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

    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    @State private var imageOpacity: Double = 0

    init(
        imageURL: URL?,
        size: ImageSize = .card,
        showPlaceholderText: Bool = false
    ) {
        self.imageURL = imageURL
        self.size = size
        self.showPlaceholderText = showPlaceholderText
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
        isLoading = true

        let result = await RecipeImageService.shared.loadImage(from: imageURL)

        switch result {
        case .success(let image):
            loadedImage = image
            // Smooth fade-in animation
            withAnimation(.easeOut(duration: 0.3)) {
                imageOpacity = 1.0
            }
        case .failure:
            // Keep showing placeholder
            break
        }

        isLoading = false
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
    init(heroImageURL: URL?) {
        self.init(imageURL: heroImageURL, size: .hero, showPlaceholderText: false)
    }

    /// Create a card-sized image view
    init(cardImageURL: URL?) {
        self.init(imageURL: cardImageURL, size: .card, showPlaceholderText: false)
    }

    /// Create a thumbnail-sized image view
    init(thumbnailImageURL: URL?) {
        self.init(imageURL: thumbnailImageURL, size: .thumbnail, showPlaceholderText: false)
    }

    /// Create a preview-sized image view
    init(previewImageURL: URL?, showPlaceholderText: Bool = true) {
        self.init(imageURL: previewImageURL, size: .preview, showPlaceholderText: showPlaceholderText)
    }
}

// MARK: - Hero Recipe Image View

/// Hero image view with dynamic height and gradient overlay
struct HeroRecipeImageView: View {
    let imageURL: URL?

    @State private var loadedImage: UIImage?
    @State private var imageOpacity: Double = 0

    var body: some View {
        Group {
            if let image = loadedImage {
                ZStack(alignment: .bottom) {
                    GeometryReader { geo in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                    .opacity(imageOpacity)

                    // Gradient overlay for text readability
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.black.opacity(0.4)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(height: imageHeight(for: image))
            } else {
                placeholderView
            }
        }
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

            Image(systemName: "fork.knife")
                .font(.system(size: 48))
                .foregroundStyle(Color.cauldronOrange.opacity(0.3))
        }
        .frame(height: 300)
    }

    private func imageHeight(for image: UIImage) -> CGFloat {
        let aspectRatio = image.size.width / image.size.height
        let estimatedWidth: CGFloat = 390 // Approximate device width

        // Calculate height based on aspect ratio
        let calculatedHeight = estimatedWidth / aspectRatio

        // Clamp between min and max values for better UX
        return min(max(calculatedHeight, 250), 450)
    }

    private func loadImage() async {
        let result = await RecipeImageService.shared.loadImage(from: imageURL)

        switch result {
        case .success(let image):
            loadedImage = image
            // Smooth fade-in animation
            withAnimation(.easeOut(duration: 0.3)) {
                imageOpacity = 1.0
            }
        case .failure:
            // Keep showing placeholder
            break
        }
    }
}

// MARK: - Preview

#Preview("Card") {
    VStack(spacing: 20) {
        RecipeImageView(cardImageURL: nil)
        RecipeImageView(thumbnailImageURL: nil)
    }
    .padding()
}
