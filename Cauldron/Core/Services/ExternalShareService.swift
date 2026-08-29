//
//  ExternalShareService.swift
//  Cauldron
//
//  Service for generating external shareable links for recipes, profiles, and collections
//

import Foundation
import UIKit
import CloudKit
import CryptoKit
import os

enum WebShareCanonicalURL {
    static let origin = URL(string: "https://cauldronrecipes.com")!

    static func recipe(id: UUID) -> URL {
        origin.appending(path: "recipe").appending(path: id.uuidString)
    }
}

/// Remembers the exact public recipe revision that Firebase confirmed. The
/// canonical URL itself is deterministic; this receipt only decides whether a
/// share action needs to wait for publication before presenting that URL.
struct WebSharePublicationReceiptStore {
    private let defaults: UserDefaults
    private let storageKey = "webShare.recipePublicationReceipts.v2"
    private let maximumReceiptCount = 2_000
    private let maximumReceiptAge: TimeInterval = 90 * 24 * 60 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func containsCurrentRevision(of recipe: Recipe) -> Bool {
        guard let ownerID = recipe.ownerId else { return false }
        guard let receipt = parsedReceipt(
            receipts[receiptKey(ownerID: ownerID, recipeID: recipe.id)]
        ) else { return false }
        guard Date().timeIntervalSince1970 - receipt.recordedAt <= maximumReceiptAge else {
            return false
        }
        return receipt.fingerprint == publicationFingerprint(for: recipe)
    }

    func record(_ recipe: Recipe) {
        guard let ownerID = recipe.ownerId else { return }
        var updated = receipts
        updated[receiptKey(ownerID: ownerID, recipeID: recipe.id)] = [
            String(Date().timeIntervalSince1970),
            publicationFingerprint(for: recipe),
        ].joined(separator: "|")
        if updated.count > maximumReceiptCount {
            let overflow = updated.count - maximumReceiptCount
            for key in updated
                .sorted(by: { receiptTimestamp($0.value) < receiptTimestamp($1.value) })
                .prefix(overflow)
                .map(\.key) {
                updated.removeValue(forKey: key)
            }
        }
        defaults.set(updated, forKey: storageKey)
    }

    func remove(recipeID: UUID, ownerID: UUID) {
        var updated = receipts
        updated.removeValue(forKey: receiptKey(ownerID: ownerID, recipeID: recipeID))
        defaults.set(updated, forKey: storageKey)
    }

    func removeAll(ownerID: UUID) {
        let prefix = "\(ownerID.uuidString.lowercased())|"
        defaults.set(receipts.filter { !$0.key.hasPrefix(prefix) }, forKey: storageKey)
    }

    private var receipts: [String: String] {
        defaults.dictionary(forKey: storageKey)?.reduce(into: [:]) { result, entry in
            if let value = entry.value as? String {
                result[entry.key] = value
            }
        } ?? [:]
    }

    private func parsedReceipt(_ value: String?) -> (recordedAt: TimeInterval, fingerprint: String)? {
        guard let value,
              let separator = value.firstIndex(of: "|"),
              let recordedAt = TimeInterval(value[..<separator]) else { return nil }
        let fingerprint = String(value[value.index(after: separator)...])
        guard !fingerprint.isEmpty else { return nil }
        return (recordedAt, fingerprint)
    }

    private func receiptTimestamp(_ value: String) -> TimeInterval {
        parsedReceipt(value)?.recordedAt ?? 0
    }

    /// Firebase stores only this summary pointer. Full recipe content is read
    /// from CloudKit when the page renders, so favorites, notes, ingredients,
    /// instructions, and timestamps must not trigger redundant publication.
    private func publicationFingerprint(for recipe: Recipe) -> String {
        let normalizedTags = recipe.tags
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let input = [
            recipe.title.trimmingCharacters(in: .whitespacesAndNewlines),
            recipe.totalMinutes.map(String.init) ?? "",
            normalizedTags.joined(separator: "\u{1F}"),
        ].joined(separator: "\u{1E}")
        return SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func receiptKey(ownerID: UUID, recipeID: UUID) -> String {
        "\(ownerID.uuidString.lowercased())|\(recipeID.uuidString.lowercased())"
    }
}

/// Errors that can occur during external sharing
enum ExternalShareError: LocalizedError {
    case invalidRecipe
    case invalidProfile
    case invalidCollection
    case networkError(Error)
    case invalidResponse
    case temporarilyUnavailable
    case notPublic
    case imageUploadFailed
    case accountDeletionInProgress

    var errorDescription: String? {
        switch self {
        case .invalidRecipe:
            return "Invalid recipe data"
        case .invalidProfile:
            return "Invalid profile data"
        case .invalidCollection:
            return "Invalid collection data"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .temporarilyUnavailable:
            return "The sharing service is temporarily unavailable"
        case .notPublic:
            return "Only public recipes and collections can be shared externally"
        case .imageUploadFailed:
            return "Failed to upload image to cloud"
        case .accountDeletionInProgress:
            return "Account deletion is in progress"
        }
    }
}

/// Registers the private, account-wide web-share credential with the public
/// profile record. A same-generation hash mismatch can be left behind by an
/// older client or interrupted migration; rotating the private credential
/// advances the generation so the public record can be repaired safely.
@MainActor
enum WebShareCapabilityRegistrationWorkflow {
    static func recover(
        maxAttempts: Int = 3,
        resolve: () async throws -> UserCloudService.WebShareCredential,
        rotate: () async throws -> UserCloudService.WebShareCredential,
        register: (UserCloudService.WebShareCredential) async throws -> Bool
    ) async throws -> UserCloudService.WebShareCredential {
        precondition(maxAttempts > 0)

        var credential = try await resolve()
        for attempt in 1...maxAttempts {
            do {
                if try await register(credential) {
                    return credential
                }

                guard attempt < maxAttempts else {
                    throw ExternalShareError.invalidProfile
                }
                // A false result means the public record has a newer
                // generation. Re-read the private authority before retrying.
                credential = try await resolve()
            } catch let error as CloudKitError where error == .webShareCapabilityConflict {
                guard attempt < maxAttempts else { throw error }
                // Equal generations with different hashes cannot be merged.
                // Advance the private authority and register that generation.
                credential = try await rotate()
            }
        }

        throw ExternalShareError.invalidProfile
    }
}

/// Keeps one owner's credential registration and backend mutation atomic with
/// respect to other in-process share operations. Main-actor methods are
/// reentrant across awaits, so actor isolation alone does not close this race.
@MainActor
final class WebShareOwnerMutationCoordinator {
    private var activeOwners: Set<UUID> = []
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    func perform<T>(
        ownerID: UUID,
        operation: () async throws -> T
    ) async throws -> T {
        await acquire(ownerID: ownerID)
        defer { release(ownerID: ownerID) }
        // A task can be cancelled while its continuation is queued. Never let
        // that stale request mutate CloudKit or Firebase once it gets a turn.
        try Task.checkCancellation()
        return try await operation()
    }

    func queuedMutationCount(for ownerID: UUID) -> Int {
        waiters[ownerID]?.count ?? 0
    }

    private func acquire(ownerID: UUID) async {
        guard activeOwners.contains(ownerID) else {
            activeOwners.insert(ownerID)
            return
        }
        await withCheckedContinuation { continuation in
            waiters[ownerID, default: []].append(continuation)
        }
    }

    private func release(ownerID: UUID) {
        guard var ownerWaiters = waiters[ownerID], !ownerWaiters.isEmpty else {
            activeOwners.remove(ownerID)
            waiters[ownerID] = nil
            return
        }
        let next = ownerWaiters.removeFirst()
        waiters[ownerID] = ownerWaiters.isEmpty ? nil : ownerWaiters
        next.resume()
    }
}

/// Service for creating and importing external share links
@MainActor
final class ExternalShareService: Sendable {
    private let logger = Logger(subsystem: "com.cauldron", category: "ExternalShareService")

    // Backend API configuration
    // Firebase Functions URL
    private let baseURL = "https://us-central1-cauldron-f900a.cloudfunctions.net"

    private let session: URLSession
    private let userCloudService: UserCloudService?
    private let mutationCoordinator = WebShareOwnerMutationCoordinator()
    private let publicationReceipts: WebSharePublicationReceiptStore

    init(
        imageManager _: RecipeImageManager,
        userCloudService: UserCloudService? = nil,
        publicationDefaults: UserDefaults = .standard
    ) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        self.userCloudService = userCloudService
        self.publicationReceipts = WebSharePublicationReceiptStore(defaults: publicationDefaults)
    }

    // MARK: - Share Link Generation

    /// Generate a shareable link for a recipe (Local only - deterministic)
    func generateShareLink(for recipe: Recipe) -> ShareableLink {
        let previewText = "Check out my recipe for \(recipe.title) on Cauldron!"

        return ShareableLink(
            url: WebShareCanonicalURL.recipe(id: recipe.id),
            previewText: previewText,
            image: nil // Caller can attach image if they have it, or we can load it if we make this async
        )
    }

    /// Update share metadata on the backend (Fire-and-forget style)
    /// This should be called when a recipe is saved/updated and is PUBLIC
    @discardableResult
    func updateShareMetadata(for recipe: Recipe) async -> Bool {
        guard recipe.visibility == .publicRecipe else { return true }
        guard !publicationReceipts.containsCurrentRevision(of: recipe) else {
            logger.debug("Skipping unchanged recipe publication: \(recipe.title)")
            return true
        }

        logger.info("🔄 Updating share metadata for recipe: \(recipe.title)")

        do {
            let response = try await publishRecipeShareMetadata(for: recipe, shouldCreate: true)
            guard response.published == true else {
                logger.warning("Recipe publication endpoint did not write a snapshot")
                return false
            }
            publicationReceipts.record(recipe)
            logger.info("✅ Share metadata updated successfully")
            return true
        } catch {
            logger.error("❌ Failed to update share metadata: \(error.localizedDescription)")
            return false
        }
    }

    /// Removes a public web snapshot. This is awaited by visibility/deletion sync
    /// so a recipe does not remain readable after it is made private.
    func removeShareMetadata(for recipe: Recipe) async throws {
        guard let ownerId = recipe.ownerId else {
            throw ExternalShareError.invalidRecipe
        }

        try await mutationCoordinator.perform(ownerID: ownerId) {
            let context = try await registeredOwnerContext(ownerId: ownerId)
            let metadata = ShareMetadata.RecipeUnshare(
                recipeId: recipe.id.uuidString,
                ownerId: ownerId.uuidString,
                identityRecordName: context.identityRecordName,
                capability: context.capability
            )
            guard let publicationLease = await AccountDeletionGate.shared.acquirePublicationLease(ownerID: ownerId) else {
                throw ExternalShareError.accountDeletionInProgress
            }
            defer { Task { await AccountDeletionGate.shared.releasePublicationLease(publicationLease) } }
            let response: UnshareResponse = try await post(endpoint: "/unshareRecipeV2", metadata: metadata)
            guard response.success else {
                throw ExternalShareError.invalidResponse
            }
            publicationReceipts.remove(recipeID: recipe.id, ownerID: ownerId)
            try await rotateManagementCapability(forOwnerID: ownerId)
        }
    }

    /// Legacy support - calls generate and optionally updates metadata
    func shareRecipe(_ recipe: Recipe) async throws -> ShareableLink {
        guard recipe.visibility == .publicRecipe else {
            throw ExternalShareError.notPublic
        }

        // Only the owner can publish or mutate the snapshot. Other users may
        // reshare its stable owner-managed URL without minting credentials.
        guard CurrentUserSession.shared.userId == recipe.ownerId else {
            let link = generateShareLink(for: recipe)
            return ShareableLink(
                url: link.url,
                previewText: link.previewText,
                image: UIImage(named: "BrandMarks/CauldronIcon")
            )
        }

        if publicationReceipts.containsCurrentRevision(of: recipe) {
            let link = generateShareLink(for: recipe)
            return ShareableLink(
                url: link.url,
                previewText: link.previewText,
                image: UIImage(named: "BrandMarks/CauldronIcon")
            )
        }

        let response = try await publishRecipeShareMetadata(for: recipe, shouldCreate: true)
        guard response.published == true else {
            throw ExternalShareError.invalidResponse
        }

        guard URL(string: response.shareUrl) == WebShareCanonicalURL.recipe(id: recipe.id) else {
            throw ExternalShareError.invalidResponse
        }
        publicationReceipts.record(recipe)
        let link = generateShareLink(for: recipe)
        return ShareableLink(
            url: link.url,
            previewText: link.previewText,
            image: UIImage(named: "BrandMarks/CauldronIcon")
        )
    }

    /// Generate a shareable link for a profile (Local only)
    func generateProfileLink(for user: User, recipeCount: Int) -> ShareableLink {
        // URL-encode username to handle special characters safely
        let encodedUsername = user.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user.username
        let permanentURLString = "https://cauldronrecipes.com/u/\(encodedUsername)"
        let recipeText = recipeCount == 1 ? "1 recipe" : "\(recipeCount) recipes"
        let previewText = "Check out my Cauldron profile! \(recipeText) and counting 🍲"

        // Safely construct URL, falling back to ID-based URL if username encoding fails
        let url: URL
        if let constructedURL = URL(string: permanentURLString) {
            url = constructedURL
        } else {
            let fallbackURLString = "https://cauldronrecipes.com/profile/\(user.id.uuidString)"
            url = URL(string: fallbackURLString)!
        }

        return ShareableLink(
            url: url,
            previewText: previewText,
            image: nil
        )
    }

    /// Update profile share metadata on the backend
    func updateProfileShareMetadata(for user: User, recipeCount: Int? = nil) async -> Bool {
        logger.info("🔄 Updating share metadata for profile: \(user.username)")

        do {
            let response = try await publishProfileShareMetadata(
                for: user,
                recipeCount: recipeCount,
                shouldCreate: true
            )
            guard response.published == true else {
                logger.warning("Profile publication endpoint did not write a snapshot")
                return false
            }
            logger.info("✅ Profile metadata updated successfully")
            return true
        } catch {
             logger.error("❌ Failed to update profile metadata: \(error.localizedDescription)")
            return false
        }
    }

    /// Generate a shareable link for a user profile
    func shareProfile(_ user: User, recipeCount: Int) async throws -> ShareableLink {
        // Ensure the web page exists before presenting a link that can be opened.
        let response = try await publishProfileShareMetadata(
            for: user,
            recipeCount: recipeCount,
            shouldCreate: true
        )
        guard response.published == true else {
            throw ExternalShareError.invalidResponse
        }
        guard let publishedURL = URL(string: response.shareUrl) else {
            throw ExternalShareError.invalidResponse
        }

        let recipeText = recipeCount == 1 ? "1 recipe" : "\(recipeCount) recipes"
        return ShareableLink(
            url: publishedURL,
            previewText: "Check out my Cauldron profile! \(recipeText) and counting 🍲",
            image: UIImage(named: "BrandMarks/CauldronIcon")
        )
    }

    private func publishRecipeShareMetadata(
        for recipe: Recipe,
        shouldCreate: Bool
    ) async throws -> ShareResponse {
        guard await AccountDeletionGate.shared.permitsWrite(ownerID: recipe.ownerId) else {
            throw ExternalShareError.accountDeletionInProgress
        }
        guard let ownerId = recipe.ownerId else {
            throw ExternalShareError.invalidRecipe
        }
        return try await mutationCoordinator.perform(ownerID: ownerId) {
            let context = try await registeredOwnerContext(ownerId: ownerId)
            let metadata = ShareMetadata.RecipeShare(
                recipe: recipe,
                identityRecordName: context.identityRecordName,
                capability: context.capability,
                shouldCreate: shouldCreate
            )
            guard let publicationLease = await AccountDeletionGate.shared.acquirePublicationLease(ownerID: ownerId) else {
                throw ExternalShareError.accountDeletionInProgress
            }
            defer { Task { await AccountDeletionGate.shared.releasePublicationLease(publicationLease) } }
            return try await post(endpoint: "/shareRecipeV2", metadata: metadata)
        }
    }

    private func publishProfileShareMetadata(
        for user: User,
        recipeCount: Int?,
        shouldCreate: Bool
    ) async throws -> ShareResponse {
        guard await AccountDeletionGate.shared.permitsWrite(ownerID: user.id) else {
            throw ExternalShareError.accountDeletionInProgress
        }
        return try await mutationCoordinator.perform(ownerID: user.id) {
            let context = try await registeredOwnerContext(ownerId: user.id)
            let metadata = ShareMetadata.ProfileShare(
                userId: user.id.uuidString,
                identityRecordName: context.identityRecordName,
                username: user.username,
                displayName: user.displayName,
                profileEmoji: user.profileEmoji,
                profileColor: user.profileColor,
                recipeCount: recipeCount,
                capability: context.capability,
                shouldCreate: shouldCreate
            )
            guard let publicationLease = await AccountDeletionGate.shared.acquirePublicationLease(ownerID: user.id) else {
                throw ExternalShareError.accountDeletionInProgress
            }
            defer { Task { await AccountDeletionGate.shared.releasePublicationLease(publicationLease) } }
            return try await post(endpoint: "/shareProfileV2", metadata: metadata)
        }
    }

    func removeProfileShareMetadata(for user: User) async throws {
        try await mutationCoordinator.perform(ownerID: user.id) {
            let context = try await registeredOwnerContext(ownerId: user.id)
            let metadata = ShareMetadata.ProfileUnshare(
                userId: user.id.uuidString,
                identityRecordName: context.identityRecordName,
                username: user.username,
                capability: context.capability
            )
            guard let publicationLease = await AccountDeletionGate.shared.acquirePublicationLease(ownerID: user.id) else {
                throw ExternalShareError.accountDeletionInProgress
            }
            defer { Task { await AccountDeletionGate.shared.releasePublicationLease(publicationLease) } }
            let response: UnshareResponse = try await post(endpoint: "/unshareProfileV2", metadata: metadata)
            guard response.success else {
                throw ExternalShareError.invalidResponse
            }
            try await rotateManagementCapability(forOwnerID: user.id)
        }
    }

    func removeAllShareMetadata(for user: User) async throws {
        try await mutationCoordinator.perform(ownerID: user.id) {
            let context = try await registeredOwnerContext(ownerId: user.id, allowDuringAccountDeletion: true)
            let metadata = ShareMetadata.AccountUnshare(
                userId: user.id.uuidString,
                identityRecordName: context.identityRecordName,
                capability: context.capability
            )
            let response: UnshareResponse = try await post(endpoint: "/unshareAccountV2", metadata: metadata)
            guard response.success else {
                throw ExternalShareError.invalidResponse
            }
            publicationReceipts.removeAll(ownerID: user.id)
        }
    }

    func restoreAccountShareMetadata(for user: User) async throws {
        try await mutationCoordinator.perform(ownerID: user.id) {
            guard let userCloudService else {
                throw ExternalShareError.invalidProfile
            }
            guard let identityRecordName = user.cloudRecordName, !identityRecordName.isEmpty else {
                throw ExternalShareError.invalidProfile
            }
            // Rotate while the server-side revocation epoch is still active. The
            // restore endpoint requires the replacement hash, so the credential
            // used to begin deletion can never clear or bypass that epoch.
            let replacement = try await userCloudService.rotateWebShareCapability(
                for: user,
                allowDuringAccountDeletion: true
            )
            guard try await userCloudService.registerWebShareCapabilityHash(
                replacement,
                for: user,
                allowDuringAccountDeletion: true
            ) else { throw ExternalShareError.invalidProfile }
            let metadata = ShareMetadata.AccountUnshare(
                userId: user.id.uuidString,
                identityRecordName: identityRecordName,
                capability: replacement.capability
            )
            let response: UnshareResponse = try await post(endpoint: "/restoreAccountSharingV2", metadata: metadata)
            guard response.success else {
                throw ExternalShareError.invalidResponse
            }
        }
    }

    private struct OwnerContext {
        let identityRecordName: String
        let capability: String
    }

    private func registeredOwnerContext(
        ownerId: UUID,
        allowDuringAccountDeletion: Bool = false
    ) async throws -> OwnerContext {
        guard let user = CurrentUserSession.shared.currentUser,
              user.id == ownerId,
              let identityRecordName = user.cloudRecordName,
              !identityRecordName.isEmpty,
              let userCloudService else {
            throw ExternalShareError.invalidProfile
        }
        let credential = try await WebShareCapabilityRegistrationWorkflow.recover {
            try await userCloudService.resolveWebShareCapability(
                for: user,
                allowDuringAccountDeletion: allowDuringAccountDeletion
            )
        } rotate: {
            try await userCloudService.rotateWebShareCapability(
                for: user,
                allowDuringAccountDeletion: allowDuringAccountDeletion
            )
        } register: { credential in
            try await userCloudService.registerWebShareCapabilityHash(
                credential,
                for: user,
                allowDuringAccountDeletion: allowDuringAccountDeletion
            )
        }
        return OwnerContext(identityRecordName: identityRecordName, capability: credential.capability)
    }

    private func rotateManagementCapability(forOwnerID ownerID: UUID) async throws {
        guard let user = CurrentUserSession.shared.currentUser,
              user.id == ownerID,
              let userCloudService else {
            throw ExternalShareError.invalidProfile
        }
        let replacement = try await userCloudService.rotateWebShareCapability(for: user)
        guard try await userCloudService.registerWebShareCapabilityHash(
            replacement,
            for: user
        ) else { throw ExternalShareError.invalidProfile }
    }

    private func capabilityHash(_ capability: String) -> String {
        SHA256.hash(data: Data(capability.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Generate a shareable link for a collection (Local only)
    func generateCollectionLink(for collection: Collection, recipeCount: Int) -> ShareableLink {
        // Note: For collections we might not have a clean username URL structure yet?
        // Let's assume ID based for now if username isn't easily available,
        // or we need to pass username in.
        // The original code used the response from createShare to getting the URL, which implies the backend
        // generated the ID or URL. But here we want it deterministic.
        // If the web app supports /c/{collectionId}, we can use that.
        // Assuming /collection/{id} or similar.
        
        // Construct URL - using valid web app structure (collection IDs are UUIDs, safe for URLs)
        let urlString = "https://cauldronrecipes.com/collection/\(collection.id.uuidString)"

        let recipeText = recipeCount == 1 ? "1 recipe" : "\(recipeCount) recipes"
        let previewText = "Check out my \(collection.name) collection on Cauldron! \(recipeText)"

        // UUID strings are always URL-safe, but guard against unexpected failures
        guard let url = URL(string: urlString) else {
            logger.error("Failed to construct collection URL - this should never happen with UUID")
            return ShareableLink(
                url: URL(string: "https://cauldronrecipes.com")!,
                previewText: previewText,
                image: nil
            )
        }

        return ShareableLink(
            url: url,
            previewText: previewText,
            image: nil
        )
    }

    /// Update collection share metadata
    func updateCollectionShareMetadata(for collection: Collection, recipeIds: [UUID]) async -> Bool {
         guard collection.visibility == .publicRecipe else { return true }

         logger.info("🔄 Updating share metadata for collection: \(collection.name)")

        do {
            let response = try await publishCollectionShareMetadata(
                for: collection,
                recipeIds: recipeIds,
                shouldCreate: true
            )
            guard response.published == true else {
                logger.warning("Collection publication endpoint did not write a snapshot")
                return false
            }
             logger.info("✅ Collection metadata updated successfully")
            return true
        } catch {
            logger.error("❌ Failed to update collection metadata: \(error.localizedDescription)")
            return false
        }
    }

    /// Generate a shareable link for a collection
    func shareCollection(_ collection: Collection, recipeIds: [UUID]) async throws -> ShareableLink {
        logger.info("📤 Generating share link for collection: \(collection.name)")

        // Validate collection is public
        guard collection.visibility == .publicRecipe else {
            logger.warning("⚠️ Attempted to share private collection")
            throw ExternalShareError.notPublic
        }
        
        let response = try await publishCollectionShareMetadata(
            for: collection,
            recipeIds: recipeIds,
            shouldCreate: true
        )
        guard response.published == true else {
            throw ExternalShareError.invalidResponse
        }
        guard let publishedURL = URL(string: response.shareUrl) else {
            throw ExternalShareError.invalidResponse
        }
        return ShareableLink(
            url: publishedURL,
            previewText: "Check out my \(collection.name) collection on Cauldron! \(recipeIds.count) recipes",
            image: UIImage(named: "BrandMarks/CauldronIcon")
        )
    }

    private func publishCollectionShareMetadata(
        for collection: Collection,
        recipeIds: [UUID],
        shouldCreate: Bool
    ) async throws -> ShareResponse {
        guard await AccountDeletionGate.shared.permitsWrite(ownerID: collection.userId) else {
            throw ExternalShareError.accountDeletionInProgress
        }
        return try await mutationCoordinator.perform(ownerID: collection.userId) {
            let context = try await registeredOwnerContext(ownerId: collection.userId)
            let metadata = ShareMetadata.CollectionShare(
                collectionId: collection.id.uuidString,
                ownerId: collection.userId.uuidString,
                identityRecordName: context.identityRecordName,
                title: collection.name,
                recipeCount: recipeIds.count,
                recipeIds: recipeIds.map { $0.uuidString },
                capability: context.capability,
                shouldCreate: shouldCreate
            )
            guard let publicationLease = await AccountDeletionGate.shared.acquirePublicationLease(ownerID: collection.userId) else {
                throw ExternalShareError.accountDeletionInProgress
            }
            defer { Task { await AccountDeletionGate.shared.releasePublicationLease(publicationLease) } }
            return try await createShare(endpoint: "/shareCollectionV2", metadata: metadata)
        }
    }

    func removeCollectionShareMetadata(collectionId: UUID, ownerId: UUID) async throws {
        try await mutationCoordinator.perform(ownerID: ownerId) {
            let context = try await registeredOwnerContext(ownerId: ownerId)
            let metadata = ShareMetadata.CollectionUnshare(
                collectionId: collectionId.uuidString,
                ownerId: ownerId.uuidString,
                identityRecordName: context.identityRecordName,
                capability: context.capability
            )
            guard let publicationLease = await AccountDeletionGate.shared.acquirePublicationLease(ownerID: ownerId) else {
                throw ExternalShareError.accountDeletionInProgress
            }
            defer { Task { await AccountDeletionGate.shared.releasePublicationLease(publicationLease) } }
            let response: UnshareResponse = try await post(endpoint: "/unshareCollectionV2", metadata: metadata)
            guard response.success else {
                throw ExternalShareError.invalidResponse
            }
            try await rotateManagementCapability(forOwnerID: ownerId)
        }
    }

    // MARK: - Import from Share Link

    /// Import content from a share URL
    func importFromShareURL(_ url: URL) async throws -> ImportedContent {
        logger.info("📥 Importing from share URL: \(url.absoluteString)")

        guard let route = ExternalShareURLClassifier.route(from: url) else {
            logger.error("❌ Invalid or unsupported URL format: \(url.absoluteString)")
            throw ExternalShareError.invalidResponse
        }
        switch route {
        case .recipe(let shareID):
            let shareData = try await fetchShareData(type: "recipe", shareId: shareID)
            return try await convertToRecipe(shareData)
        case .profile(let shareID):
            let shareData = try await fetchShareData(type: "profile", shareId: shareID)
            return try convertToProfile(shareData)
        case .collection(let shareID):
            let shareData = try await fetchShareData(type: "collection", shareId: shareID)
            return try await convertToCollection(shareData)
        }
    }

    // MARK: - Private Helpers

    private func createShare<T: Encodable>(endpoint: String, metadata: T) async throws -> ShareResponse {
        try await post(endpoint: endpoint, metadata: metadata)
    }

    private func post<T: Encodable, Response: Decodable>(endpoint: String, metadata: T) async throws -> Response {
        guard let url = URL(string: baseURL + endpoint) else {
            throw ExternalShareError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(metadata)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ExternalShareError.invalidResponse
            }

            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            logger.error("❌ Share creation failed: \(error.localizedDescription)")
            throw ExternalShareError.networkError(error)
        }
    }

    private func fetchShareData(type: String, shareId: String) async throws -> ShareData {
        guard let url = URL(string: "\(baseURL)/api/data/\(type)/\(shareId)") else {
            throw ExternalShareError.invalidResponse
        }

        logger.info("🌐 Fetching data from \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.error("❌ Failed to fetch share data: \(error.localizedDescription)")
            throw ExternalShareError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("❌ Response is not HTTPURLResponse")
            throw ExternalShareError.invalidResponse
        }

        logger.info("🌐 Status Code: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No body"
            logger.error("❌ Invalid status code. Body: \(body)")
            if httpResponse.statusCode == 408 ||
                httpResponse.statusCode == 425 ||
                httpResponse.statusCode == 429 ||
                (500...599).contains(httpResponse.statusCode) {
                throw ExternalShareError.temporarilyUnavailable
            }
            throw ExternalShareError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(ShareData.self, from: data)
        } catch {
            logger.error("❌ Invalid share response: \(error.localizedDescription)")
            throw ExternalShareError.invalidResponse
        }
    }

    private func convertToRecipe(_ shareData: ShareData) async throws -> ImportedContent {
        guard let recipeId = shareData.data.recipeId,
              let title = shareData.data.title else {
            throw ExternalShareError.invalidRecipe
        }

        // Create a minimal Recipe object from share data
        // Note: The full recipe data should be fetched from CloudKit using the recipeId
        let recipe = Recipe(
            id: UUID(uuidString: recipeId) ?? UUID(),
            title: title,
            ingredients: [], // Will be populated when fetching full recipe
            steps: [],
            yields: "",
            totalMinutes: shareData.data.totalMinutes,
            tags: shareData.data.tags?.compactMap { Tag(name: $0) } ?? [],
            nutrition: nil,
            sourceURL: nil,
            sourceTitle: nil,
            notes: nil,
            imageURL: shareData.data.imageURL.flatMap { URL(string: $0) },
            isFavorite: false,
            visibility: .publicRecipe,
            ownerId: shareData.data.ownerId.flatMap { UUID(uuidString: $0) },
            cloudRecordName: nil,
            cloudImageRecordName: nil,
            imageModifiedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        return .recipe(recipe, originalCreator: nil)
    }

    private func convertToProfile(_ shareData: ShareData) throws -> ImportedContent {
        guard let userId = shareData.data.userId,
              let username = shareData.data.username else {
            throw ExternalShareError.invalidProfile
        }

        let user = User(
            id: UUID(uuidString: userId) ?? UUID(),
            username: username,
            displayName: shareData.data.displayName ?? username,
            email: nil,
            cloudRecordName: nil,
            createdAt: Date(),
            profileEmoji: nil,
            profileColor: nil,
            profileImageURL: shareData.data.profileImageURL.flatMap { URL(string: $0) },
            cloudProfileImageRecordName: nil,
            profileImageModifiedAt: nil
        )

        return .profile(user)
    }

    private func convertToCollection(_ shareData: ShareData) async throws -> ImportedContent {
        guard let collectionId = shareData.data.collectionId,
              let title = shareData.data.title,
              let ownerId = shareData.data.ownerId else {
            throw ExternalShareError.invalidCollection
        }

        let collection = Collection(
            id: UUID(uuidString: collectionId) ?? UUID(),
            name: title,
            description: nil,
            userId: UUID(uuidString: ownerId) ?? UUID(),
            recipeIds: shareData.data.recipeIds?.compactMap(UUID.init(uuidString:)) ?? [],
            visibility: .publicRecipe,
            emoji: nil,
            color: nil,
            coverImageType: .customImage, // Assume custom image if URL present, or fallback
            coverImageURL: shareData.data.coverImageURL.flatMap { URL(string: $0) },
            cloudCoverImageRecordName: nil,
            coverImageModifiedAt: nil,
            cloudRecordName: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        return .collection(collection, owner: nil)
    }
}
