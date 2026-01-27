//
//  SocialRecipeCard.swift
//  Cauldron
//
//  Reusable card component for displaying recipes with creator attribution
//  Used in "From Friends" section, "Popular in Cauldron", and FriendsTabView
//

import SwiftUI

/// Card view for displaying a recipe with creator attribution and tier badge
/// Used across Friends tab and Cook tab social sections
struct SocialRecipeCard: View {
    let recipe: Recipe
    let creator: User
    let creatorTier: UserTier?
    let sharedAt: Date?
    let dependencies: DependencyContainer
    @ObservedObject private var currentUserSession = CurrentUserSession.shared

    /// Initialize with a SharedRecipe
    init(sharedRecipe: SharedRecipe, creatorTier: UserTier? = nil, dependencies: DependencyContainer) {
        self.recipe = sharedRecipe.recipe
        self.creator = sharedRecipe.sharedBy
        self.creatorTier = creatorTier
        self.sharedAt = sharedRecipe.sharedAt
        self.dependencies = dependencies
    }

    /// Initialize with individual components (for popular recipes)
    init(recipe: Recipe, creator: User, creatorTier: UserTier? = nil, dependencies: DependencyContainer) {
        self.recipe = recipe
        self.creator = creator
        self.creatorTier = creatorTier
        self.sharedAt = nil
        self.dependencies = dependencies
    }

    /// Returns the current user from session if creator is the current user, otherwise the passed creator
    /// This ensures profile changes propagate immediately throughout the app
    private var displayCreator: User {
        if let currentUser = currentUserSession.currentUser, currentUser.id == creator.id {
            return currentUser
        }
        return creator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image with creator overlay (top left) and tier badge (top right)
            ZStack {
                RecipeImageView(recipe: recipe, recipeImageService: dependencies.recipeImageService)
                    .frame(width: 240, height: 160)

                // Top overlays
                VStack {
                    HStack(alignment: .top) {
                        // Creator info overlay (top left)
                        HStack(spacing: 6) {
                            ProfileAvatar(user: displayCreator, size: 24, dependencies: dependencies)

                            Text(displayCreator.displayName)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())

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
            .frame(width: 240, height: 160)

            // Title
            Text(recipe.title)
                .font(.headline)
                .lineLimit(1)
                .frame(width: 240, height: 20, alignment: .leading)

            // Metadata row - time and tag (like regular recipe cards)
            HStack(spacing: 4) {
                // Time
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
                } else {
                    Text(" ")
                        .font(.caption2)
                        .frame(width: 60)
                }
            }
            .frame(width: 240, height: 20)
        }
        .frame(width: 240)
    }
}

/// Compact card variation for grid layouts
struct SocialRecipeCardCompact: View {
    let recipe: Recipe
    let creator: User
    let creatorTier: UserTier?
    let dependencies: DependencyContainer

    init(sharedRecipe: SharedRecipe, creatorTier: UserTier? = nil, dependencies: DependencyContainer) {
        self.recipe = sharedRecipe.recipe
        self.creator = sharedRecipe.sharedBy
        self.creatorTier = creatorTier
        self.dependencies = dependencies
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Image with creator badge (bottom left) and tier (top right)
            ZStack {
                RecipeImageView(recipe: recipe, recipeImageService: dependencies.recipeImageService)
                    .frame(width: 160, height: 120)

                VStack {
                    // Tier badge (top right)
                    HStack {
                        Spacer()
                        if let tier = creatorTier, tier != .apprentice {
                            Image(systemName: tier.icon)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(tier.color)
                                .padding(5)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                    }
                    .padding(6)

                    Spacer()

                    // Creator avatar (bottom left)
                    HStack {
                        ProfileAvatar(user: creator, size: 20, dependencies: dependencies)
                            .background(Circle().fill(.ultraThinMaterial).padding(-2))
                        Spacer()
                    }
                    .padding(6)
                }
            }
            .frame(width: 160, height: 120)

            // Title
            Text(recipe.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)

            // Time
            if let time = recipe.displayTime {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(time)
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
        }
        .frame(width: 160)
    }
}

#Preview {
    VStack {
        SocialRecipeCard(
            recipe: Recipe(title: "Chocolate Cake", ingredients: [], steps: []),
            creator: User(username: "chef_julia", displayName: "Julia Child"),
            creatorTier: .potionMaker,
            dependencies: .preview()
        )
    }
    .padding()
}
