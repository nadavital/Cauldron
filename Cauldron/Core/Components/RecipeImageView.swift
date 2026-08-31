//
//  RecipeImageView.swift
//  Cauldron
//
//  Created by Claude Code on 10/28/25.
//

import SwiftUI
import CoreImage

/// Shared CoreImage context for cheap luminance sampling (creating one per call
/// is expensive).
private enum RecipeLuminance {
    static let context = CIContext(options: [.workingColorSpace: NSNull()])
}

extension UIImage {
    /// Average perceived luminance (0 = dark, 1 = light) of the image's top
    /// region — where overlay chips sit — so callers can pick legible
    /// white/black foreground colors. Returns nil if it can't be sampled.
    func topRegionLuminance() -> Double? {
        guard let cg = cgImage else { return nil }
        let ciImage = CIImage(cgImage: cg)
        let extent = ciImage.extent
        guard extent.height > 0 else { return nil }
        // Top 35% (CIImage origin is bottom-left, so the top is the high-y band).
        let topExtent = CGRect(
            x: extent.minX,
            y: extent.maxY - extent.height * 0.35,
            width: extent.width,
            height: extent.height * 0.35
        )
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: topExtent)
        ]), let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        RecipeLuminance.context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}

private enum RecipeImageLoadingPipeline {
    struct Outcome {
        let result: Result<UIImage, ImageLoadError>
        let shouldAnimateAppearance: Bool
    }

    static func initialCachedImage(
        recipeId: UUID?,
        variant: String,
        targetPixelSizes: [CGFloat?],
        fallbackVariants: [(variant: String, targetPixelSizes: [CGFloat?])] = [],
        cacheIdentity: String? = nil
    ) -> UIImage? {
        guard let recipeId = recipeId else { return nil }
        for candidate in [(variant, targetPixelSizes)] + fallbackVariants {
            for targetPixelSize in candidate.targetPixelSizes + [nil] {
                let cacheVariant = RecipeImageCacheKeyPolicy.variant(
                    baseVariant: candidate.variant,
                    hasExplicitVariant: true,
                    targetPixelSize: targetPixelSize,
                    cacheIdentity: cacheIdentity
                )
                let cacheKey = ImageCache.recipeImageKey(recipeId: recipeId, variant: cacheVariant)
                if let image = ImageCache.shared.get(cacheKey),
                   cachedImageSatisfiesRequest(image, targetPixelSize: targetPixelSize) {
                    return image
                }
            }
        }
        return nil
    }

    static func loadImage(
        with service: RecipeImageService,
        recipeId: UUID?,
        imageURL: URL?,
        ownerId: UUID?,
        targetPixelSize: CGFloat?,
        cacheVariant: String,
        privateRecordName: String? = nil,
        cacheIdentity: String? = nil,
        forceRefresh: Bool = false
    ) async -> Outcome {
        if let recipeId = recipeId {
            let versionedVariant = RecipeImageCacheKeyPolicy.variant(
                baseVariant: cacheVariant,
                hasExplicitVariant: true,
                targetPixelSize: targetPixelSize,
                cacheIdentity: cacheIdentity
            )
            let cacheKey = ImageCache.recipeImageKey(recipeId: recipeId, variant: versionedVariant)
            if !forceRefresh, let cachedImage = await ImageCache.shared.load(cacheKey) {
                if cachedImageSatisfiesRequest(cachedImage, targetPixelSize: targetPixelSize) {
                    return Outcome(result: .success(cachedImage), shouldAnimateAppearance: false)
                }
                ImageCache.shared.remove(cacheKey)
            }

            let result = await service.loadImage(
                forRecipeId: recipeId,
                localURL: imageURL,
                ownerId: ownerId,
                targetPixelSize: targetPixelSize,
                cacheVariant: cacheVariant,
                privateRecordName: privateRecordName,
                cacheIdentity: cacheIdentity,
                forceRefresh: forceRefresh
            )
            return Outcome(result: result, shouldAnimateAppearance: true)
        }
        return Outcome(result: await service.loadImage(
            from: imageURL,
            targetPixelSize: targetPixelSize,
            cacheIdentity: cacheIdentity,
            forceRefresh: forceRefresh
        ), shouldAnimateAppearance: true)
    }

    private static func cachedImageSatisfiesRequest(
        _ image: UIImage,
        targetPixelSize: CGFloat?
    ) -> Bool {
        guard let targetPixelSize, targetPixelSize > 0 else { return true }
        let pixelWidth = image.cgImage.map { CGFloat($0.width) } ?? image.size.width * image.scale
        let pixelHeight = image.cgImage.map { CGFloat($0.height) } ?? image.size.height * image.scale
        let longestEdge = max(pixelWidth, pixelHeight)
        return longestEdge <= 0 || longestEdge + 1 >= targetPixelSize
    }

    static func applyLoadedImage(
        _ image: UIImage,
        loadedImage: inout UIImage?,
        imageOpacity: inout Double,
        shouldAnimateAppearance: Bool
    ) {
        if let currentImage = loadedImage {
            // The load task is already keyed by recipe, URL, and cache variant.
            // Avoid a full pixel-buffer comparison on the main actor here.
            if image !== currentImage {
                loadedImage = image
                imageOpacity = 1.0
            }
        } else {
            loadedImage = image
            if shouldAnimateAppearance {
                withAnimation(.easeOut(duration: 0.2)) {
                    imageOpacity = 1.0
                }
            } else {
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
    /// Optional CloudKit private record name (for legacy recipes whose record
    /// name differs from their UUID). Enables the private-database image fallback.
    let privateRecordName: String?
    let imageCacheIdentity: String?
    /// Optional: reports the loaded image's average luminance (0 = dark, 1 =
    /// light) so overlays can pick legible (white/black) foreground colors.
    var onLuminance: ((Double) -> Void)? = nil

    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: UIImage?
    @State private var imageOpacity: Double = 0
    @State private var imageReloadGeneration = 0
    @State private var forceRefreshNextLoad = false

    private var cacheVariant: String {
        size.cacheVariant
    }

    private var targetPixelSize: CGFloat? {
        size.targetPixelSize(displayScale: displayScale)
    }

    private var loadTaskKey: String {
        let recipeKey = recipeId?.uuidString ?? "no-recipe"
        let imageKey = imageURL?.absoluteString ?? "no-image"
        return "\(recipeKey)|\(imageKey)|\(cacheVariant)|\(imageCacheIdentity ?? "unversioned")|\(imageReloadGeneration)"
    }

    init(
        imageURL: URL?,
        size: ImageSize = .card,
        showPlaceholderText: Bool = false,
        recipeImageService: RecipeImageService,
        recipeId: UUID? = nil,
        ownerId: UUID? = nil,
        privateRecordName: String? = nil,
        imageCacheIdentity: String? = nil,
        onLuminance: ((Double) -> Void)? = nil
    ) {
        self.imageURL = imageURL
        self.size = size
        self.showPlaceholderText = showPlaceholderText
        self.recipeImageService = recipeImageService
        self.recipeId = recipeId
        self.ownerId = ownerId
        self.privateRecordName = privateRecordName
        self.imageCacheIdentity = imageCacheIdentity
        self.onLuminance = onLuminance

        // Initialize with cache to avoid placeholder flicker on back-navigation.
        if let cachedImage = RecipeImageLoadingPipeline.initialCachedImage(
            recipeId: recipeId,
            variant: cacheVariant,
            targetPixelSizes: size.initialTargetPixelSizes,
            fallbackVariants: [
                ("card", ImageSize.card.initialTargetPixelSizes),
                ("thumbnail", ImageSize.thumbnail.initialTargetPixelSizes),
            ],
            cacheIdentity: imageCacheIdentity
        ) {
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
        .task(id: loadTaskKey) {
            await loadImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recipeImageUpdated)) { notification in
            guard notification.object as? UUID == recipeId else { return }
            forceRefreshNextLoad = true
            imageReloadGeneration &+= 1
        }
    }

    private var placeholderView: some View {
        RecipeImagePlaceholder(iconSize: size.iconSize, showText: showPlaceholderText)
    }

    private func loadImage() async {
        let forceRefresh = forceRefreshNextLoad
        let result = await RecipeImageLoadingPipeline.loadImage(
            with: recipeImageService,
            recipeId: recipeId,
            imageURL: imageURL,
            ownerId: ownerId,
            targetPixelSize: targetPixelSize,
            cacheVariant: cacheVariant,
            privateRecordName: privateRecordName,
            cacheIdentity: imageCacheIdentity,
            forceRefresh: forceRefresh
        )
        guard !Task.isCancelled else { return }
        if forceRefresh {
            forceRefreshNextLoad = false
        }
        switch result.result {
        case .success(let image):
            RecipeImageLoadingPipeline.applyLoadedImage(
                image,
                loadedImage: &loadedImage,
                imageOpacity: &imageOpacity,
                shouldAnimateAppearance: result.shouldAnimateAppearance
            )
            if let onLuminance, let luminance = image.topRegionLuminance() {
                onLuminance(luminance)
            }
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
        case collectionTile
        case thumbnail
        case preview

        var width: CGFloat? {
            switch self {
            case .hero: return nil // Full width
            case .card: return 240
            case .collectionTile: return nil
            case .thumbnail: return 70
            case .preview: return nil // Dynamic
            }
        }

        var height: CGFloat? {
            switch self {
            case .hero: return nil // Dynamic based on aspect ratio
            case .card: return 160
            case .collectionTile: return nil
            case .thumbnail: return 70
            case .preview: return nil // Dynamic
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .hero: return 0 // Edge-to-edge, no corners
            case .collectionTile: return 0
            case .card, .preview: return 16
            case .thumbnail: return 12
            }
        }

        var shadowOpacity: Double {
            switch self {
            case .hero: return 0 // No shadow for full-bleed
            case .collectionTile: return 0
            case .card, .preview: return 0.1 // Medium shadow
            case .thumbnail: return 0.05 // Subtle shadow
            }
        }

        var shadowRadius: CGFloat {
            switch self {
            case .hero, .collectionTile: return 0
            case .card, .preview: return 8
            case .thumbnail: return 4
            }
        }

        var shadowY: CGFloat {
            switch self {
            case .hero, .collectionTile: return 0
            case .card, .preview: return 4
            case .thumbnail: return 2
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .hero, .preview: return 48
            case .card: return 32
            case .collectionTile: return 28
            case .thumbnail: return 20
            }
        }

        var cacheVariant: String {
            switch self {
            case .hero: return "hero"
            case .card: return "card"
            case .collectionTile: return "collectionTile"
            case .thumbnail: return "thumbnail"
            case .preview: return "preview"
            }
        }

        func targetPixelSize(displayScale: CGFloat) -> CGFloat? {
            switch self {
            case .hero:
                return 900 * displayScale
            case .card:
                return max(width ?? 0, height ?? 0) * displayScale
            case .collectionTile:
                return 500 * displayScale
            case .thumbnail:
                return max(width ?? 0, height ?? 0) * displayScale
            case .preview:
                return 900
            }
        }

        /// Initializers cannot read SwiftUI's environment display scale. Probe
        /// the finite set of cache keys the live view can generate, largest
        /// first, and let the task use the exact environment-backed key later.
        var initialTargetPixelSizes: [CGFloat?] {
            [3.0, 2.0, 1.0].map(targetPixelSize(displayScale:))
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
    init(recipe: Recipe, recipeImageService: RecipeImageService, onLuminance: ((Double) -> Void)? = nil) {
        self.init(imageURL: recipe.imageURL, size: .card, showPlaceholderText: false, recipeImageService: recipeImageService, recipeId: recipe.id, ownerId: recipe.ownerId, privateRecordName: recipe.cloudRecordName, imageCacheIdentity: recipe.imageModifiedAt.map(Self.cacheIdentity), onLuminance: onLuminance)
    }

    /// Create a thumbnail-sized image view from a Recipe object (with CloudKit fallback)
    init(thumbnailForRecipe recipe: Recipe, recipeImageService: RecipeImageService) {
        self.init(imageURL: recipe.imageURL, size: .thumbnail, showPlaceholderText: false, recipeImageService: recipeImageService, recipeId: recipe.id, ownerId: recipe.ownerId, privateRecordName: recipe.cloudRecordName, imageCacheIdentity: recipe.imageModifiedAt.map(Self.cacheIdentity))
    }

    nonisolated static func cacheIdentity(for date: Date) -> String {
        String(date.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
    }
}

extension HeroRecipeImageView {
    /// Create from a Recipe object (with CloudKit fallback)
    init(recipe: Recipe, recipeImageService: RecipeImageService, reloadToken: UUID? = nil) {
        self.init(imageURL: recipe.imageURL, recipeImageService: recipeImageService, recipeId: recipe.id, ownerId: recipe.ownerId, privateRecordName: recipe.cloudRecordName, imageCacheIdentity: recipe.imageModifiedAt.map { String($0.timeIntervalSinceReferenceDate.bitPattern, radix: 16) }, reloadToken: reloadToken)
    }
}

// MARK: - Hero Recipe Image View

/// Hero image view with card style and padding
struct HeroRecipeImageView: View {
    let imageURL: URL?
    let recipeImageService: RecipeImageService
    let recipeId: UUID?
    let ownerId: UUID?
    /// Optional CloudKit private record name (for legacy recipes whose record
    /// name differs from their UUID). Enables the private-database image fallback.
    let privateRecordName: String?
    let imageCacheIdentity: String?
    let reloadToken: UUID?

    @Environment(\.displayScale) private var displayScale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var loadedImage: UIImage?
    @State private var imageOpacity: Double = 0
    @State private var containerWidth: CGFloat = 0
    @State private var imageReloadGeneration = 0
    @State private var forceRefreshNextLoad = false

    private let cacheVariant = "hero"
    private var heroHeight: CGFloat {
        horizontalSizeClass == .regular ? 460 : 380
    }

    private var loadTaskKey: String {
        let recipeKey = recipeId?.uuidString ?? "no-recipe"
        let imageKey = imageURL?.absoluteString ?? "no-image"
        let pixelKey = Int(targetPixelSize.rounded(.up))
        return "\(recipeKey)|\(imageKey)|\(pixelKey)|\(imageCacheIdentity ?? "unversioned")|\(reloadToken?.uuidString ?? "no-reload")|\(imageReloadGeneration)"
    }
    private var targetPixelSize: CGFloat {
        max(containerWidth, 500) * displayScale
    }

    init(imageURL: URL?, recipeImageService: RecipeImageService, recipeId: UUID? = nil, ownerId: UUID? = nil, privateRecordName: String? = nil, imageCacheIdentity: String? = nil, reloadToken: UUID? = nil) {
        self.imageURL = imageURL
        self.recipeImageService = recipeImageService
        self.recipeId = recipeId
        self.ownerId = ownerId
        self.privateRecordName = privateRecordName
        self.imageCacheIdentity = imageCacheIdentity
        self.reloadToken = reloadToken

        // A card image is already visible at the moment this view is pushed.
        // Reuse it immediately, then replace it with the hero-sized decode in
        // place. This prevents the placeholder flash between the matched card
        // transition and the detail image.
        if let cachedImage = RecipeImageLoadingPipeline.initialCachedImage(
            recipeId: recipeId,
            variant: cacheVariant,
            targetPixelSizes: [1_500, 1_000, 500],
            fallbackVariants: [
                ("card", RecipeImageView.ImageSize.card.initialTargetPixelSizes),
                ("thumbnail", RecipeImageView.ImageSize.thumbnail.initialTargetPixelSizes),
            ],
            cacheIdentity: imageCacheIdentity
        ) {
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
                    .frame(height: heroHeight)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        // Bottom gradient for smooth transition to content
                        LinearGradient(
                            colors: [
                                Color.appBackground.opacity(0),
                                Color.appBackground.opacity(0.5),
                                Color.appBackground
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
        .frame(height: heroHeight)
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
        .task(id: loadTaskKey) {
            await loadImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recipeImageUpdated)) { notification in
            guard notification.object as? UUID == recipeId else { return }
            forceRefreshNextLoad = true
            imageReloadGeneration &+= 1
        }
    }

    private var placeholderView: some View {
        RecipeImagePlaceholder(iconSize: 64, showText: false)
            .frame(height: heroHeight)
            .frame(maxWidth: .infinity)
    }

    private func loadImage() async {
        let forceRefresh = forceRefreshNextLoad
        let result = await RecipeImageLoadingPipeline.loadImage(
            with: recipeImageService,
            recipeId: recipeId,
            imageURL: imageURL,
            ownerId: ownerId,
            targetPixelSize: targetPixelSize,
            cacheVariant: cacheVariant,
            privateRecordName: privateRecordName,
            cacheIdentity: imageCacheIdentity,
            forceRefresh: forceRefresh
        )
        guard !Task.isCancelled else { return }
        if forceRefresh {
            forceRefreshNextLoad = false
        }
        switch result.result {
        case .success(let image):
            RecipeImageLoadingPipeline.applyLoadedImage(
                image,
                loadedImage: &loadedImage,
                imageOpacity: &imageOpacity,
                shouldAnimateAppearance: result.shouldAnimateAppearance
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
    let dependencies = DependencyContainer.preview()
    return VStack(spacing: 20) {
        RecipeImageView(cardImageURL: nil, recipeImageService: dependencies.recipeImageService)
        RecipeImageView(thumbnailImageURL: nil, recipeImageService: dependencies.recipeImageService)
    }
    .padding()
}
