//
//  ExternalShareService.swift
//  Cauldron
//
//  Service for generating external shareable links for recipes, profiles, and collections
//

import Foundation
import UIKit
import os

/// Errors that can occur during external sharing
enum ExternalShareError: LocalizedError {
    case invalidRecipe
    case invalidProfile
    case invalidCollection
    case networkError(Error)
    case invalidResponse
    case notPublic

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
        }
    }
}

/// Service for creating and importing external share links
actor ExternalShareService {
    private let logger = Logger(subsystem: "com.cauldron", category: "ExternalShareService")

    // Backend API configuration
    // TODO: Update this URL after deploying to Vercel
    // After running 'vercel --prod', replace with your actual Vercel URL
    private let baseURL = "https://your-project.vercel.app/api"
    // Example: "https://cauldron-api.vercel.app/api"

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Share Link Generation

    /// Generate a shareable link for a recipe
    func shareRecipe(_ recipe: Recipe) async throws -> ShareableLink {
        logger.info("📤 Generating share link for recipe: \(recipe.title)")

        // Validate recipe is public
        guard recipe.visibility == .publicRecipe else {
            logger.warning("⚠️ Attempted to share private recipe")
            throw ExternalShareError.notPublic
        }

        // Prepare metadata
        let metadata = ShareMetadata.RecipeShare(
            recipeId: recipe.id.uuidString,
            ownerId: recipe.ownerId?.uuidString ?? "",
            title: recipe.title,
            imageURL: recipe.imageURL?.absoluteString,
            ingredientCount: recipe.ingredients.count,
            totalMinutes: recipe.totalMinutes,
            tags: recipe.tags.map { $0.rawValue }
        )

        // Send to backend
        let response = try await createShare(endpoint: "/share/recipe", metadata: metadata)

        // Create preview text
        let ingredientText = "\(recipe.ingredients.count) ingredients"
        let timeText = recipe.totalMinutes.map { "\($0) min" } ?? "Quick"
        let previewText = "Check out my recipe for \(recipe.title) on Cauldron! \(ingredientText) • \(timeText)"

        // Load image if available
        var image: UIImage?
        if let imageURL = recipe.imageURL {
            image = try? await loadImage(from: imageURL)
        }

        logger.info("✅ Share link generated: \(response.shareUrl)")

        return ShareableLink(
            url: URL(string: response.shareUrl)!,
            previewText: previewText,
            image: image
        )
    }

    /// Generate a shareable link for a user profile
    func shareProfile(_ user: User, recipeCount: Int) async throws -> ShareableLink {
        logger.info("📤 Generating share link for profile: \(user.username)")

        // Prepare metadata
        let metadata = ShareMetadata.ProfileShare(
            userId: user.id.uuidString,
            username: user.username,
            displayName: user.displayName,
            profileImageURL: user.profileImageURL?.absoluteString,
            recipeCount: recipeCount
        )

        // Send to backend
        let response = try await createShare(endpoint: "/share/profile", metadata: metadata)

        // Create preview text
        let recipeText = recipeCount == 1 ? "1 recipe" : "\(recipeCount) recipes"
        let previewText = "Check out my Cauldron profile! \(recipeText) and counting 🍲"

        // Load profile image if available
        var image: UIImage?
        if let imageURL = user.profileImageURL {
            image = try? await loadImage(from: imageURL)
        }

        logger.info("✅ Share link generated: \(response.shareUrl)")

        return ShareableLink(
            url: URL(string: response.shareUrl)!,
            previewText: previewText,
            image: image
        )
    }

    /// Generate a shareable link for a collection
    func shareCollection(_ collection: Collection, recipeIds: [UUID]) async throws -> ShareableLink {
        logger.info("📤 Generating share link for collection: \(collection.title)")

        // Validate collection is public
        guard collection.visibility == .publicCollection else {
            logger.warning("⚠️ Attempted to share private collection")
            throw ExternalShareError.notPublic
        }

        // Prepare metadata
        let metadata = ShareMetadata.CollectionShare(
            collectionId: collection.id.uuidString,
            ownerId: collection.ownerId.uuidString,
            title: collection.title,
            coverImageURL: collection.coverImageURL?.absoluteString,
            recipeCount: recipeIds.count,
            recipeIds: recipeIds.map { $0.uuidString }
        )

        // Send to backend
        let response = try await createShare(endpoint: "/share/collection", metadata: metadata)

        // Create preview text
        let recipeText = recipeIds.count == 1 ? "1 recipe" : "\(recipeIds.count) recipes"
        let previewText = "Check out my \(collection.title) collection on Cauldron! \(recipeText)"

        // Load cover image if available
        var image: UIImage?
        if let imageURL = collection.coverImageURL {
            image = try? await loadImage(from: imageURL)
        }

        logger.info("✅ Share link generated: \(response.shareUrl)")

        return ShareableLink(
            url: URL(string: response.shareUrl)!,
            previewText: previewText,
            image: image
        )
    }

    // MARK: - Import from Share Link

    /// Import content from a share URL
    func importFromShareURL(_ url: URL) async throws -> ImportedContent {
        logger.info("📥 Importing from share URL: \(url.absoluteString)")

        // Parse URL to determine type and shareId
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let pathComponents = components.path.split(separator: "/") as? [String],
              pathComponents.count >= 2 else {
            throw ExternalShareError.invalidResponse
        }

        let type = pathComponents[pathComponents.count - 2]
        let shareId = pathComponents[pathComponents.count - 1]

        logger.info("📋 Importing \(type) with ID: \(shareId)")

        // Fetch data from backend
        let shareData = try await fetchShareData(type: type, shareId: shareId)

        // Convert to ImportedContent based on type
        switch type {
        case "recipe":
            return try await convertToRecipe(shareData)
        case "profile":
            return try convertToProfile(shareData)
        case "collection":
            return try await convertToCollection(shareData)
        default:
            throw ExternalShareError.invalidResponse
        }
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
        guard let url = URL(string: "\(baseURL)/data/\(type)/\(shareId)") else {
            throw ExternalShareError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
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
            tags: shareData.data.tags?.compactMap { Tag(rawValue: $0) } ?? [],
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

        // TODO: Fetch original creator info if needed
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
            title: title,
            ownerId: UUID(uuidString: ownerId) ?? UUID(),
            visibility: .publicCollection,
            coverImageURL: shareData.data.coverImageURL.flatMap { URL(string: $0) },
            cloudRecordName: nil,
            cloudImageRecordName: nil,
            imageModifiedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        // TODO: Fetch owner info if needed
        return .collection(collection, owner: nil)
    }
}
