//
//  CollectionCoverView.swift
//  Cauldron
//
//  The paged cover carousel for a collection (custom cover image + recipe
//  pages). Extracted from CollectionDetailView; owns its own cover-image
//  loading state and page selection.
//

import SwiftUI

struct CollectionCoverView: View {
    let collection: Collection
    let recipes: [Recipe]
    let recipeImageSources: [CollectionRecipeImageSource]
    let dependencies: DependencyContainer

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var customCoverImage: UIImage?
    @State private var loadedCoverKey: String?
    @State private var isLoadingCoverImage = false
    @State private var selectedCoverPage = 0

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $selectedCoverPage) {
                if showsCustomCollectionCoverPage {
                    customCoverView
                        .tag(0)
                        .accessibilityLabel("\(collection.name) collection cover")
                }

                if collectionCoverRecipePages.isEmpty && !showsCustomCollectionCoverPage {
                    fallbackCoverView
                        .tag(0)
                        .accessibilityLabel("\(collection.name) collection cover")
                }

                ForEach(Array(collectionCoverRecipePages.enumerated()), id: \.element.id) { index, recipe in
                    collectionRecipeCoverPage(for: recipe)
                        .tag(showsCustomCollectionCoverPage ? index + 1 : index)
                    .accessibilityLabel(recipe.title)
                }
            }
            .id(collectionCoverPagesID)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity)
            .frame(height: horizontalSizeClass == .regular ? 360 : 260)
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.07), radius: 14, y: 6)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.appSurface)
            }

            if collectionCoverPageCount > 1 {
                collectionCoverPageIndicator
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .onChange(of: collectionCoverPageCount) { _, pageCount in
            selectedCoverPage = min(selectedCoverPage, max(0, pageCount - 1))
        }
        .task(id: customCoverTaskID) {
            await loadCustomCoverImage()
        }
    }

    // MARK: - Derived

    private var collectionColor: Color {
        Color(hex: collection.color ?? "#FF9933") ?? .cauldronOrange
    }

    private var collectionSymbolName: String {
        collection.symbolName ?? "folder.fill"
    }

    private var customCoverTaskID: String {
        let remoteKey = collection.coverImageURL?.absoluteString ?? collection.cloudCoverImageRecordName ?? "no-cover"
        return "\(collection.id.uuidString)|\(collection.coverImageType.rawValue)|\(remoteKey)"
    }

    private var showsCustomCollectionCoverPage: Bool {
        collection.coverImageType == .customImage
    }

    private var collectionCoverPageCount: Int {
        let customCoverCount = showsCustomCollectionCoverPage ? 1 : 0
        return max(1, customCoverCount + collectionCoverRecipePages.count)
    }

    private var collectionCoverPagesID: String {
        let recipePageKeys = collectionCoverRecipePages.map { recipe in
            [
                recipe.id.uuidString,
                recipe.imageURL?.absoluteString ?? "no-url",
                recipe.cloudImageRecordName ?? "no-cloud-image"
            ].joined(separator: ":")
        }
        let customCoverKey = showsCustomCollectionCoverPage ? customCoverTaskID : "no-custom-cover"
        return ([customCoverKey] + recipePageKeys).joined(separator: "|")
    }

    private var collectionCoverRecipePages: [Recipe] {
        let recipesById = RecipeDeduplication.byIdPreferringBest(recipes)
        let imageSourceByRecipeId = recipeImageSources.reduce(into: [UUID: CollectionRecipeImageSource]()) { result, source in
            if let recipeId = source.recipeId, result[recipeId] == nil {
                result[recipeId] = source
            }
        }
        var seenRecipeIds = Set<UUID>()
        let orderedRecipes = collection.recipeIds.compactMap { recipeId -> Recipe? in
            guard seenRecipeIds.insert(recipeId).inserted else {
                return nil
            }
            return recipesById[recipeId]
        }

        let imageCapableRecipes = orderedRecipes.filter { recipe in
            let imageSource = imageSourceByRecipeId[recipe.id]
            return recipe.imageURL != nil || recipe.cloudImageRecordName != nil || imageSource?.canLoadImage == true
        }

        return Array(imageCapableRecipes.prefix(10))
    }

    // MARK: - Pages

    @ViewBuilder
    private func collectionRecipeCoverPage(for recipe: Recipe) -> some View {
        ZStack(alignment: .bottomLeading) {
            RecipeImageView(
                imageURL: recipe.imageURL,
                size: .collectionTile,
                showPlaceholderText: false,
                recipeImageService: dependencies.recipeImageService,
                recipeId: recipe.id,
                ownerId: recipe.ownerId,
                privateRecordName: recipe.cloudRecordName
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.18), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )

            recipeCoverTitle(recipe.title)
        }
    }

    private func recipeCoverTitle(_ title: String) -> some View {
        Text(title.recipeDetailLineBreakFriendly())
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .minimumScaleFactor(0.88)
            .allowsTightening(true)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            .accessibilityHidden(true)
    }

    private var collectionCoverPageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<collectionCoverPageCount, id: \.self) { index in
                Capsule()
                    .fill(index == selectedCoverPage ? collectionColor : Color.secondary.opacity(0.28))
                    .frame(width: index == selectedCoverPage ? 18 : 6, height: 6)
                    .animation(.snappy(duration: 0.2), value: selectedCoverPage)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Cover page \(selectedCoverPage + 1) of \(collectionCoverPageCount)")
    }

    @ViewBuilder
    private var customCoverView: some View {
        if let customCoverImage {
            Image(uiImage: customCoverImage)
                .resizable()
                .scaledToFill()
        } else if isLoadingCoverImage {
            fallbackCoverView
                .overlay {
                    ProgressView()
                        .tint(.white)
                }
        } else {
            fallbackCoverView
        }
    }

    @ViewBuilder
    private var fallbackCoverView: some View {
        CollectionCoverArtwork(
            imageSources: [],
            additionalRecipeCount: 0,
            collectionColor: collectionColor,
            collectionSymbolName: collectionSymbolName,
            dependencies: dependencies,
            iconScale: 82
        )
    }

    // MARK: - Loading

    @MainActor
    private func loadCustomCoverImage() async {
        guard collection.coverImageType == .customImage else {
            customCoverImage = nil
            loadedCoverKey = nil
            isLoadingCoverImage = false
            return
        }

        if loadedCoverKey != customCoverTaskID {
            customCoverImage = nil
        }
        isLoadingCoverImage = true
        defer { isLoadingCoverImage = false }

        let image = await dependencies.entityImageLoader.loadCollectionCoverImage(
            for: collection,
            dependencies: dependencies
        )

        guard !Task.isCancelled else { return }

        if let image {
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
}
