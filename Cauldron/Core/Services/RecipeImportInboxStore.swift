import Foundation

actor RecipeImportInboxStore {
    enum StoreError: Error, Equatable {
        case jobNotFound
        case invalidTransition
    }

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
        return job
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
                let data = try Data(contentsOf: url)
                decoded.append(try decoder.decode(RecipeImportJob.self, from: data))
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
            return try decoder.decode(RecipeImportJob.self, from: Data(contentsOf: url))
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
        return recovered
    }

    func remove(id: UUID) throws {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
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
        try encoder.encode(job).write(to: url, options: [.atomic])
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
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
}
