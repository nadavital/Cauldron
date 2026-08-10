import Foundation
import Observation

/// A small, device-local history of searches the user explicitly submitted.
/// Keystrokes are never recorded; callers opt in only at meaningful commit
/// points such as Search submission or opening a result.
@MainActor
@Observable
final class SearchHistoryStore {
    private(set) var entries: [String]

    private let defaults: UserDefaults
    private let baseKey: String
    private let limit: Int
    private var ownerID: UUID?

    init(
        defaults: UserDefaults = .standard,
        key: String = "search.history.recipes.v1",
        ownerID: UUID? = nil,
        limit: Int = 10
    ) {
        self.defaults = defaults
        self.baseKey = key
        self.ownerID = ownerID
        self.limit = max(1, limit)
        self.entries = Self.sanitizedEntries(
            defaults.stringArray(forKey: Self.storageKey(baseKey: key, ownerID: ownerID)) ?? [],
            limit: max(1, limit)
        )
    }

    /// Switches to the active account's device-local history. The anonymous
    /// namespace is intentionally separate so no account can see another
    /// account's submitted searches during sign-in transitions.
    func selectOwner(_ ownerID: UUID?) {
        guard self.ownerID != ownerID else { return }
        self.ownerID = ownerID
        entries = Self.sanitizedEntries(
            defaults.stringArray(forKey: storageKey) ?? [],
            limit: limit
        )
    }

    func record(_ query: String) {
        guard let displayQuery = Self.displayQuery(from: query) else { return }
        let identity = Self.identity(for: displayQuery)

        entries.removeAll { Self.identity(for: $0) == identity }
        entries.insert(displayQuery, at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        persist()
    }

    func remove(_ query: String) {
        let identity = Self.identity(for: query)
        entries.removeAll { Self.identity(for: $0) == identity }
        persist()
    }

    func clear() {
        entries = []
        defaults.removeObject(forKey: storageKey)
    }

    nonisolated static func displayQuery(from query: String) -> String? {
        let collapsed = query
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    private nonisolated static func identity(for query: String) -> String {
        (displayQuery(from: query) ?? "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private nonisolated static func sanitizedEntries(_ entries: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            guard let displayQuery = displayQuery(from: entry) else { continue }
            let identity = identity(for: displayQuery)
            guard seen.insert(identity).inserted else { continue }
            result.append(displayQuery)
            if result.count == limit { break }
        }
        return result
    }

    private func persist() {
        defaults.set(entries, forKey: storageKey)
    }

    private var storageKey: String {
        Self.storageKey(baseKey: baseKey, ownerID: ownerID)
    }

    private nonisolated static func storageKey(baseKey: String, ownerID: UUID?) -> String {
        "\(baseKey).\(ownerID?.uuidString.lowercased() ?? "anonymous")"
    }
}
