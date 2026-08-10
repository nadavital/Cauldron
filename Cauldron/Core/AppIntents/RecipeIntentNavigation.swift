import Darwin
import Foundation

enum RecipeIntentNavigationStore {
    nonisolated static let appGroupID = CookSessionSharedStore.appGroupID
    nonisolated static let pendingRecipeIDKey = "appIntent.pendingRoute.v2"
    nonisolated static let pendingVisualRecipeIDsKey = pendingRecipeIDKey

    nonisolated private enum Route: Codable, Equatable {
        case recipe(UUID)
        case visualSearch([UUID])
    }

    nonisolated private struct Envelope: Codable, Equatable {
        let id: UUID
        let createdAt: Date
        let route: Route
    }

    nonisolated static func save(
        recipeID: UUID,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) {
        save(route: .recipe(recipeID), defaults: defaults)
    }

    nonisolated static func pendingRecipeID(
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) -> UUID? {
        withExclusiveLock {
            guard case .recipe(let recipeID) = readUnlocked(defaults: defaults)?.route else {
                return nil
            }
            return recipeID
        }
    }

    @discardableResult
    nonisolated static func consume(
        expectedRecipeID: UUID? = nil,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) -> UUID? {
        withExclusiveLock {
            guard let envelope = readUnlocked(defaults: defaults),
                  case .recipe(let recipeID) = envelope.route,
                  expectedRecipeID == nil || expectedRecipeID == recipeID else {
                return nil
            }
            defaults?.removeObject(forKey: pendingRecipeIDKey)
            return recipeID
        }
    }

    nonisolated static func saveVisualSearch(
        recipeIDs: [UUID],
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) {
        save(route: .visualSearch(recipeIDs), defaults: defaults)
    }

    nonisolated static func hasPendingVisualSearch(
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) -> Bool {
        withExclusiveLock {
            guard case .visualSearch = readUnlocked(defaults: defaults)?.route else { return false }
            return true
        }
    }

    nonisolated static func pendingVisualSearch(
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) -> [UUID] {
        withExclusiveLock {
            guard case .visualSearch(let recipeIDs) = readUnlocked(defaults: defaults)?.route else {
                return []
            }
            return recipeIDs
        }
    }

    @discardableResult
    nonisolated static func consumeVisualSearch(
        expectedRecipeIDs: [UUID],
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) -> Bool {
        withExclusiveLock {
            guard let envelope = readUnlocked(defaults: defaults),
                  case .visualSearch(let recipeIDs) = envelope.route,
                  recipeIDs == expectedRecipeIDs else {
                return false
            }
            defaults?.removeObject(forKey: pendingRecipeIDKey)
            return true
        }
    }

    nonisolated private static func save(route: Route, defaults: UserDefaults?) {
        withExclusiveLock {
            let envelope = Envelope(id: UUID(), createdAt: Date(), route: route)
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            defaults?.set(data, forKey: pendingRecipeIDKey)
        }
    }

    nonisolated private static func readUnlocked(defaults: UserDefaults?) -> Envelope? {
        guard let data = defaults?.data(forKey: pendingRecipeIDKey),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            if defaults?.object(forKey: pendingRecipeIDKey) != nil {
                defaults?.removeObject(forKey: pendingRecipeIDKey)
            }
            return nil
        }
        return envelope
    }

    nonisolated private static func withExclusiveLock<T>(_ body: () -> T) -> T {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return body()
        }
        let lockURL = container.appendingPathComponent("RecipeIntentNavigation.lock")
        let descriptor = lockURL.path.withCString {
            open($0, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { return body() }
        flock(descriptor, LOCK_EX)
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        return body()
    }
}
