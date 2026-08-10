import Foundation

actor RecipeImportInboxStore {
    struct EnqueueIfAbsentResult: Sendable, Equatable {
        enum Disposition: Sendable, Equatable {
            case enqueued
            case alreadyQueued
            case retried
        }

        let job: RecipeImportJob
        let disposition: Disposition
    }

    enum StoreError: Error, Equatable {
        case jobNotFound
        case invalidTransition
        case payloadTooLarge(maximumBytes: Int)
        case jobFileTooLarge(maximumBytes: Int)
    }

    /// Import jobs store already-extracted recipe data rather than source HTML.
    /// These generous limits reject pathological handoffs without affecting
    /// normal or legacy schema-v1 jobs.
    nonisolated static let maximumPayloadBytes = 1_000_000
    nonisolated static let maximumJobFileBytes = 2_000_000

    private let directoryURL: URL
    private let quarantineURL: URL
    private let unsupportedURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let root = directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
        self.directoryURL = root
        self.quarantineURL = root.appendingPathComponent("Corrupt", isDirectory: true)
        self.unsupportedURL = root.appendingPathComponent("Unsupported", isDirectory: true)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    @discardableResult
    func enqueue(source: RecipeImportJob.Source, now: Date = Date()) throws -> RecipeImportJob {
        let job = RecipeImportJob(createdAt: now, source: source)
        try persist(job)
        notifyChange()
        return job
    }

    /// Enqueues user-provided URL or text imports once while an equivalent job
    /// is still pending. This makes Siri and Shortcuts retries safe without
    /// preventing a user from importing the same recipe again after completion.
    @discardableResult
    func enqueueIfAbsent(source: RecipeImportJob.Source, now: Date = Date()) throws -> RecipeImportJob {
        try enqueueIfAbsentWithDisposition(source: source, now: now).job
    }

    /// Atomically deduplicates an import while also reporting whether the
    /// request created, reused, or retried a durable inbox job.
    @discardableResult
    func enqueueIfAbsentWithDisposition(
        source: RecipeImportJob.Source,
        now: Date = Date()
    ) throws -> EnqueueIfAbsentResult {
        if let sourceKey = Self.idempotencyKey(for: source),
           var existing = try jobs().first(where: {
               $0.state != .completed && Self.idempotencyKey(for: $0.source) == sourceKey
           }) {
            if existing.state == .failed {
                existing.state = .received
                existing.updatedAt = now
                existing.processingStartedAt = nil
                existing.lastErrorCategory = nil
                try persist(existing)
                notifyChange()
                return EnqueueIfAbsentResult(job: existing, disposition: .retried)
            }
            return EnqueueIfAbsentResult(job: existing, disposition: .alreadyQueued)
        }
        return EnqueueIfAbsentResult(
            job: try enqueue(source: source, now: now),
            disposition: .enqueued
        )
    }

    @discardableResult
    func ingest(_ item: ShareExtensionInboxItem, now: Date = Date()) throws -> RecipeImportJob {
        if let existing = try jobs().first(where: { job in
            if case .shareTransport(let persisted) = job.source {
                return persisted.id == item.id
            }
            return false
        }) {
            return existing
        }
        return try enqueue(source: .shareTransport(item), now: now)
    }

    func jobs() throws -> [RecipeImportJob] {
        try ensureDirectory()
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ).filter { $0.pathExtension == "json" }

        var decoded: [RecipeImportJob] = []
        decoded.reserveCapacity(urls.count)
        for url in urls {
            do {
                decoded.append(try decodeJob(at: url))
            } catch let error as RecipeImportJobCodingError {
                if case .unsupportedSchema = error {
                    quarantine(url, destinationDirectory: unsupportedURL)
                }
            } catch {
                quarantine(url, destinationDirectory: quarantineURL)
            }
        }
        return decoded.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.createdAt < $1.createdAt
        }
    }

    func job(id: UUID) throws -> RecipeImportJob? {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try decodeJob(at: url)
        } catch let error as RecipeImportJobCodingError {
            if case .unsupportedSchema = error {
                quarantine(url, destinationDirectory: unsupportedURL)
            }
            return nil
        } catch {
            quarantine(url, destinationDirectory: quarantineURL)
            return nil
        }
    }

    /// Removes every durable import handoff, including quarantined payloads.
    /// Cauldron is single-account per installation, so account deletion must
    /// not leave recipe content received under the deleted account on disk.
    func removeAll() throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.removeItem(at: directoryURL)
        notifyChange()
    }

    @discardableResult
    func claimNext(now: Date = Date()) throws -> RecipeImportJob? {
        // Failed jobs require an explicit retry transition. This prevents one
        // poison import from starving all newer received work.
        guard var job = try jobs().first(where: { $0.state == .received }) else {
            return nil
        }
        job.state = .processing
        job.attemptCount += 1
        job.updatedAt = now
        job.processingStartedAt = now
        job.lastErrorCategory = nil
        try persist(job)
        notifyChange()
        return job
    }

    @discardableResult
    func transition(
        id: UUID,
        to state: RecipeImportJob.State,
        errorCategory: String? = nil,
        now: Date = Date()
    ) throws -> RecipeImportJob {
        guard var job = try job(id: id) else { throw StoreError.jobNotFound }
        guard Self.canTransition(from: job.state, to: state) else {
            throw StoreError.invalidTransition
        }
        job.state = state
        job.updatedAt = now
        job.lastErrorCategory = errorCategory
        if state != .processing {
            job.processingStartedAt = nil
        }
        try persist(job)
        notifyChange()
        return job
    }

    func recoverStaleProcessing(before cutoff: Date, now: Date = Date()) throws -> Int {
        var recovered = 0
        for var job in try jobs() where job.state == .processing {
            guard let startedAt = job.processingStartedAt, startedAt < cutoff else { continue }
            job.state = .received
            job.updatedAt = now
            job.processingStartedAt = nil
            job.lastErrorCategory = "interrupted"
            try persist(job)
            recovered += 1
        }
        if recovered > 0 {
            notifyChange()
        }
        return recovered
    }

    func remove(id: UUID) throws {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
        notifyChange()
    }

    /// Persists completion before cleanup. If deletion fails, the durable
    /// completed marker prevents the recipe from being offered for saving a
    /// second time and can be cleaned up on a later maintenance pass.
    func complete(id: UUID, now: Date = Date()) throws {
        _ = try transition(id: id, to: .completed, now: now)
        try? remove(id: id)
    }

    private func persist(_ job: RecipeImportJob) throws {
        try ensureDirectory()
        let url = fileURL(for: job.id)
        guard Self.payloadByteCount(for: job.source) <= Self.maximumPayloadBytes else {
            throw StoreError.payloadTooLarge(maximumBytes: Self.maximumPayloadBytes)
        }
        let data = try encoder.encode(job)
        guard data.count <= Self.maximumJobFileBytes else {
            throw StoreError.jobFileTooLarge(maximumBytes: Self.maximumJobFileBytes)
        }
        try data.write(to: url, options: [.atomic])
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .recipeImportInboxChanged, object: nil)
    }

    private func decodeJob(at url: URL) throws -> RecipeImportJob {
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard resourceValues.isRegularFile != false else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let fileSize = resourceValues.fileSize,
           fileSize > Self.maximumJobFileBytes {
            throw StoreError.jobFileTooLarge(maximumBytes: Self.maximumJobFileBytes)
        }

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= Self.maximumJobFileBytes else {
            // Recheck after opening to close the gap if another process replaced
            // or enlarged the file after its metadata was read.
            throw StoreError.jobFileTooLarge(maximumBytes: Self.maximumJobFileBytes)
        }
        return try decoder.decode(RecipeImportJob.self, from: data)
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = directoryURL
        try? mutableURL.setResourceValues(values)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directoryURL.path
        )
    }

    private func quarantine(_ url: URL, destinationDirectory: URL) {
        do {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            applyPrivacyAttributes(to: destinationDirectory, excludeFromBackup: true)
            let destination = destinationDirectory.appendingPathComponent(
                "\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).json"
            )
            try fileManager.moveItem(at: url, to: destination)
            applyPrivacyAttributes(to: destination, excludeFromBackup: false)
        } catch {
            // Enumeration must remain available even if forensic quarantine
            // cannot be written because storage is full or permissions changed.
        }
    }

    private func applyPrivacyAttributes(to url: URL, excludeFromBackup: Bool) {
        if excludeFromBackup {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(values)
        }
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func fileURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    nonisolated private static func defaultDirectory(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("Cauldron", isDirectory: true)
            .appendingPathComponent("RecipeImportInbox-v1", isDirectory: true)
    }

    nonisolated private static func canTransition(
        from current: RecipeImportJob.State,
        to next: RecipeImportJob.State
    ) -> Bool {
        switch (current, next) {
        case (.received, .needsReview),
             (.received, .failed),
             (.received, .completed),
             (.processing, .needsReview),
             (.processing, .ready),
             (.processing, .failed),
             (.needsReview, .ready),
             (.needsReview, .completed),
             (.ready, .completed),
             (.processing, .completed),
             (.failed, .received):
            return true
        default:
            return current == next
        }
    }

    nonisolated private static func idempotencyKey(for source: RecipeImportJob.Source) -> String? {
        switch source {
        case .url(let value):
            return "url:\(canonicalURLString(value))"
        case .text(let value):
            return "text:\(normalizedText(value))"
        case .prepared, .shareTransport:
            return nil
        }
    }

    nonisolated private static func payloadByteCount(for source: RecipeImportJob.Source) -> Int {
        switch source {
        case .url(let value), .text(let value):
            return value.utf8.count
        case .prepared(let data):
            return data.count
        case .shareTransport(let item):
            return (item.urlString?.utf8.count ?? 0)
                + (item.text?.utf8.count ?? 0)
                + (item.preparedPayload?.count ?? 0)
        }
    }

    nonisolated private static func canonicalURLString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else {
            return trimmed
        }

        components.scheme = scheme
        components.host = host
        components.fragment = nil
        if (scheme == "http" && components.port == 80)
            || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        return components.string ?? trimmed
    }

    nonisolated private static func normalizedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
