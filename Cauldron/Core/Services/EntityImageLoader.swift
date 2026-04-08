//
//  EntityImageLoader.swift
//  Cauldron
//
//  Shared orchestration layer for entity image loading and preloading.
//

import Foundation
import UIKit
import os

@MainActor
final class EntityImageLoader {
    static let shared = EntityImageLoader()

    struct ProfileImageResult {
        let image: UIImage?
        let downloadedURL: URL?
    }

    private let logger = Logger(subsystem: "com.cauldron", category: "EntityImageLoader")

    private init() {}

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {}

    func loadProfileImage(for user: User, dependencies: DependencyContainer?) async -> ProfileImageResult {
        let cacheKey = ImageCache.profileImageKey(userId: user.id)

        if let cachedImage = await ImageCache.shared.load(cacheKey) {
            return ProfileImageResult(image: cachedImage, downloadedURL: nil)
        }

        if let localImage = await loadImage(from: user.profileImageURL) {
            ImageCache.shared.set(cacheKey, image: localImage)
            return ProfileImageResult(image: localImage, downloadedURL: nil)
        }

        guard let dependencies = dependencies,
              user.cloudProfileImageRecordName != nil,
              user.profileImageURL == nil else {
            return ProfileImageResult(image: nil, downloadedURL: nil)
        }

        do {
            if let downloadedURL = try await dependencies.profileImageManager.downloadImageFromCloud(userId: user.id),
               let downloadedImage = await loadImage(from: downloadedURL) {
                ImageCache.shared.set(cacheKey, image: downloadedImage)
                return ProfileImageResult(image: downloadedImage, downloadedURL: downloadedURL)
            }
        } catch {
            logger.warning("Failed to download profile image from CloudKit: \(error.localizedDescription)")
        }

        return ProfileImageResult(image: nil, downloadedURL: nil)
    }

    func loadCollectionCoverImage(for collection: Collection, dependencies: DependencyContainer?) async -> UIImage? {
        let cacheKey = ImageCache.collectionImageKey(collectionId: collection.id)

        if let cachedImage = await ImageCache.shared.load(cacheKey) {
            return cachedImage
        }

        if let localImage = await loadImage(from: collection.coverImageURL) {
            ImageCache.shared.set(cacheKey, image: localImage)
            return localImage
        }

        guard let dependencies = dependencies,
              collection.cloudCoverImageRecordName != nil,
              collection.coverImageURL == nil else {
            return nil
        }

        do {
            if let downloadedURL = try await dependencies.collectionImageManager.downloadImageFromCloud(collectionId: collection.id),
               let downloadedImage = await loadImage(from: downloadedURL) {
                ImageCache.shared.set(cacheKey, image: downloadedImage)
                return downloadedImage
            }
        } catch {
            logger.warning("Failed to download collection cover image from CloudKit: \(error.localizedDescription)")
        }

        return nil
    }

    func ensureProfileImagesInCache(users: [User]) async {
        for user in users {
            let cacheKey = ImageCache.profileImageKey(userId: user.id)
            if ImageCache.shared.get(cacheKey) != nil {
                continue
            }

            if let image = await loadImage(from: user.profileImageURL) {
                ImageCache.shared.set(cacheKey, image: image)
            }
        }
    }

    func preloadProfileImages(users: [User], dependencies: DependencyContainer, forceRefresh: Bool = false) async {
        await withTaskGroup(of: (UUID, UIImage?).self) { group in
            for user in users {
                guard user.cloudProfileImageRecordName != nil || user.profileImageURL != nil else {
                    continue
                }

                group.addTask { @MainActor in
                    let cacheKey = ImageCache.profileImageKey(userId: user.id)

                    if !forceRefresh, ImageCache.shared.get(cacheKey) != nil {
                        return (user.id, nil)
                    }

                    if let image = await self.loadImage(from: user.profileImageURL) {
                        return (user.id, image)
                    }

                    if forceRefresh || user.profileImageURL == nil {
                        do {
                            if let downloadedURL = try await dependencies.profileImageManager.downloadImageFromCloud(userId: user.id),
                               let image = await self.loadImage(from: downloadedURL) {
                                return (user.id, image)
                            }
                        } catch {
                            self.logger.warning("Failed to preload profile image for \(user.username): \(error.localizedDescription)")
                        }
                    }

                    return (user.id, nil)
                }
            }

            for await (userId, image) in group {
                if let image = image {
                    let cacheKey = ImageCache.profileImageKey(userId: userId)
                    ImageCache.shared.set(cacheKey, image: image)
                }
            }
        }
    }

    func preloadSharedRecipeAndProfileImages(sharedRecipes: [SharedRecipe]) async {
        var needsPreload = false
        for sharedRecipe in sharedRecipes {
            let recipeKey = ImageCache.recipeImageKey(recipeId: sharedRecipe.recipe.id)
            let profileKey = ImageCache.profileImageKey(userId: sharedRecipe.sharedBy.id)
            if ImageCache.shared.get(recipeKey) == nil || ImageCache.shared.get(profileKey) == nil {
                needsPreload = true
                break
            }
        }

        guard needsPreload else { return }
        let displayScale = max(UITraitCollection.current.displayScale, 1)

        await withTaskGroup(of: (String, UIImage?).self) { group in
            for sharedRecipe in sharedRecipes {
                let recipeId = sharedRecipe.recipe.id
                group.addTask { @MainActor in
                    let cacheKey = ImageCache.recipeImageKey(recipeId: recipeId, variant: "thumbnail")
                    if ImageCache.shared.get(cacheKey) != nil {
                        return (cacheKey, nil)
                    }
                    if let image = await self.loadImage(
                        from: sharedRecipe.recipe.imageURL,
                        maxPixelSize: 70 * displayScale
                    ) {
                        return (cacheKey, image)
                    }
                    return (cacheKey, nil)
                }

                let userId = sharedRecipe.sharedBy.id
                group.addTask { @MainActor in
                    let cacheKey = ImageCache.profileImageKey(userId: userId)
                    if ImageCache.shared.get(cacheKey) != nil {
                        return (cacheKey, nil)
                    }
                    if let image = await self.loadImage(from: sharedRecipe.sharedBy.profileImageURL) {
                        return (cacheKey, image)
                    }
                    return (cacheKey, nil)
                }
            }

            for await (cacheKey, image) in group {
                if let image = image {
                    ImageCache.shared.set(cacheKey, image: image)
                }
            }
        }
    }

    private func loadImage(from url: URL?, maxPixelSize: CGFloat? = nil) async -> UIImage? {
        guard let url else { return nil }

        do {
            return try await ImageLoadingPipeline.loadImage(fromFileURL: url, maxPixelSize: maxPixelSize)
        } catch {
            return nil
        }
    }
}
