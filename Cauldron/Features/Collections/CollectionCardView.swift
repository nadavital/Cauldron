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
        isLoadingImage = true
        defer { isLoadingImage = false }

        // Strategy 1: Try loading from local file URL
        if let coverImageURL = collection.coverImageURL,
           let imageData = try? Data(contentsOf: coverImageURL),
           let image = UIImage(data: imageData) {
            customCoverImage = image
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
                    customCoverImage = image
                    AppLogger.general.info("✅ Downloaded collection cover image from CloudKit for collection \(collection.name)")
                }
            } catch {
                AppLogger.general.warning("Failed to download collection cover image from CloudKit: \(error.localizedDescription)")
                // Fall back to recipe grid display
            }
        }
    }

    // MARK: - Color

    private var collectionColor: Color {
        if let colorHex = collection.color {
            return Color(hex: colorHex) ?? .cauldronOrange
        }
        return .cauldronOrange
    }
}

// MARK: - Collection Reference Card

struct CollectionReferenceCardView: View {
    let reference: CollectionReference
    let recipeImages: [URL?]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover - show placeholder for referenced collections
            ZStack {
                Color.gray.opacity(0.2)
                    .aspectRatio(1, contentMode: .fill)

                VStack(spacing: 8) {
                    if let emoji = reference.collectionEmoji {
                        Text(emoji)
                            .font(.system(size: 50))
                    } else {
                        Image(systemName: "folder.badge.person.crop")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .cornerRadius(12)
            .overlay(
                // "Shared" badge
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .padding(8),
                alignment: .topTrailing
            )

            // Collection name and count
            VStack(alignment: .leading, spacing: 4) {
                Text(reference.collectionName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text("\(reference.recipeCount) recipe\(reference.recipeCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
    }
}
