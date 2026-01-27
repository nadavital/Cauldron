//
//  CollectionCardView.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import SwiftUI

struct CollectionCardView: View {
    let collection: Collection
    let recipeImages: [URL?]  // Up to 4 recipe image URLs for the grid
    let dependencies: DependencyContainer?

    @State private var customCoverImage: UIImage?
    @State private var isLoadingImage = false

    init(collection: Collection, recipeImages: [URL?], dependencies: DependencyContainer? = nil) {
        self.collection = collection
        self.recipeImages = recipeImages
        self.dependencies = dependencies
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image/grid
            ZStack {
                switch collection.coverImageType {
                case .customImage:
                    customImageView
                        .frame(width: 160, height: 160)
                case .emoji:
                    // Show emoji with color background
                    if let emoji = collection.emoji {
                        collectionColor
                            .frame(width: 160, height: 160)
                            .overlay(
                                Text(emoji)
                                    .font(.system(size: 60))
                            )
                    } else {
                        // Fallback to grid if emoji not set
                        recipeGridView
                            .frame(width: 160, height: 160)
                    }
                case .color:
                    // Show solid color with folder icon and name
                    collectionColor
                        .frame(width: 160, height: 160)
                        .overlay(
                            VStack(spacing: 4) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.8))
                                Text(collection.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                            }
                        )
                case .recipeGrid:
                    // Default: Show 2x2 grid of recipe images
                    recipeGridView
                        .frame(width: 160, height: 160)
                }
            }
            .cornerRadius(12)
            .clipped()
            .task {
                if collection.coverImageType == .customImage {
                    await loadCustomImage()
                }
            }

            // Collection name and count
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text("\(collection.recipeCount) recipe\(collection.recipeCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 160, alignment: .leading)
            .padding(.top, 8)
        }
        .frame(width: 160)
    }

    // MARK: - Recipe Grid View

    private var recipeGridView: some View {
        Group {
            let size: CGFloat = 80  // 160 / 2 for the 2x2 grid

            // Show empty state if collection has no recipes, not based on loaded images
            if collection.recipeCount == 0 {
                // Empty state - show placeholder
                collectionColor
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.6))
                            Text("No recipes")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    )
            } else if recipeImages.isEmpty || recipeImages.allSatisfy({ $0 == nil }) {
                // Has recipes but images not loaded - show placeholder with count
                collectionColor
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.6))
                            Text("\(collection.recipeCount) recipe\(collection.recipeCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    )
            } else {
                // Show 2x2 grid of recipe images
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        recipeImageTile(at: 0, size: size)
                        recipeImageTile(at: 1, size: size)
                    }
                    HStack(spacing: 0) {
                        recipeImageTile(at: 2, size: size)
                        recipeImageTile(at: 3, size: size)
                    }
                }
            }
        }
    }

    private func recipeImageTile(at index: Int, size: CGFloat) -> some View {
        Group {
            if index < recipeImages.count, let imageURL = recipeImages[index] {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        placeholderTile(size: size)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipped()
                    case .failure:
                        placeholderTile(size: size)
                    @unknown default:
                        placeholderTile(size: size)
                    }
                }
            } else {
                placeholderTile(size: size)
            }
        }
    }

    private func placeholderTile(size: CGFloat) -> some View {
        Rectangle()
            .fill(collectionColor.opacity(0.3))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "fork.knife")
                    .font(.system(size: size * 0.3))
                    .foregroundColor(.white.opacity(0.5))
            )
    }

    // MARK: - Custom Image View

    private var customImageView: some View {
        Group {
            if let customCoverImage = customCoverImage {
                Image(uiImage: customCoverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoadingImage {
                collectionColor
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            } else {
                // Fallback to recipe grid if custom image fails to load
                recipeGridView
            }
        }
    }

    @MainActor
    private func loadCustomImage() async {
        let cacheKey = ImageCache.collectionImageKey(collectionId: collection.id)

        // Strategy 0: Check in-memory cache first (fastest)
        if let cachedImage = ImageCache.shared.get(cacheKey) {
            // CRITICAL: Always set customCoverImage if it's nil (initial load)
            if let currentImage = customCoverImage {
                // Only update UI if the image actually changed
                if !areImagesEqual(cachedImage, currentImage) {
                    customCoverImage = cachedImage
                }
            } else {
                // First load - always set the image
                customCoverImage = cachedImage
            }
            return
        }

        // Strategy 1: Try loading from local file URL
        if let coverImageURL = collection.coverImageURL,
           let imageData = try? Data(contentsOf: coverImageURL),
           let image = UIImage(data: imageData) {
            // CRITICAL: Always set customCoverImage if it's nil (initial load)
            if let currentImage = customCoverImage {
                // Only update UI if the image actually changed
                if !areImagesEqual(image, currentImage) {
                    customCoverImage = image
                    ImageCache.shared.set(cacheKey, image: image)
                }
            } else {
                // First load - always set the image
                customCoverImage = image
                ImageCache.shared.set(cacheKey, image: image)
            }
            return
        }

        // Strategy 2: If local file is missing but we have a cloud record, try downloading
        // This handles the case where app was reinstalled or local storage was cleared
        if let dependencies = dependencies,
           collection.cloudCoverImageRecordName != nil,
           collection.coverImageURL == nil {
            AppLogger.general.info("Local collection cover image missing, attempting download from CloudKit for collection \(collection.name)")

            do {
                if let downloadedURL = try await dependencies.collectionImageManager.downloadImageFromCloud(collectionId: collection.id),
                   let imageData = try? Data(contentsOf: downloadedURL),
                   let image = UIImage(data: imageData) {
                    // CRITICAL: Always set customCoverImage if it's nil (initial load)
                    if let currentImage = customCoverImage {
                        // Only update UI if the image actually changed
                        if !areImagesEqual(image, currentImage) {
                            customCoverImage = image
                            ImageCache.shared.set(cacheKey, image: image)
                        }
                    } else {
                        // First load - always set the image
                        customCoverImage = image
                        ImageCache.shared.set(cacheKey, image: image)
                    }
                    // Downloaded collection cover image from CloudKit (don't log routine operations)
                }
            } catch {
                AppLogger.general.warning("Failed to download collection cover image from CloudKit: \(error.localizedDescription)")
                // Fall back to recipe grid display
            }
        }
    }

    /// Compare two images to see if they're visually identical
    /// This prevents UI updates when CloudKit sync returns the same image
    private func areImagesEqual(_ image1: UIImage, _ image2: UIImage) -> Bool {
        // Fast path: if they're literally the same object, they're equal
        if image1 === image2 {
            return true
        }

        // Compare image dimensions
        if image1.size != image2.size {
            return false
        }

        // Compare scale
        if image1.scale != image2.scale {
            return false
        }

        // If dimensions and scale match, assume they're the same image
        // This prevents expensive byte-by-byte comparison
        return true
    }

    // MARK: - Color

    private var collectionColor: Color {
        if let colorHex = collection.color {
            return Color(hex: colorHex) ?? .cauldronOrange
        }
        return .cauldronOrange
    }
}
