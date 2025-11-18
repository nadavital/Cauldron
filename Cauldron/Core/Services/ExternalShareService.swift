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
@MainActor
final class ExternalShareService: Sendable {
    private let logger = Logger(subsystem: "com.cauldron", category: "ExternalShareService")

    // Backend API configuration
    // Firebase Functions URL
    private let baseURL = "https://us-central1-cauldron-f900a.cloudfunctions.net"

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
            tags: recipe.tags.map { $0.name }
        )

        // Send to backend
        let response = try await createShare(endpoint: "/shareRecipe", metadata: metadata)

        // Create preview text
        let previewText = "Check out my recipe for \(recipe.title) on Cauldron!"

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
        let response = try await createShare(endpoint: "/shareProfile", metadata: metadata)

        // Create preview text
        let recipeText = recipeCount == 1 ? "1 recipe" : "\(recipeCount) recipes"
        let previewText = "Check out my Cauldron profile! \(recipeText) and counting 🍲"

        // Load profile image if available, otherwise use App Icon
        var image: UIImage?
        if let imageURL = user.profileImageURL {
            image = try? await loadImage(from: imageURL)
        }
        
        // Fallback to Cauldron Icon if no profile image
        if image == nil {
            image = UIImage(named: "CauldronIcon")
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
        logger.info("📤 Generating share link for collection: \(collection.name)")

        // Validate collection is public
        // Note: Collection uses RecipeVisibility enum
        guard collection.visibility == .publicRecipe else {
            logger.warning("⚠️ Attempted to share private collection")
            throw ExternalShareError.notPublic
        }

        // Prepare metadata
        let metadata = ShareMetadata.CollectionShare(
            collectionId: collection.id.uuidString,
            ownerId: collection.userId.uuidString,
            title: collection.name,
            coverImageURL: collection.coverImageURL?.absoluteString,
            recipeCount: recipeIds.count,
            recipeIds: recipeIds.map { $0.uuidString }
        )

        // Send to backend
        let response = try await createShare(endpoint: "/shareCollection", metadata: metadata)

        // Create preview text
        let recipeText = recipeIds.count == 1 ? "1 recipe" : "\(recipeIds.count) recipes"
        let previewText = "Check out my \(collection.name) collection on Cauldron! \(recipeText)"

        // Load cover image if available
        var image: UIImage?
        if let imageURL = collection.coverImageURL {
            image = try? await loadImage(from: imageURL)
        }
        
        // Fallback to Cauldron Icon if no cover image
        if image == nil {
            image = UIImage(named: "CauldronIcon")
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
        // Supports:
        // 1. Web: https://cauldron-f900a.web.app/recipe/123
        // 2. Deep Link: cauldron://import/recipe/123
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        // Expected format: ["recipe", "123"] or ["import", "recipe", "123"]
        var type: String?
        var shareId: String?
        
        if pathComponents.count >= 2 {
            // Check for /recipe/123 format
            if ["recipe", "profile", "collection"].contains(pathComponents[pathComponents.count - 2]) {
                type = pathComponents[pathComponents.count - 2]
                shareId = pathComponents[pathComponents.count - 1]
            }
        }
        
        guard let finalType = type, let finalShareId = shareId else {
            logger.error("❌ Invalid URL format: \(url.absoluteString)")
            throw ExternalShareError.invalidResponse
        }

        logger.info("📋 Importing \(finalType) with ID: \(finalShareId)")

        // Fetch data from backend
        let shareData = try await fetchShareData(type: finalType, shareId: finalShareId)

        // Convert to ImportedContent based on type
        switch finalType {
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
        guard let url = URL(string: "\(baseURL)/api/data/\(type)/\(shareId)") else {
            throw ExternalShareError.invalidResponse
        }

        print("🌐 ExternalShareService: Fetching data from \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ ExternalShareService: Response is not HTTPURLResponse")
                throw ExternalShareError.invalidResponse
            }

            print("🌐 ExternalShareService: Status Code: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "No body"
                print("❌ ExternalShareService: Invalid status code. Body: \(body)")
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

        // TODO: Fetch owner info if needed
        return .collection(collection, owner: nil)
    }
}
