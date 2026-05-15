//
//  CollectionCardView.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import SwiftUI

struct CollectionRecipeImageSource: Hashable {
    let recipeId: UUID?
    let imageURL: URL?
    let ownerId: UUID?
    let hasCloudImage: Bool

    init(recipeId: UUID? = nil, imageURL: URL?, ownerId: UUID? = nil, hasCloudImage: Bool = false) {
        self.recipeId = recipeId
        self.imageURL = imageURL
        self.ownerId = ownerId
        self.hasCloudImage = hasCloudImage
    }

    var canLoadImage: Bool {
        imageURL != nil || (recipeId != nil && hasCloudImage)
    }
}

struct CollectionCardView: View {
    let collection: Collection
    let recipeImages: [URL?]  // Up to 4 recipe image URLs for the grid
    let recipeImageSources: [CollectionRecipeImageSource]
    let preferredWidth: CGFloat?
    let dependencies: DependencyContainer?
    @State private var customCoverImage: UIImage?
    @State private var loadedCoverKey: String?
    @State private var isLoadingImage = false

    init(
        collection: Collection,
        recipeImages: [URL?],
        recipeImageSources: [CollectionRecipeImageSource]? = nil,
        preferredWidth: CGFloat? = 200,
        dependencies: DependencyContainer? = nil
    ) {
        self.collection = collection
        self.recipeImages = recipeImages
        self.recipeImageSources = recipeImageSources ?? recipeImages.map {
            CollectionRecipeImageSource(imageURL: $0)
        }
        self.preferredWidth = preferredWidth
        self.dependencies = dependencies
    }

    private var additionalRecipeCount: Int {
        max(0, collection.recipeCount - 4)
    }

    private var customCoverTaskID: String {
        let remoteKey = collection.coverImageURL?.absoluteString ?? collection.cloudCoverImageRecordName ?? "no-cover"
        return "\(collection.id.uuidString)|\(collection.coverImageType.rawValue)|\(remoteKey)"
    }

    private var coverImageSources: [CollectionRecipeImageSource] {
        Array(recipeImageSources.prefix(4))
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
        .task(id: customCoverTaskID) {
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

            if collection.recipeCount == 0 {
                collectionColor
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: collectionSymbolName)
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("No recipes")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    )
            } else if coverImageSources.isEmpty || coverImageSources.allSatisfy({ !$0.canLoadImage }) {
                placeholderGridView(tileSize: tileSize)
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

    private func placeholderGridView(tileSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                placeholderTile(at: 0, size: tileSize)
                placeholderTile(at: 1, size: tileSize)
            }
            HStack(spacing: 0) {
                placeholderTile(at: 2, size: tileSize)
                placeholderTile(at: 3, size: tileSize)
            }
        }
    }

    private func recipeImageTile(at index: Int, size: CGFloat) -> some View {
        Group {
            if index < coverImageSources.count, coverImageSources[index].canLoadImage {
                let imageSource = coverImageSources[index]
                RecipeImageView(
                    previewImageURL: imageSource.imageURL,
                    showPlaceholderText: false,
                    recipeImageService: (dependencies ?? DependencyContainer.shared).recipeImageService,
                    recipeId: imageSource.recipeId,
                    ownerId: imageSource.ownerId
                )
                .id("\(imageSource.recipeId?.uuidString ?? "no-recipe")|\(imageSource.imageURL?.absoluteString ?? "no-url")")
                .frame(width: size, height: size)
                .clipped()
            } else {
                placeholderTile(at: index, size: size)
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

    private func placeholderTile(at index: Int, size: CGFloat) -> some View {
        let symbols = [collectionSymbolName, "fork.knife", "book.closed.fill", "sparkles"]
        let opacity = [0.28, 0.22, 0.18, 0.24][min(index, 3)]

        return Rectangle()
            .fill(collectionColor.opacity(opacity))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbols[min(index, symbols.count - 1)])
                    .font(.system(size: size * 0.28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
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
            loadedCoverKey = nil
            isLoadingImage = false
            return
        }

        if loadedCoverKey != customCoverTaskID {
            customCoverImage = nil
        }
        isLoadingImage = true
        defer { isLoadingImage = false }

        let loader = dependencies?.entityImageLoader ?? EntityImageLoader.shared
        if let image = await loader.loadCollectionCoverImage(for: collection, dependencies: dependencies) {
            guard !Task.isCancelled else { return }
            if let currentImage = customCoverImage {
                if !ImageLoadingPipeline.areImagesEqual(image, currentImage) {
                    customCoverImage = image
                }
            } else {
                customCoverImage = image
            }
            loadedCoverKey = customCoverTaskID
        } else {
            customCoverImage = nil
            loadedCoverKey = nil
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
