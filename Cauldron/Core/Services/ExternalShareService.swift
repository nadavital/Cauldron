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

/// Service for creating and importing external share links
@MainActor
final class ExternalShareService: Sendable {
    private let logger = Logger(subsystem: "com.cauldron", category: "ExternalShareService")

    // Backend API configuration
    // Firebase Functions URL
    private let baseURL = "https://us-central1-cauldron-f900a.cloudfunctions.net"

    private let session: URLSession
    private let userCloudService: UserCloudService?

    init(imageManager _: RecipeImageManager, userCloudService: UserCloudService? = nil) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        self.userCloudService = userCloudService
    }

    // MARK: - Share Link Generation

    /// Generate a shareable link for a recipe (Local only - deterministic)
    func generateShareLink(for recipe: Recipe) -> ShareableLink {
        // Fetch owner username locally or fallback
        var username = "user"
        
        // This is a best-effort local check. The backend sync ensures the link works.
        // If we don't have the username locally, the link will still work but might redirect
        // or rely on the ID lookup.
        if let ownerId = recipe.ownerId {
             // We can't easily look up other users synchronously here without a cache.
             // For the current user, we can check session.
             if let currentUser = CurrentUserSession.shared.currentUser, currentUser.id == ownerId {
                 username = currentUser.username
             }
             // NOTE: If it's another user's recipe, we might not have their username handy
             // in a synchronous context without fetching.
             // Ideally, Recipe should store `ownerUsername` or we rely on the repository to provide it.
             // For now, we'll assume the link format uses the ID if username is generic,
             // or sticking to the pattern: /u/{username}/{recipeId}
             // If we don't know the username, "user" is a safe fallback that the web app should handle (redirecting by ID).
        }
        
        // Construct permanent URL
        // Format: https://cauldron-f900a.web.app/u/{username}/{recipeId}
        // URL-encode username to handle special characters safely
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let permanentURLString = "https://cauldron-f900a.web.app/u/\(encodedUsername)/\(recipe.id.uuidString)"

        // Create preview text
        let previewText = "Check out my recipe for \(recipe.title) on Cauldron!"

        // Safely construct URL, falling back to ID-based URL if username encoding fails
        let url: URL
        if let constructedURL = URL(string: permanentURLString) {
            url = constructedURL
        } else {
            // Fallback to ID-based URL if username causes invalid URL
            let fallbackURLString = "https://cauldron-f900a.web.app/recipe/\(recipe.id.uuidString)"
            url = URL(string: fallbackURLString)!
        }

        return ShareableLink(
            url: url,
            previewText: previewText,
            image: nil // Caller can attach image if they have it, or we can load it if we make this async
        )
    }

    /// Update share metadata on the backend (Fire-and-forget style)
    /// This should be called when a recipe is saved/updated and is PUBLIC
    @discardableResult
    func updateShareMetadata(for recipe: Recipe) async -> Bool {
        guard recipe.visibility == .publicRecipe else { return true }

        logger.info("🔄 Updating share metadata for recipe: \(recipe.title)")

        do {
            _ = try await publishRecipeShareMetadata(for: recipe, shouldCreate: false)
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
        try await rotateManagementCapability(forOwnerID: ownerId)
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

        let response = try await publishRecipeShareMetadata(for: recipe, shouldCreate: true)

        guard let publishedURL = URL(string: response.shareUrl) else {
            throw ExternalShareError.invalidResponse
        }
        return ShareableLink(
            url: publishedURL,
            previewText: "Check out my recipe for \(recipe.title) on Cauldron!",
            image: UIImage(named: "BrandMarks/CauldronIcon")
        )
    }

    /// Generate a shareable link for a profile (Local only)
    func generateProfileLink(for user: User, recipeCount: Int) -> ShareableLink {
        // URL-encode username to handle special characters safely
        let encodedUsername = user.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user.username
        let permanentURLString = "https://cauldron-f900a.web.app/u/\(encodedUsername)"
        let recipeText = recipeCount == 1 ? "1 recipe" : "\(recipeCount) recipes"
        let previewText = "Check out my Cauldron profile! \(recipeText) and counting 🍲"

        // Safely construct URL, falling back to ID-based URL if username encoding fails
        let url: URL
        if let constructedURL = URL(string: permanentURLString) {
            url = constructedURL
        } else {
            let fallbackURLString = "https://cauldron-f900a.web.app/profile/\(user.id.uuidString)"
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
            _ = try await publishProfileShareMetadata(
                for: user,
                recipeCount: recipeCount,
                shouldCreate: false
            )
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

    private func publishProfileShareMetadata(
        for user: User,
        recipeCount: Int?,
        shouldCreate: Bool
    ) async throws -> ShareResponse {
        guard await AccountDeletionGate.shared.permitsWrite(ownerID: user.id) else {
            throw ExternalShareError.accountDeletionInProgress
        }
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

    func removeProfileShareMetadata(for user: User) async throws {
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

    func removeAllShareMetadata(for user: User) async throws {
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
    }

    func restoreAccountShareMetadata(for user: User) async throws {
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
        var credential = try await userCloudService.resolveWebShareCapability(
            for: user,
            allowDuringAccountDeletion: allowDuringAccountDeletion
        )
        if !(try await userCloudService.registerWebShareCapabilityHash(
            credential,
            for: user,
            allowDuringAccountDeletion: allowDuringAccountDeletion
        )) {
            credential = try await userCloudService.resolveWebShareCapability(
                for: user,
                allowDuringAccountDeletion: allowDuringAccountDeletion
            )
            guard try await userCloudService.registerWebShareCapabilityHash(
                credential,
                for: user,
                allowDuringAccountDeletion: allowDuringAccountDeletion
            ) else { throw ExternalShareError.invalidProfile }
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
        let urlString = "https://cauldron-f900a.web.app/collection/\(collection.id.uuidString)"

        let recipeText = recipeCount == 1 ? "1 recipe" : "\(recipeCount) recipes"
        let previewText = "Check out my \(collection.name) collection on Cauldron! \(recipeText)"

        // UUID strings are always URL-safe, but guard against unexpected failures
        guard let url = URL(string: urlString) else {
            logger.error("Failed to construct collection URL - this should never happen with UUID")
            return ShareableLink(
                url: URL(string: "https://cauldron-f900a.web.app")!,
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
            _ = try await publishCollectionShareMetadata(
                for: collection,
                recipeIds: recipeIds,
                shouldCreate: false
            )
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

    func removeCollectionShareMetadata(collectionId: UUID, ownerId: UUID) async throws {
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

    // MARK: - Import from Share Link

    /// Import content from a share URL
    func importFromShareURL(_ url: URL) async throws -> ImportedContent {
        logger.info("📥 Importing from share URL: \(url.absoluteString)")

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        // 1. Handle /u/{username}/{recipeId} (Recipe) and /u/{username} (Profile)
        if let uIndex = pathComponents.firstIndex(of: "u") {
            if uIndex + 2 < pathComponents.count {
                // Format: .../u/username/recipeId
                let shareId = pathComponents[uIndex + 2]
                let shareData = try await fetchShareData(type: "recipe", shareId: shareId)
                return try await convertToRecipe(shareData)
            } else if uIndex + 1 < pathComponents.count {
                // Format: .../u/username
                // Note: We use the username component as the ID for lookup.
                // The backend must support resolving profiles by username or ID.
                let shareId = pathComponents[uIndex + 1]
                let shareData = try await fetchShareData(type: "profile", shareId: shareId)
                return try convertToProfile(shareData)
            }
        }
        
        // 2. Handle /collection/{collectionId}
        if let cIndex = pathComponents.firstIndex(of: "collection"), cIndex + 1 < pathComponents.count {
            let shareId = pathComponents[cIndex + 1]
            let shareData = try await fetchShareData(type: "collection", shareId: shareId)
            return try await convertToCollection(shareData)
        }
        
        // 3. Handle Legacy /recipe/{recipeId} or /profile/{userId}
        if let rIndex = pathComponents.firstIndex(of: "recipe"), rIndex + 1 < pathComponents.count {
            let shareId = pathComponents[rIndex + 1]
            let shareData = try await fetchShareData(type: "recipe", shareId: shareId)
            return try await convertToRecipe(shareData)
        }
        
        if let pIndex = pathComponents.firstIndex(of: "profile"), pIndex + 1 < pathComponents.count {
            let shareId = pathComponents[pIndex + 1]
             let shareData = try await fetchShareData(type: "profile", shareId: shareId)
            return try convertToProfile(shareData)
        }

        logger.error("❌ Invalid or unsupported URL format: \(url.absoluteString)")
        throw ExternalShareError.invalidResponse
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
