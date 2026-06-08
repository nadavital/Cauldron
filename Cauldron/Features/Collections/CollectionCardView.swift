//
//  CollectionCardView.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import SwiftUI

struct CollectionRecipeImageSource: Hashable, Sendable {
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

enum CollectionCoverPagePolicy {
    static func shouldReserveCustomCoverPage(
        coverImageType: CoverImageType,
        coverImageURL: URL?,
        cloudCoverImageRecordName: String?,
        hasLoadedCustomCoverImage: Bool
    ) -> Bool {
        guard coverImageType == .customImage else { return false }
        return hasLoadedCustomCoverImage ||
            coverImageURL != nil ||
            cloudCoverImageRecordName != nil
    }
}

struct CollectionCoverArtwork: View {
    let imageSources: [CollectionRecipeImageSource]
    let additionalRecipeCount: Int
    let collectionColor: Color
    let collectionSymbolName: String
    let dependencies: DependencyContainer?
    let iconScale: CGFloat

    private var visibleImageSources: [CollectionRecipeImageSource] {
        Array(imageSources.filter { $0.canLoadImage }.prefix(4))
    }

    var body: some View {
        GeometryReader { proxy in
            if visibleImageSources.isEmpty {
                defaultGradientCover
            } else {
                collageView(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    @ViewBuilder
    private func collageView(width: CGFloat, height: CGFloat) -> some View {
        switch visibleImageSources.count {
        case 1:
            recipeImageTile(0, width: width, height: height)
        case 2:
            HStack(spacing: 0) {
                recipeImageTile(0, width: width / 2, height: height)
                recipeImageTile(1, width: width / 2, height: height)
            }
        case 3:
            HStack(spacing: 0) {
                recipeImageTile(0, width: width * 0.58, height: height)
                VStack(spacing: 0) {
                    recipeImageTile(1, width: width * 0.42, height: height / 2)
                    recipeImageTile(2, width: width * 0.42, height: height / 2)
                }
            }
        default:
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    recipeImageTile(0, width: width / 2, height: height / 2)
                    recipeImageTile(1, width: width / 2, height: height / 2)
                }
                HStack(spacing: 0) {
                    recipeImageTile(2, width: width / 2, height: height / 2)
                    recipeImageTile(3, width: width / 2, height: height / 2)
                }
            }
        }
    }

    private func recipeImageTile(_ index: Int, width: CGFloat, height: CGFloat) -> some View {
        let imageSource = visibleImageSources[index]

        return RecipeImageView(
            imageURL: imageSource.imageURL,
            size: .collectionTile,
            showPlaceholderText: false,
            recipeImageService: (dependencies ?? DependencyContainer.shared).recipeImageService,
            recipeId: imageSource.recipeId,
            ownerId: imageSource.ownerId
        )
        .id("\(imageSource.recipeId?.uuidString ?? "no-recipe")|\(imageSource.imageURL?.absoluteString ?? "no-url")")
        .frame(width: width, height: height)
        .clipped()
        .overlay {
            if index == min(visibleImageSources.count, 4) - 1, additionalRecipeCount > 0 {
                ZStack {
                    Rectangle()
                        .fill(.black.opacity(0.42))
                    Text("+\(additionalRecipeCount)")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var defaultGradientCover: some View {
        LinearGradient(
            stops: [
                .init(color: collectionColor, location: 0),
                .init(color: Color.cauldronOrange, location: 0.52),
                .init(color: Color(red: 0.98, green: 0.76, blue: 0.22), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .overlay {
            Image(systemName: collectionSymbolName)
                .font(.system(size: iconScale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
        }
    }
}

struct CollectionCardView: View {
    let collection: Collection
    let recipeImages: [URL?]  // Up to 4 recipe image URLs for the grid
    let recipeImageSources: [CollectionRecipeImageSource]
    let preferredWidth: CGFloat?
    let dependencies: DependencyContainer?
    /// Optional owner shown as a creator tag over the cover (for friends' collections).
    let owner: User?
    @State private var customCoverImage: UIImage?
    @State private var loadedCoverKey: String?
    @State private var isLoadingImage = false
    /// Owner-tag text adapts to the cover's top luminance (white over dark
    /// covers, black over light ones). Defaults to white for gradient/collage
    /// covers, which read well with white text.
    @State private var overlayPrefersDarkText = false

    init(
        collection: Collection,
        recipeImages: [URL?],
        recipeImageSources: [CollectionRecipeImageSource]? = nil,
        preferredWidth: CGFloat? = 200,
        owner: User? = nil,
        dependencies: DependencyContainer? = nil
    ) {
        self.collection = collection
        self.recipeImages = recipeImages
        self.recipeImageSources = recipeImageSources ?? recipeImages.map {
            CollectionRecipeImageSource(imageURL: $0)
        }
        self.preferredWidth = preferredWidth
        self.owner = owner
        self.dependencies = dependencies
    }

    private var additionalRecipeCount: Int {
        max(0, collection.recipeCount - 4)
    }

    private var customCoverTaskID: String {
        collection.customCoverImageCacheKey
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
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .stroke(collectionColor.opacity(0.2), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if let owner, let dependencies {
                        GlassEffectContainer(spacing: 2) {
                            HStack(spacing: 6) {
                                ProfileAvatar(user: owner, size: 22, dependencies: dependencies)
                                Text(owner.displayName)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                    .foregroundStyle(overlayPrefersDarkText ? .black : .white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .glassEffect(.clear, in: Capsule())
                        }
                        .padding(8)
                    }
                }

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
        if CollectionCoverPagePolicy.shouldReserveCustomCoverPage(
            coverImageType: collection.coverImageType,
            coverImageURL: collection.coverImageURL,
            cloudCoverImageRecordName: collection.cloudCoverImageRecordName,
            hasLoadedCustomCoverImage: customCoverImage != nil
        ) {
            customImageView
        } else {
            collectionCoverArtwork
        }
    }

    private var collectionCoverArtwork: some View {
        CollectionCoverArtwork(
            imageSources: coverImageSources,
            additionalRecipeCount: additionalRecipeCount,
            collectionColor: collectionColor,
            collectionSymbolName: collectionSymbolName,
            dependencies: dependencies,
            iconScale: 46
        )
    }

    private var customImageView: some View {
        Group {
            if let customCoverImage = customCoverImage {
                Image(uiImage: customCoverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoadingImage {
                collectionCoverArtwork
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            } else {
                collectionCoverArtwork
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
            if let luminance = image.topRegionLuminance() {
                overlayPrefersDarkText = luminance > 0.6
            }
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
