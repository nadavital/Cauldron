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
    let preferredWidth: CGFloat?
    let dependencies: DependencyContainer?
    @State private var customCoverImage: UIImage?
    @State private var isLoadingImage = false

    init(
        collection: Collection,
        recipeImages: [URL?],
        preferredWidth: CGFloat? = 200,
        dependencies: DependencyContainer? = nil
    ) {
        self.collection = collection
        self.recipeImages = recipeImages
        self.preferredWidth = preferredWidth
        self.dependencies = dependencies
    }

    private var additionalRecipeCount: Int {
        max(0, collection.recipeCount - 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            coverContent
                .aspectRatio(1, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(collectionColor.opacity(0.2), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: collectionSymbolName)
                        .font(.subheadline)
                        .foregroundStyle(collectionColor)

                    Text(collection.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }

                Text("\(collection.recipeCount) recipe\(collection.recipeCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: preferredWidth, alignment: .leading)
        .frame(maxWidth: preferredWidth == nil ? .infinity : nil, alignment: .leading)
        .task(id: collection.coverImageURL?.absoluteString ?? collection.cloudCoverImageRecordName) {
            await loadCustomImage()
        }
    }

    @ViewBuilder
    private var coverContent: some View {
        if collection.coverImageType == .customImage {
            customImageView
        } else {
            recipeGridView
        }
    }

    private var recipeGridView: some View {
        GeometryReader { proxy in
            let tileSize = proxy.size.width / 2

            if collection.recipeCount == 0 || recipeImages.isEmpty || recipeImages.allSatisfy({ $0 == nil }) {
                collectionColor
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: collectionSymbolName)
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(collection.recipeCount == 0 ? "No recipes" : "\(collection.recipeCount) recipe\(collection.recipeCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    )
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        recipeImageTile(at: 0, size: tileSize)
                        recipeImageTile(at: 1, size: tileSize)
                    }
                    HStack(spacing: 0) {
                        recipeImageTile(at: 2, size: tileSize)
                        recipeImageTile(at: 3, size: tileSize)
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
        .overlay {
            if index == 3, additionalRecipeCount > 0 {
                ZStack {
                    Rectangle()
                        .fill(.black.opacity(0.45))
                    Text("+\(additionalRecipeCount)")
                        .font(.system(size: size * 0.22, weight: .semibold))
                        .foregroundStyle(.white)
                }
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
                    .foregroundStyle(.white.opacity(0.5))
            )
    }

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
        guard collection.coverImageType == .customImage else {
            customCoverImage = nil
            return
        }

        let loader = dependencies?.entityImageLoader ?? EntityImageLoader.shared
        if let image = await loader.loadCollectionCoverImage(for: collection, dependencies: dependencies) {
            if let currentImage = customCoverImage {
                if !ImageLoadingPipeline.areImagesEqual(image, currentImage) {
                    customCoverImage = image
                }
            } else {
                customCoverImage = image
            }
        } else {
            customCoverImage = nil
        }
    }

    private var collectionColor: Color {
        if let colorHex = collection.color {
            return Color(hex: colorHex) ?? .cauldronOrange
        }
        return .cauldronOrange
    }

    private var collectionSymbolName: String {
        collection.symbolName ?? "folder.fill"
    }
}
