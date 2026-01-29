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
    let recipe: Recipe
    let dependencies: DependencyContainer
    var sharedBy: User?
    var creatorTier: UserTier?
    var onTagTap: ((Tag) -> Void)?

    @ObservedObject private var currentUserSession = CurrentUserSession.shared

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

    /// Returns the current user from session if creator is the current user, otherwise the passed creator
    /// This ensures profile changes propagate immediately throughout the app
    private var displayCreator: User? {
        guard let sharedBy = sharedBy else { return nil }
        if let currentUser = currentUserSession.currentUser, currentUser.id == sharedBy.id {
            return currentUser
        }
        return sharedBy
    }

    /// Whether this is a shared recipe (from someone else)
    private var isSharedRecipe: Bool {
        sharedBy != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image with contextual overlays
            ZStack {
                RecipeImageView(recipe: recipe, recipeImageService: dependencies.recipeImageService)
                    .frame(width: 240, height: 160)

                if isSharedRecipe {
                    // Shared recipe: show creator overlay
                    sharedRecipeOverlay
                } else {
                    // Own recipe: show favorite star if applicable
                    ownRecipeOverlay
                }
            }
            .frame(width: 240, height: 160)

            // Title - single line for clean look
            Text(recipe.title)
                .font(.headline)
                .lineLimit(1)
                .frame(width: 240, height: 20, alignment: .leading)

            // Metadata row - time and tag
            metadataRow
        }
        .frame(width: 240)
    }

    // MARK: - Overlay Views

    /// Overlay for shared recipes - shows creator info and tier badge
    private var sharedRecipeOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                // Creator info (top left)
                if let creator = displayCreator {
                    HStack(spacing: 6) {
                        ProfileAvatar(user: creator, size: 24, dependencies: dependencies)

                        Text(creator.displayName)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                }

                Spacer()

                // Tier badge (top right)
                if let tier = creatorTier, tier != .apprentice {
                    Image(systemName: tier.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(tier.color)
                        .padding(6)
                        .background(Circle().fill(.ultraThinMaterial))
                }
            }
            .padding(8)

            Spacer()
        }
    }

    /// Overlay for own recipes - shows favorite star
    private var ownRecipeOverlay: some View {
        VStack {
            HStack {
                Spacer()

                // Favorite indicator (top-right)
                if recipe.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(6)
                        .background(Circle().fill(.ultraThinMaterial))
                        .padding(8)
                }
            }

            Spacer()
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
                    .frame(maxWidth: 100, alignment: .trailing)
                    .onTapGesture {
                        onTagTap?(firstTag)
                    }
            } else {
                Text(" ")
                    .font(.caption2)
                    .frame(width: 60)
            }
        }
        .frame(width: 240, height: 20)
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
