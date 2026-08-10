import Foundation
import Darwin

/// Shared contract between Share Extension and app target for recipe import handoff.
nonisolated enum ShareExtensionImportContract {
    static let appGroupID = "group.Nadav.Cauldron"
    static let pendingRecipeURLKey = "shareExtension.pendingRecipeURL"
    static let pendingRecipeTextKey = "shareExtension.pendingRecipeText"
    static let preparedRecipePayloadKey = "shareExtension.preparedRecipePayload"
    static let inboxKey = "shareExtension.inbox.v1"
    static let maximumInboxItemCount = 20

    static func firstHTTPURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return validHTTPURL(from: trimmed)
        }

        let range = NSRange(location: 0, length: trimmed.utf16.count)
        let matches = detector.matches(in: trimmed, options: [], range: range)

        for match in matches {
            guard let url = match.url,
                  isHTTPURL(url) else {
                continue
            }
            return url
        }

        return validHTTPURL(from: trimmed)
    }

    static func plainTextRecipeShouldTakePrecedenceOverURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let textWithoutURLs = removingHTTPURLs(from: trimmed)
        let meaningfulLines = textWithoutURLs
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let normalized = textWithoutURLs.lowercased()

        guard !normalized.isEmpty else { return false }

        if normalized.contains("ingredients") || normalized.contains("instructions") || normalized.contains("directions") {
            return true
        }

        let hasIngredientQuantity = normalized.range(
            of: #"\b\d+([./]\d+)?\s*(cup|cups|tbsp|tablespoon|tablespoons|tsp|teaspoon|teaspoons|oz|ounce|ounces|g|gram|grams|lb|pound|pounds|ml|l)\b"#,
            options: .regularExpression
        ) != nil
        let hasCookingAction = [
            "bake", "boil", "broil", "chop", "cook", "fold", "fry", "knead",
            "mix", "preheat", "roast", "saute", "sauté", "simmer", "stir", "whisk"
        ].contains { normalized.contains($0) }

        if hasIngredientQuantity && (hasCookingAction || meaningfulLines.count >= 2) {
            return true
        }

        if meaningfulLines.count >= 4 {
            return true
        }

        return textWithoutURLs.count >= 120 && meaningfulLines.count >= 2
    }

    private static func removingHTTPURLs(from text: String) -> String {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return text
        }

        let mutable = NSMutableString(string: text)
        let range = NSRange(location: 0, length: mutable.length)
        let matches = detector.matches(in: text, options: [], range: range)
        for match in matches.reversed() {
            guard let url = match.url, isHTTPURL(url) else { continue }
            mutable.replaceCharacters(in: match.range, with: "")
        }
        return mutable.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func validHTTPURL(from string: String) -> URL? {
        guard let url = URL(string: string), isHTTPURL(url) else { return nil }
        return url
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

/// One atomic share handoff. Keeping URL/text/prepared data together prevents
/// separate UserDefaults keys from being mixed when shares arrive quickly.
nonisolated struct ShareExtensionInboxItem: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let urlString: String?
    let text: String?
    let preparedPayload: Data?

    nonisolated init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        urlString: String? = nil,
        text: String? = nil,
        preparedPayload: Data? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.urlString = urlString
        self.text = text
        self.preparedPayload = preparedPayload
    }
}

/// Cross-process-safe inbox storage. Each share is an independent atomic file,
/// so extension appends cannot overwrite one another or race app acknowledgements.
nonisolated enum ShareExtensionInboxFiles {
    enum PublicationMethod: Equatable {
        case atomicFile
        case defaultsInboxFallback
    }

    enum InboxError: Error, LocalizedError, Equatable {
        case unavailableContainer
        case inboxFull(maximumItemCount: Int)
        case fallbackPersistenceFailed
        case fallbackLockUnavailable
        case fallbackInboxCorrupt

        var errorDescription: String? {
            switch self {
            case .unavailableContainer:
                return "Cauldron couldn't access its shared storage."
            case .inboxFull(let maximumItemCount):
                return "Your Import Inbox already contains \(maximumItemCount) recipes."
            case .fallbackPersistenceFailed:
                return "Cauldron couldn't persist the shared recipe fallback."
            case .fallbackLockUnavailable:
                return "Cauldron couldn't safely coordinate shared recipe storage."
            case .fallbackInboxCorrupt:
                return "Cauldron's shared recipe storage is unreadable."
            }
        }
    }

    /// A missing payload is a confirmed empty inbox. Invalid bytes are kept
    /// distinct so callers never mistake corruption for permission to consult
    /// or mutate the older single-value mirrors.
    enum FallbackInboxState: Equatable {
        case empty
        case items([ShareExtensionInboxItem])
        case corrupt
    }

    /// The atomic transport must distinguish a genuinely empty directory from
    /// an unreadable entry. Treating corruption as emptiness can expose an
    /// older defaults/legacy payload and import the wrong recipe.
    enum AtomicInboxState {
        case unavailable
        case empty
        case items([(url: URL, item: ShareExtensionInboxItem)])
        case corrupt([URL])
    }

    private static let directoryName = "ShareExtensionInbox-v1"
    private static let fallbackLockFileName = ".ShareExtensionInboxFallback-v1.lock"
    private static let fallbackProcessLock = NSLock()

    static func enqueue(
        _ item: ShareExtensionInboxItem,
        directoryURL providedDirectoryURL: URL? = directoryURL()
    ) throws {
        guard let directory = providedDirectoryURL else {
            throw InboxError.unavailableContainer
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(item.id.uuidString).appendingPathExtension("json")

        // Retrying the same handoff remains safe even when the inbox is full.
        // New handoffs fail closed instead of deleting an older, unsaved recipe.
        if !FileManager.default.fileExists(atPath: destination.path) {
            let pendingItemCount = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ).lazy.filter { $0.pathExtension == "json" }.count
            guard pendingItemCount < ShareExtensionImportContract.maximumInboxItemCount else {
                throw InboxError.inboxFull(
                    maximumItemCount: ShareExtensionImportContract.maximumInboxItemCount
                )
            }
        }

        try JSONEncoder().encode(item).write(to: destination, options: .atomic)
    }

    /// Publishes through exactly one authoritative transport. Atomic files are
    /// preferred; the defaults inbox exists only as a compatibility fallback
    /// when shared-file storage itself is unavailable. No legacy mirrors are
    /// written after the atomic commit, so an app acknowledgement cannot race a
    /// later mirror publication and resurrect a completed share.
    @discardableResult
    static func publish(
        _ item: ShareExtensionInboxItem,
        directoryURL providedDirectoryURL: URL? = directoryURL(),
        fallbackDefaults: UserDefaults? = UserDefaults(
            suiteName: ShareExtensionImportContract.appGroupID
        ),
        fallbackLockURL providedFallbackLockURL: URL? = fallbackLockURL(),
        afterFallbackInboxRead: () -> Void = {},
        afterAtomicEnqueue: () -> Void = {}
    ) throws -> PublicationMethod {
        do {
            try enqueue(item, directoryURL: providedDirectoryURL)
            afterAtomicEnqueue()
            return .atomicFile
        } catch let error as InboxError {
            if case .inboxFull = error {
                // Never bypass the durable inbox capacity through a fallback.
                throw error
            }
        } catch {
            // A filesystem failure may still leave the app-group defaults
            // transport available for compatibility with older installations.
        }

        guard let fallbackDefaults else {
            throw InboxError.unavailableContainer
        }

        return try withFallbackInboxLock(at: providedFallbackLockURL) {
            var fallbackItems: [ShareExtensionInboxItem]
            switch fallbackInboxState(in: fallbackDefaults) {
            case .empty:
                fallbackItems = []
            case .items(let items):
                fallbackItems = items
            case .corrupt:
                throw InboxError.fallbackInboxCorrupt
            }
            afterFallbackInboxRead()
            if !fallbackItems.contains(where: { $0.id == item.id }) {
                guard fallbackItems.count < ShareExtensionImportContract.maximumInboxItemCount else {
                    throw InboxError.inboxFull(
                        maximumItemCount: ShareExtensionImportContract.maximumInboxItemCount
                    )
                }
                fallbackItems.append(item)
            }

            try persistFallbackInbox(fallbackItems, in: fallbackDefaults)
            return .defaultsInboxFallback
        }
    }

    static func fallbackLockURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ShareExtensionImportContract.appGroupID)?
            .appendingPathComponent(fallbackLockFileName)
    }

    static func withFallbackInboxLock<Result>(
        at providedLockURL: URL? = fallbackLockURL(),
        _ operation: () throws -> Result
    ) throws -> Result {
        guard let lockURL = providedLockURL else {
            throw InboxError.fallbackLockUnavailable
        }

        // POSIX record locks coordinate separate processes. The in-process
        // lock supplies the equivalent exclusion between threads because
        // fcntl locks are owned by the process rather than an individual fd.
        fallbackProcessLock.lock()
        defer { fallbackProcessLock.unlock() }

        do {
            try FileManager.default.createDirectory(
                at: lockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw InboxError.fallbackLockUnavailable
        }

        let descriptor = lockURL.path.withCString {
            Darwin.open($0, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw InboxError.fallbackLockUnavailable
        }
        defer { Darwin.close(descriptor) }

        var lock = Darwin.flock()
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)
        guard Darwin.fcntl(descriptor, F_SETLKW, &lock) == 0 else {
            throw InboxError.fallbackLockUnavailable
        }
        defer {
            lock.l_type = Int16(F_UNLCK)
            _ = Darwin.fcntl(descriptor, F_SETLK, &lock)
        }

        return try operation()
    }

    static func fallbackInboxState(in defaults: UserDefaults) -> FallbackInboxState {
        guard let data = defaults.data(forKey: ShareExtensionImportContract.inboxKey) else {
            return .empty
        }
        guard let items = try? JSONDecoder().decode([ShareExtensionInboxItem].self, from: data) else {
            return .corrupt
        }
        return items.isEmpty ? .empty : .items(items.sorted(by: inboxOrder))
    }

    static func persistFallbackInbox(
        _ items: [ShareExtensionInboxItem],
        in defaults: UserDefaults
    ) throws {
        if items.isEmpty {
            defaults.removeObject(forKey: ShareExtensionImportContract.inboxKey)
            guard defaults.data(forKey: ShareExtensionImportContract.inboxKey) == nil else {
                throw InboxError.fallbackPersistenceFailed
            }
            return
        }

        let encoded = try JSONEncoder().encode(items.sorted(by: inboxOrder))
        defaults.set(encoded, forKey: ShareExtensionImportContract.inboxKey)
        guard defaults.data(forKey: ShareExtensionImportContract.inboxKey) == encoded else {
            throw InboxError.fallbackPersistenceFailed
        }
    }

    private static func inboxOrder(
        _ lhs: ShareExtensionInboxItem,
        _ rhs: ShareExtensionInboxItem
    ) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.createdAt < rhs.createdAt
    }

    static func atomicInboxState(
        directoryURL providedDirectoryURL: URL? = directoryURL()
    ) -> AtomicInboxState {
        guard let directory = providedDirectoryURL else { return .unavailable }
        guard FileManager.default.fileExists(atPath: directory.path) else { return .empty }
        guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            // The container exists, so a read failure may hide authoritative
            // items. It is not equivalent to an unavailable app-group path.
            return .corrupt([directory])
        }

        let inboxURLs = urls.filter { $0.pathExtension == "json" }
        guard !inboxURLs.isEmpty else { return .empty }

        var decoded: [(url: URL, item: ShareExtensionInboxItem)] = []
        var corrupt: [URL] = []
        for url in inboxURLs {
            guard let data = try? Data(contentsOf: url),
                  let item = try? JSONDecoder().decode(ShareExtensionInboxItem.self, from: data) else {
                corrupt.append(url)
                continue
            }
            decoded.append((url, item))
        }

        // Preserve unreadable handoffs for recovery/support. We cannot safely
        // skip them because their creation timestamp and FIFO position are not
        // trustworthy, so the entire authoritative queue fails closed.
        guard corrupt.isEmpty else { return .corrupt(corrupt) }

        decoded.sort {
            if $0.item.createdAt == $1.item.createdAt {
                return $0.item.id.uuidString < $1.item.id.uuidString
            }
            return $0.item.createdAt < $1.item.createdAt
        }
        return decoded.isEmpty ? .empty : .items(decoded)
    }

    static func items(
        directoryURL providedDirectoryURL: URL? = directoryURL()
    ) -> [(url: URL, item: ShareExtensionInboxItem)] {
        switch atomicInboxState(directoryURL: providedDirectoryURL) {
        case .items(let items):
            return items
        case .unavailable, .empty, .corrupt:
            return []
        }
    }

    static func remove(id: UUID) {
        guard let directory = directoryURL() else { return }
        let url = directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        try? FileManager.default.removeItem(at: url)
    }

    static func directoryURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ShareExtensionImportContract.appGroupID)?
            .appendingPathComponent(directoryName, isDirectory: true)
    }
}

/// Transport payload written by the Share Extension and consumed by the app.
nonisolated struct PreparedShareRecipePayload: Codable, Sendable {
    let title: String
    let ingredients: [String]
    let steps: [String]
    let yields: String?
    let totalMinutes: Int?
    let sourceURL: String?
    let sourceTitle: String?
    let imageURL: String?
    let tagNames: [String]
    let notes: String?

    private enum CodingKeys: String, CodingKey {
        case title
        case ingredients
        case steps
        case yields
        case totalMinutes
        case sourceURL
        case sourceTitle
        case imageURL
        case tagNames
        case notes
    }

    nonisolated init(
        title: String,
        ingredients: [String],
        steps: [String],
        yields: String? = nil,
        totalMinutes: Int? = nil,
        sourceURL: String? = nil,
        sourceTitle: String? = nil,
        imageURL: String? = nil,
        tagNames: [String] = [],
        notes: String? = nil
    ) {
        self.title = title
        self.ingredients = ingredients
        self.steps = steps
        self.yields = yields
        self.totalMinutes = totalMinutes
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.imageURL = imageURL
        self.tagNames = tagNames
        self.notes = notes
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.ingredients = try container.decode([String].self, forKey: .ingredients)
        self.steps = try container.decode([String].self, forKey: .steps)
        self.yields = try container.decodeIfPresent(String.self, forKey: .yields)
        self.totalMinutes = try container.decodeIfPresent(Int.self, forKey: .totalMinutes)
        self.sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        self.sourceTitle = try container.decodeIfPresent(String.self, forKey: .sourceTitle)
        self.imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        self.tagNames = try container.decodeIfPresent([String].self, forKey: .tagNames) ?? []
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(ingredients, forKey: .ingredients)
        try container.encode(steps, forKey: .steps)
        try container.encodeIfPresent(yields, forKey: .yields)
        try container.encodeIfPresent(totalMinutes, forKey: .totalMinutes)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(sourceTitle, forKey: .sourceTitle)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        if !tagNames.isEmpty {
            try container.encode(tagNames, forKey: .tagNames)
        }
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}
