//
//  RecipeImageView.swift
//  Cauldron
//
//  Created by Claude Code on 10/28/25.
//

import SwiftUI

private enum RecipeImageLoadingPipeline {
    static func initialCachedImage(recipeId: UUID?) -> UIImage? {
        guard let recipeId = recipeId else { return nil }
        let cacheKey = ImageCache.recipeImageKey(recipeId: recipeId)
        return ImageCache.shared.get(cacheKey)
    }

    static func areImagesEqual(_ lhs: UIImage, _ rhs: UIImage) -> Bool {
        if lhs === rhs {
            return true
        }
        return lhs.size == rhs.size && lhs.scale == rhs.scale
    }

    static func loadImage(
        with service: RecipeImageService,
        recipeId: UUID?,
        imageURL: URL?,
        ownerId: UUID?
    ) async -> Result<UIImage, ImageLoadError> {
        if let recipeId = recipeId {
            return await service.loadImage(forRecipeId: recipeId, localURL: imageURL, ownerId: ownerId)
        }
        return await service.loadImage(from: imageURL)
    }

    static func applyLoadedImage(
        _ image: UIImage,
        loadedImage: inout UIImage?,
        imageOpacity: inout Double
    ) {
        if let currentImage = loadedImage {
            if !areImagesEqual(image, currentImage) {
                loadedImage = image
                withAnimation(.easeOut(duration: 0.3)) {
                    imageOpacity = 1.0
                }
            }
        } else {
            loadedImage = image
            withAnimation(.easeOut(duration: 0.3)) {
                imageOpacity = 1.0
            }
        }
    }
}

/// Reusable recipe image view with consistent styling and loading states
struct RecipeImageView: View {
    let imageURL: URL?
    let size: ImageSize
    let showPlaceholderText: Bool
    let recipeImageService: RecipeImageService
    let recipeId: UUID?
    let ownerId: UUID?

    @State private var loadedImage: UIImage?
    @State private var imageOpacity: Double = 0

    init(
        imageURL: URL?,
        size: ImageSize = .card,
        showPlaceholderText: Bool = false,
        recipeImageService: RecipeImageService,
        recipeId: UUID? = nil,
        ownerId: UUID? = nil
    ) {
        self.imageURL = imageURL
        self.size = size
        self.showPlaceholderText = showPlaceholderText
        self.recipeImageService = recipeImageService
        self.recipeId = recipeId
        self.ownerId = ownerId

        // Initialize with cache to avoid placeholder flicker on back-navigation.
        if let cachedImage = RecipeImageLoadingPipeline.initialCachedImage(recipeId: recipeId) {
            _loadedImage = State(initialValue: cachedImage)
            _imageOpacity = State(initialValue: 1.0)
        }
    }

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(imageOpacity)
            } else {
                placeholderView
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
        .shadow(
            color: .black.opacity(size.shadowOpacity),
            radius: size.shadowRadius,
            x: 0,
            y: size.shadowY
        )
        .task(id: recipeId) {
            await loadImage()
        }
    }

    private var placeholderView: some View {
        ZStack {
            // Adaptive gradient background
            LinearGradient(
                colors: [
                    Color.cauldronOrange.opacity(0.08),
                    Color.cauldronOrange.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                Image(systemName: "fork.knife")
                    .font(.system(size: size.iconSize))
                    .foregroundStyle(Color.cauldronOrange.opacity(0.3))

                if showPlaceholderText {
                    Text("No Image")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadImage() async {
        let result = await RecipeImageLoadingPipeline.loadImage(
            with: recipeImageService,
            recipeId: recipeId,
            imageURL: imageURL,
            ownerId: ownerId
        )
        switch result {
        case .success(let image):
            RecipeImageLoadingPipeline.applyLoadedImage(
                image,
                loadedImage: &loadedImage,
                imageOpacity: &imageOpacity
            )
        case .failure:
            break
        }
    }
}

// MARK: - Image Size Presets

extension RecipeImageView {
    enum ImageSize {
        case hero
        case card
        case thumbnail
        case preview

        var width: CGFloat? {
            switch self {
            case .hero: return nil // Full width
            case .card: return 240
            case .thumbnail: return 70
            case .preview: return nil // Dynamic
            }
        }

        var height: CGFloat? {
            switch self {
            case .hero: return nil // Dynamic based on aspect ratio
            case .card: return 160
            case .thumbnail: return 70
            case .preview: return nil // Dynamic
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .hero: return 0 // Edge-to-edge, no corners
            case .card, .preview: return 16
            case .thumbnail: return 12
            }
        }

        var shadowOpacity: Double {
            switch self {
            case .hero: return 0 // No shadow for full-bleed
            case .card, .preview: return 0.1 // Medium shadow
            case .thumbnail: return 0.05 // Subtle shadow
            }
        }

        var shadowRadius: CGFloat {
            switch self {
            case .hero: return 0
            case .card, .preview: return 8
            case .thumbnail: return 4
            }
        }

        var shadowY: CGFloat {
            switch self {
            case .hero: return 0
            case .card, .preview: return 4
            case .thumbnail: return 2
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .hero, .preview: return 48
            case .card: return 32
            case .thumbnail: return 20
            }
        }
    }
}

// MARK: - Convenience Initializers

extension RecipeImageView {
    /// Create a hero-sized image view
    init(heroImageURL: URL?, recipeImageService: RecipeImageService, recipeId: UUID? = nil, ownerId: UUID? = nil) {
        self.init(imageURL: heroImageURL, size: .hero, showPlaceholderText: false, recipeImageService: recipeImageService, recipeId: recipeId, ownerId: ownerId)
    }

    /// Create a card-sized image view
    init(cardImageURL: URL?, recipeImageService: RecipeImageService, recipeId: UUID? = nil, ownerId: UUID? = nil) {
        self.init(imageURL: cardImageURL, size: .card, showPlaceholderText: false, recipeImageService: recipeImageService, recipeId: recipeId, ownerId: ownerId)
    }

    /// Create a thumbnail-sized image view
    init(thumbnailImageURL: URL?, recipeImageService: RecipeImageService, recipeId: UUID? = nil, ownerId: UUID? = nil) {
        self.init(imageURL: thumbnailImageURL, size: .thumbnail, showPlaceholderText: false, recipeImageService: recipeImageService, recipeId: recipeId, ownerId: ownerId)
    }

    /// Create a preview-sized image view
    init(previewImageURL: URL?, showPlaceholderText: Bool = true, recipeImageService: RecipeImageService, recipeId: UUID? = nil, ownerId: UUID? = nil) {
        self.init(imageURL: previewImageURL, size: .preview, showPlaceholderText: showPlaceholderText, recipeImageService: recipeImageService, recipeId: recipeId, ownerId: ownerId)
    }

    /// Create a card-sized image view from a Recipe object (with CloudKit fallback)
    init(recipe: Recipe, recipeImageService: RecipeImageService) {
        self.init(imageURL: recipe.imageURL, size: .card, showPlaceholderText: false, recipeImageService: recipeImageService, recipeId: recipe.id, ownerId: recipe.ownerId)
    }

    /// Create a thumbnail-sized image view from a Recipe object (with CloudKit fallback)
    init(thumbnailForRecipe recipe: Recipe, recipeImageService: RecipeImageService) {
        self.init(imageURL: recipe.imageURL, size: .thumbnail, showPlaceholderText: false, recipeImageService: recipeImageService, recipeId: recipe.id, ownerId: recipe.ownerId)
    }
}

extension HeroRecipeImageView {
    /// Create from a Recipe object (with CloudKit fallback)
    init(recipe: Recipe, recipeImageService: RecipeImageService) {
        self.init(imageURL: recipe.imageURL, recipeImageService: recipeImageService, recipeId: recipe.id, ownerId: recipe.ownerId)
    }
}

// MARK: - Hero Recipe Image View

/// Hero image view with card style and padding
struct HeroRecipeImageView: View {
    let imageURL: URL?
    let recipeImageService: RecipeImageService
    let recipeId: UUID?
    let ownerId: UUID?

    @State private var loadedImage: UIImage?
    @State private var imageOpacity: Double = 0
    @State private var containerWidth: CGFloat = 0

    init(imageURL: URL?, recipeImageService: RecipeImageService, recipeId: UUID? = nil, ownerId: UUID? = nil) {
        self.imageURL = imageURL
        self.recipeImageService = recipeImageService
        self.recipeId = recipeId
        self.ownerId = ownerId

        if let cachedImage = RecipeImageLoadingPipeline.initialCachedImage(recipeId: recipeId) {
            _loadedImage = State(initialValue: cachedImage)
            _imageOpacity = State(initialValue: 1.0)
        }
    }

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: imageHeight(for: image))
                    .clipped()
                    .overlay(alignment: .bottom) {
                        // Bottom gradient for smooth transition to content
                        LinearGradient(
                            colors: [
                                Color(uiColor: .systemBackground).opacity(0),
                                Color(uiColor: .systemBackground).opacity(0.5),
                                Color(uiColor: .systemBackground)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 200)
                    }
                    .opacity(imageOpacity)
            } else {
                placeholderView
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: HeroImageWidthPreferenceKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(HeroImageWidthPreferenceKey.self) { width in
            guard width > 0 else { return }
            containerWidth = width
        }
        .task(id: recipeId) {
            await loadImage()
        }
        .onChange(of: imageURL) { _, _ in
            Task {
                await loadImage()
            }
        }
    }

    private var placeholderView: some View {
        ZStack {
            // Adaptive gradient background
            LinearGradient(
                colors: [
                    Color.cauldronOrange.opacity(0.08),
                    Color.cauldronOrange.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "fork.knife")
                .font(.system(size: 48))
                .foregroundStyle(Color.cauldronOrange.opacity(0.3))
        }
        .frame(height: 380)
        .frame(maxWidth: .infinity)
        .background(Color.cauldronOrange.opacity(0.05))
    }

    private func imageHeight(for image: UIImage) -> CGFloat {
        let aspectRatio = image.size.width / image.size.height
        let estimatedWidth: CGFloat = max(containerWidth, 1)

        // Calculate height based on aspect ratio
        let calculatedHeight = estimatedWidth / aspectRatio

        // Clamp between min and max values for better UX
        // Increased max height for hero effect
        return min(max(calculatedHeight, 300), 500)
    }

    private func loadImage() async {
        let result = await RecipeImageLoadingPipeline.loadImage(
            with: recipeImageService,
            recipeId: recipeId,
            imageURL: imageURL,
            ownerId: ownerId
        )
        switch result {
        case .success(let image):
            RecipeImageLoadingPipeline.applyLoadedImage(
                image,
                loadedImage: &loadedImage,
                imageOpacity: &imageOpacity
            )
        case .failure:
            break
        }
    }
}

private struct HeroImageWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Preview

#Preview("Card") {
    let dependencies = try! DependencyContainer.preview()
    return VStack(spacing: 20) {
        RecipeImageView(cardImageURL: nil, recipeImageService: dependencies.recipeImageService)
        RecipeImageView(thumbnailImageURL: nil, recipeImageService: dependencies.recipeImageService)
    }
    .padding()
}
