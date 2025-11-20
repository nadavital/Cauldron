//
//  RecipeImageView.swift
//  Cauldron
//
//  Created by Claude Code on 10/28/25.
//

import SwiftUI

/// Reusable recipe image view with consistent styling and loading states
struct RecipeImageView: View {
    let imageURL: URL?
    let size: ImageSize
    let showPlaceholderText: Bool
    let recipeImageService: RecipeImageService
    let recipeId: UUID?
    let ownerId: UUID?

    @State private var loadedImage: UIImage?
    @State private var isLoading = true
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

        // CRITICAL: Initialize with cached image if available
        // This prevents showing placeholder when navigating back
        if let recipeId = recipeId {
            let cacheKey = ImageCache.recipeImageKey(recipeId: recipeId)
            if let cachedImage = ImageCache.shared.get(cacheKey) {
                _loadedImage = State(initialValue: cachedImage)
                _imageOpacity = State(initialValue: 1.0)
            }
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
        .task {
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
        // Strategy 0: Check in-memory cache first (fastest)
        if let recipeId = recipeId {
            let cacheKey = ImageCache.recipeImageKey(recipeId: recipeId)
            if let cachedImage = ImageCache.shared.get(cacheKey) {
                // CRITICAL: Always set loadedImage if it's nil (initial load)
                if let currentImage = loadedImage {
                    // Only update UI if the image actually changed
                    if !areImagesEqual(cachedImage, currentImage) {
                        loadedImage = cachedImage
                        imageOpacity = 1.0
                    }
                } else {
                    // First load - always set the image
                    loadedImage = cachedImage
                    imageOpacity = 1.0
                }
                return
            }
        }

        let result: Result<UIImage, ImageLoadError>

        // If we have recipe metadata, use the enhanced method with CloudKit fallback
        if let recipeId = recipeId {
            result = await recipeImageService.loadImage(forRecipeId: recipeId, localURL: imageURL, ownerId: ownerId)
        } else {
            // Fallback to simple URL loading
            result = await recipeImageService.loadImage(from: imageURL)
        }

        switch result {
        case .success(let image):
            // CRITICAL: Always set loadedImage if it's nil (initial load)
            if let currentImage = loadedImage {
                // Only update UI if the image actually changed
                if !areImagesEqual(image, currentImage) {
                    loadedImage = image
                    // Smooth fade-in animation (only for changed images)
                    withAnimation(.easeOut(duration: 0.3)) {
                        imageOpacity = 1.0
                    }
                }
            } else {
                // First load - always set the image with animation
                loadedImage = image
                withAnimation(.easeOut(duration: 0.3)) {
                    imageOpacity = 1.0
                }
            }

            // Always cache the loaded image
            if let recipeId = recipeId {
                let cacheKey = ImageCache.recipeImageKey(recipeId: recipeId)
                ImageCache.shared.set(cacheKey, image: image)
            }
        case .failure:
            // Keep showing placeholder
            break
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

    init(imageURL: URL?, recipeImageService: RecipeImageService, recipeId: UUID? = nil, ownerId: UUID? = nil) {
        self.imageURL = imageURL
        self.recipeImageService = recipeImageService
        self.recipeId = recipeId
        self.ownerId = ownerId

        // CRITICAL: Initialize with cached image if available
        // This prevents showing placeholder when navigating back
        if let recipeId = recipeId {
            let cacheKey = ImageCache.recipeImageKey(recipeId: recipeId)
            if let cachedImage = ImageCache.shared.get(cacheKey) {
                _loadedImage = State(initialValue: cachedImage)
                _imageOpacity = State(initialValue: 1.0)
            }
        }
    }

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: imageHeight(for: image))
                    .clipped()
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    .opacity(imageOpacity)
            } else {
                placeholderView
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .task {
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
        .frame(height: 280)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    private func imageHeight(for image: UIImage) -> CGFloat {
        let aspectRatio = image.size.width / image.size.height
        let estimatedWidth: CGFloat = 358 // Device width minus padding (390 - 32)

        // Calculate height based on aspect ratio
        let calculatedHeight = estimatedWidth / aspectRatio

        // Clamp between min and max values for better UX
        return min(max(calculatedHeight, 220), 380)
    }

    private func loadImage() async {
        // Strategy 0: Check in-memory cache first (fastest)
        if let recipeId = recipeId {
            let cacheKey = ImageCache.recipeImageKey(recipeId: recipeId)
            if let cachedImage = ImageCache.shared.get(cacheKey) {
                // CRITICAL: Always set loadedImage if it's nil (initial load)
                if let currentImage = loadedImage {
                    // Only update UI if the image actually changed
                    if !areImagesEqual(cachedImage, currentImage) {
                        loadedImage = cachedImage
                        imageOpacity = 1.0
                    }
                } else {
                    // First load - always set the image
                    loadedImage = cachedImage
                    imageOpacity = 1.0
                }
                return
            }
        }

        let result: Result<UIImage, ImageLoadError>

        // If we have recipe metadata, use the enhanced method with CloudKit fallback
        if let recipeId = recipeId {
            result = await recipeImageService.loadImage(forRecipeId: recipeId, localURL: imageURL, ownerId: ownerId)
        } else {
            // Fallback to simple URL loading
            result = await recipeImageService.loadImage(from: imageURL)
        }

        switch result {
        case .success(let image):
            // CRITICAL: Always set loadedImage if it's nil (initial load)
            if let currentImage = loadedImage {
                // Only update UI if the image actually changed
                if !areImagesEqual(image, currentImage) {
                    loadedImage = image
                    // Smooth fade-in animation (only for changed images)
                    withAnimation(.easeOut(duration: 0.3)) {
                        imageOpacity = 1.0
                    }
                }
            } else {
                // First load - always set the image with animation
                loadedImage = image
                withAnimation(.easeOut(duration: 0.3)) {
                    imageOpacity = 1.0
                }
            }

            // Always cache the loaded image
            if let recipeId = recipeId {
                let cacheKey = ImageCache.recipeImageKey(recipeId: recipeId)
                ImageCache.shared.set(cacheKey, image: image)
            }
        case .failure:
            // Keep showing placeholder
            break
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
