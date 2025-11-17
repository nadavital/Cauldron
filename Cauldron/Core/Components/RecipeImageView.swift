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

    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    @State private var imageOpacity: Double = 0

    init(
        imageURL: URL?,
        size: ImageSize = .card,
        showPlaceholderText: Bool = false,
        recipeImageService: RecipeImageService
    ) {
        self.imageURL = imageURL
        self.size = size
        self.showPlaceholderText = showPlaceholderText
        self.recipeImageService = recipeImageService
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

        let result = await recipeImageService.loadImage(from: imageURL)

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
    init(heroImageURL: URL?, recipeImageService: RecipeImageService) {
        self.init(imageURL: heroImageURL, size: .hero, showPlaceholderText: false, recipeImageService: recipeImageService)
    }

    /// Create a card-sized image view
    init(cardImageURL: URL?, recipeImageService: RecipeImageService) {
        self.init(imageURL: cardImageURL, size: .card, showPlaceholderText: false, recipeImageService: recipeImageService)
    }

    /// Create a thumbnail-sized image view
    init(thumbnailImageURL: URL?, recipeImageService: RecipeImageService) {
        self.init(imageURL: thumbnailImageURL, size: .thumbnail, showPlaceholderText: false, recipeImageService: recipeImageService)
    }

    /// Create a preview-sized image view
    init(previewImageURL: URL?, showPlaceholderText: Bool = true, recipeImageService: RecipeImageService) {
        self.init(imageURL: previewImageURL, size: .preview, showPlaceholderText: showPlaceholderText, recipeImageService: recipeImageService)
    }
}

// MARK: - Hero Recipe Image View

/// Hero image view with card style and padding
struct HeroRecipeImageView: View {
    let imageURL: URL?
    let recipeImageService: RecipeImageService

    @State private var loadedImage: UIImage?
    @State private var imageOpacity: Double = 0

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
        let result = await recipeImageService.loadImage(from: imageURL)

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
    let dependencies = try! DependencyContainer.preview()
    return VStack(spacing: 20) {
        RecipeImageView(cardImageURL: nil, recipeImageService: dependencies.recipeImageService)
        RecipeImageView(thumbnailImageURL: nil, recipeImageService: dependencies.recipeImageService)
    }
    .padding()
}
