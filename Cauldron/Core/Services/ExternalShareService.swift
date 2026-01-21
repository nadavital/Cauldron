//
//  ExternalShareService.swift
//  Cauldron
//
//  Service for generating external shareable links for recipes, profiles, and collections
//

import Foundation
import UIKit
import CloudKit
import os

/// Errors that can occur during external sharing
enum ExternalShareError: LocalizedError {
    case invalidRecipe
    case invalidProfile
    case invalidCollection
    case networkError(Error)
    case invalidResponse
    case notPublic
    case imageUploadFailed

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
        case .notPublic:
            return "Only public recipes and collections can be shared externally"
        case .imageUploadFailed:
            return "Failed to upload image to cloud"
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
    private let imageManager: ImageManager
    private let cloudKitService: CloudKitService

    init(imageManager: ImageManager, cloudKitService: CloudKitService) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        self.imageManager = imageManager
        self.cloudKitService = cloudKitService
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
        let permanentURLString = "https://cauldron-f900a.web.app/u/\(username)/\(recipe.id.uuidString)"
        
        // Create preview text
        let previewText = "Check out my recipe for \(recipe.title) on Cauldron!"

        // Load image for iOS share sheet preview
        // Note: usage of local file path or cache would be ideal here if available synchronously,
        // but Since we are in an async function (or can be), we can keep it async or make this sync.
        // For now, keeping the return type sync for the URL, but the image loading might need to be async or passed in.
        // However, to keep this fast, we return the link object. The caller can load the image if needed for the UI,
        // or we can keep this async just for the image loading if we want 'perfect' previews.
        // Given the requirement for "instant", we should avoid network calls here.
        
        // Note: We need a way to get the local image without network.
        // ImageManager provides async access.
        // For the purpose of Generating the link string, we don't strictly need the UIImage *right now*
        // but share sheets *do* look better with it.
        // Let's keep this method async ONLY for local image loading, but NO network calls.
        
        return ShareableLink(
            url: URL(string: permanentURLString)!,
            previewText: previewText,
            image: nil // Caller can attach image if they have it, or we can load it if we make this async
        )
    }

    /// Update share metadata on the backend (Fire-and-forget style)
    /// This should be called when a recipe is saved/updated and is PUBLIC
    func updateShareMetadata(for recipe: Recipe) async {
        guard recipe.visibility == .publicRecipe else { return }

        logger.info("🔄 Updating share metadata for recipe: \(recipe.title)")

        // Prepare metadata
        let metadata = ShareMetadata.RecipeShare(
            recipeId: recipe.id.uuidString,
            ownerId: recipe.ownerId?.uuidString ?? "",
            title: recipe.title,
            imageURL: nil, // We don't send the image URL to backend (images are in CloudKit)
            ingredientCount: recipe.ingredients.count,
            totalMinutes: recipe.totalMinutes,
            tags: recipe.tags.map { $0.name }
        )

        do {
            _ = try await createShare(endpoint: "/shareRecipe", metadata: metadata)
            logger.info("✅ Share metadata updated successfully")
        } catch {
            logger.error("❌ Failed to update share metadata: \(error.localizedDescription)")
            // We don't throw here to avoid disrupting the save flow
        }
    }

    /// Legacy support - calls generate and optionally updates metadata
    func shareRecipe(_ recipe: Recipe) async throws -> ShareableLink {
        // Trigger metadata update in background
        Task {
            await updateShareMetadata(for: recipe)
        }
        
        // Generate link
        var link = generateShareLink(for: recipe)
        
        // Try to load image for share sheet (best effort)
        if let imageURL = recipe.imageURL {
             link.image = try? await loadImage(from: imageURL)
        }
        
        return link
    }

    /// Generate a shareable link for a profile (Local only)
    func generateProfileLink(for user: User, recipeCount: Int) -> ShareableLink {
        let permanentURLString = "https://cauldron-f900a.web.app/u/\(user.username)"
        let recipeText = recipeCount == 1 ? "1 recipe" : "\(recipeCount) recipes"
        let previewText = "Check out my Cauldron profile! \(recipeText) and counting 🍲"
        
        return ShareableLink(
            url: URL(string: permanentURLString)!,
            previewText: previewText,
            image: nil
        )
    }

    /// Update profile share metadata on the backend
    func updateProfileShareMetadata(for user: User, recipeCount: Int) async {
        logger.info("🔄 Updating share metadata for profile: \(user.username)")

        let metadata = ShareMetadata.ProfileShare(
            userId: user.id.uuidString,
            username: user.username,
            displayName: user.displayName,
            profileImageURL: user.profileImageURL?.absoluteString,
            recipeCount: recipeCount
        )

        do {
            _ = try await createShare(endpoint: "/shareProfile", metadata: metadata)
            logger.info("✅ Profile metadata updated successfully")
        } catch {
             logger.error("❌ Failed to update profile metadata: \(error.localizedDescription)")
        }
    }

    /// Generate a shareable link for a user profile
    func shareProfile(_ user: User, recipeCount: Int) async throws -> ShareableLink {
        // Trigger metadata update
        Task {
            await updateProfileShareMetadata(for: user, recipeCount: recipeCount)
        }
        
        var link = generateProfileLink(for: user, recipeCount: recipeCount)
        
        // Load profile image
        if let imageURL = user.profileImageURL {
            link.image = try? await loadImage(from: imageURL)
        }
        if link.image == nil {
            link.image = UIImage(named: "BrandMarks/CauldronIcon")
        }
        
        return link
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
        
        // Construct URL - using valid web app structure
        // If the web app expects /collection/ID, use that.
        let urlString = "https://cauldron-f900a.web.app/collection/\(collection.id.uuidString)"
        
        let recipeText = recipeCount == 1 ? "1 recipe" : "\(recipeCount) recipes"
        let previewText = "Check out my \(collection.name) collection on Cauldron! \(recipeText)"
        
        return ShareableLink(
            url: URL(string: urlString)!,
            previewText: previewText,
            image: nil
        )
    }

    /// Update collection share metadata
    func updateCollectionShareMetadata(for collection: Collection, recipeIds: [UUID]) async {
         guard collection.visibility == .publicRecipe else { return }

         logger.info("🔄 Updating share metadata for collection: \(collection.name)")

        let metadata = ShareMetadata.CollectionShare(
            collectionId: collection.id.uuidString,
            ownerId: collection.userId.uuidString,
            title: collection.name,
            coverImageURL: collection.coverImageURL?.absoluteString,
            recipeCount: recipeIds.count,
            recipeIds: recipeIds.map { $0.uuidString }
        )

        do {
            _ = try await createShare(endpoint: "/shareCollection", metadata: metadata)
             logger.info("✅ Collection metadata updated successfully")
        } catch {
            logger.error("❌ Failed to update collection metadata: \(error.localizedDescription)")
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
        
        // Trigger metadata update
        Task {
            await updateCollectionShareMetadata(for: collection, recipeIds: recipeIds)
        }

        var link = generateCollectionLink(for: collection, recipeCount: recipeIds.count)

        // Load cover image
        if let imageURL = collection.coverImageURL {
            link.image = try? await loadImage(from: imageURL)
        }
        if link.image == nil {
            link.image = UIImage(named: "BrandMarks/CauldronIcon")
        }

        return link
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

            return try JSONDecoder().decode(ShareResponse.self, from: data)
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

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("❌ Response is not HTTPURLResponse")
                throw ExternalShareError.invalidResponse
            }

            logger.info("🌐 Status Code: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "No body"
                logger.error("❌ Invalid status code. Body: \(body)")
                throw ExternalShareError.invalidResponse
            }

            return try JSONDecoder().decode(ShareData.self, from: data)
        } catch {
            logger.error("❌ Failed to fetch share data: \(error.localizedDescription)")
            throw ExternalShareError.networkError(error)
        }
    }

    private func loadImage(from url: URL) async throws -> UIImage? {
        let (data, _) = try await session.data(from: url)
        return UIImage(data: data)
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
            recipeIds: [], // We don't have the full list from share data, will fetch
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
