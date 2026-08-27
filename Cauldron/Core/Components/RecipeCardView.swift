//
//  RecipeCardView.swift
//  Cauldron
//
//  Unified card component for displaying recipes in horizontal scrolls.
//  Handles both user's own recipes and shared recipes from others.
//

import SwiftUI

/// Unified card view for displaying recipes in horizontal scroll sections.
///
/// This component adapts its appearance based on context:
/// - **Own recipes**: Shows favorite star (if favorited), no creator overlay
/// - **Shared recipes**: Shows creator avatar/name overlay on image with optional tier badge
///
/// Usage:
/// ```swift
/// // For user's own recipes
/// RecipeCardView(recipe: recipe, dependencies: deps)
///
/// // For shared recipes (shows creator overlay)
/// RecipeCardView(recipe: recipe, dependencies: deps, sharedBy: user, creatorTier: tier)
///
/// // With SharedRecipe convenience init
/// RecipeCardView(sharedRecipe: sharedRecipe, creatorTier: tier, dependencies: deps)
/// ```
struct RecipeCardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let recipe: Recipe
    let dependencies: DependencyContainer
    var sharedBy: User?
    var creatorTier: UserTier?
    var onTagTap: ((Tag) -> Void)?

    // MARK: - Initializers

    /// Standard initializer for user's own recipes
    init(recipe: Recipe, dependencies: DependencyContainer, onTagTap: ((Tag) -> Void)? = nil) {
        self.recipe = recipe
        self.dependencies = dependencies
        self.sharedBy = nil
        self.creatorTier = nil
        self.onTagTap = onTagTap
    }

    /// Initializer for shared recipes with creator info
    init(recipe: Recipe, dependencies: DependencyContainer, sharedBy: User, creatorTier: UserTier? = nil, onTagTap: ((Tag) -> Void)? = nil) {
        self.recipe = recipe
        self.dependencies = dependencies
        self.sharedBy = sharedBy
        self.creatorTier = creatorTier
        self.onTagTap = onTagTap
    }

    /// Convenience initializer for SharedRecipe
    init(sharedRecipe: SharedRecipe, creatorTier: UserTier? = nil, dependencies: DependencyContainer, onTagTap: ((Tag) -> Void)? = nil) {
        self.recipe = sharedRecipe.recipe
        self.dependencies = dependencies
        self.sharedBy = sharedRecipe.sharedBy
        self.creatorTier = creatorTier
        self.onTagTap = onTagTap
    }

    /// Whether this is a shared recipe (from someone else)
    private var isSharedRecipe: Bool {
        sharedBy != nil
    }

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    private var cardWidth: CGFloat { RecipeCardMetrics.width(isRegularWidth: isRegularWidth) }

    private var cardHeight: CGFloat { RecipeCardMetrics.imageHeight(isRegularWidth: isRegularWidth) }

    private var metadataTagMaxWidth: CGFloat {
        RecipeCardMetrics.metadataTagMaxWidth(isRegularWidth: isRegularWidth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // Image with contextual overlays
            ZStack {
                RecipeImageView(recipe: recipe, recipeImageService: dependencies.recipeImageService)
                .frame(width: cardWidth, height: cardHeight)

                if isSharedRecipe {
                    // Shared recipe: show creator overlay
                    sharedRecipeOverlay
                } else {
                    // Own recipe: show favorite star if applicable
                    ownRecipeOverlay
                }
            }
            .frame(width: cardWidth, height: cardHeight)

            // Keep every card aligned while giving longer recipe names room.
            Text(recipe.title)
                .font(Theme.Typography.cardTitle)
                .lineLimit(2, reservesSpace: true)
                .frame(width: cardWidth, height: 40, alignment: .topLeading)

            // Metadata row - time and tag
            metadataRow
        }
        .frame(width: cardWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    /// Composed VoiceOver description: title, optional creator, time, favorite.
    private var accessibilityLabel: String {
        var parts: [String] = [recipe.title]
        if let creator = sharedBy {
            parts.append("shared by \(creator.displayName)")
        }
        if let time = recipe.displayTime {
            parts.append(time)
        }
        if let tier = creatorTier, tier != .apprentice {
            parts.append("\(tier.displayName) tier")
        }
        if !isSharedRecipe, recipe.isFavorite {
            parts.append("favorite")
        }
        if let firstTag = recipe.tags.first {
            parts.append(firstTag.name)
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Overlay Views

    /// Overlay for shared recipes - shows creator info and tier badge
    private var sharedRecipeOverlay: some View {
        GlassEffectContainer(spacing: 2) {
            VStack {
                HStack(alignment: .top) {
                    // Creator info (top left)
                    if let creator = sharedBy {
                        HStack(spacing: 6) {
                            ProfileAvatar(user: creator, size: 24, dependencies: dependencies)

                            Text("@\(creator.username)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: Capsule())
                    }

                    Spacer()

                    // Tier badge (top right)
                    if let tier = creatorTier, tier != .apprentice {
                        Image(systemName: tier.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(tier.color)
                            .padding(6)
                            .glassEffect(.regular, in: Circle())
                    }
                }
                .padding(8)

                Spacer()
            }
        }
    }

    /// Overlay for own recipes - shows favorite star
    private var ownRecipeOverlay: some View {
        GlassEffectContainer(spacing: 2) {
            VStack {
                HStack {
                    Spacer()

                    // Favorite indicator (top-right)
                    if recipe.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .glassEffect(.clear, in: Circle())
                            .padding(8)
                    }
                }

                Spacer()
            }
        }
    }

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: 4) {
            // Time - always reserve space
            if let time = recipe.displayTime {
                Label(time, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(" ")
                    .font(.caption)
                    .frame(width: 60)
            }

            Spacer()

            // Tag
            if let firstTag = recipe.tags.first {
                TagView(firstTag)
                    .scaleEffect(0.9)
                    .frame(maxWidth: metadataTagMaxWidth, alignment: .trailing)
                    .onTapGesture {
                        onTagTap?(firstTag)
                    }
            } else {
                Text(" ")
                    .font(.caption2)
                    .frame(width: 60)
            }
        }
        .frame(width: cardWidth, height: 20)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Own recipe
        RecipeCardView(
            recipe: Recipe(title: "My Chocolate Cake", ingredients: [], steps: [], isFavorite: true),
            dependencies: .preview()
        )

        // Shared recipe
        RecipeCardView(
            recipe: Recipe(title: "Julia's Beef Bourguignon", ingredients: [], steps: []),
            dependencies: .preview(),
            sharedBy: User(username: "chef_julia", displayName: "Julia Child"),
            creatorTier: .potionMaker
        )
    }
    .padding()
}
