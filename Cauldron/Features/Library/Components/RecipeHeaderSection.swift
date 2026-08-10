//
//  RecipeHeaderSection.swift
//  Cauldron
//
//  Header section for recipe detail view with title, metadata, and controls
//

import SwiftUI

struct RecipeHeaderSection: View {
    let recipe: Recipe
    let scaledRecipe: Recipe
    let scaledResult: ScaledRecipe
    @Binding var localIsFavorite: Bool

    let hasOwnedCopy: Bool
    let isSavingRecipe: Bool
    let isCheckingDuplicates: Bool
    let hasUpdates: Bool
    let isUpdatingRecipe: Bool
    let isLoadingCreator: Bool

    let sharedBy: User?
    let recipeOwner: User?
    let originalCreator: User?
    let dependencies: DependencyContainer

    let onToggleFavorite: () -> Void
    let onSaveRecipe: () async -> Void
    let onUpdateRecipe: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Text(recipe.title.recipeDetailLineBreakFriendly())
                    .font(Theme.Typography.screenTitle)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                primaryHeaderAction
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs) {
                    if let time = recipe.displayTime {
                        metadataPill(systemImage: "clock", text: time.recipeDetailLineBreakFriendly())
                    }

                    metadataPill(systemImage: "person.2", text: scaledRecipe.yields.recipeDetailLineBreakFriendly())

                    sourcePill
                }
                .padding(.trailing, 1)
            }

            if !recipe.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(recipe.tags) { tag in
                            NavigationLink(destination: ExploreTagView(tag: tag, dependencies: dependencies)) {
                                TagView(tag)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 1)
                }
                .frame(height: 34)
            }

            // Updates Available Banner
            if hasUpdates {
                Button {
                    Task {
                        await onUpdateRecipe()
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title3)
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Update Available")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)

                            Text("The original recipe has been updated")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        if isUpdatingRecipe {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(Theme.Spacing.sm)
                    .appSurface(.resting)
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingRecipe)
                .accessibilityHint("Updates this saved copy from its original recipe")
            }

            // Scaling warnings
            if !scaledResult.warnings.isEmpty {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(scaledResult.warnings) { warning in
                        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                            Image(systemName: warning.icon)
                                .foregroundColor(warning.color)
                                .font(.caption)

                            Text(warning.message.recipeDetailLineBreakFriendly())
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Theme.Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(warning.color.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    }
                }
                .padding(.top, Theme.Spacing.xxs)
            }
        }
        .padding()
        .glassCard()
    }

    @ViewBuilder
    private var primaryHeaderAction: some View {
        if recipe.isOwnedByCurrentUser() {
            Button {
                // Haptic reflects the state we're moving to.
                if localIsFavorite { Haptics.light() } else { Haptics.success() }
                onToggleFavorite()
            } label: {
                Image(systemName: localIsFavorite ? "star.fill" : "star")
                    .font(.title3.weight(.semibold))
                    .frame(
                        minWidth: Theme.HitTarget.minimum,
                        minHeight: Theme.HitTarget.minimum
                    )
                    .foregroundStyle(localIsFavorite ? .yellow : .secondary)
                    .glassEffect(.regular, in: Circle())
                    .symbolEffect(.bounce, value: localIsFavorite)
            }
            .accessibilityLabel(localIsFavorite ? "Remove Favorite" : "Favorite")
        } else if hasOwnedCopy {
            Image(systemName: "checkmark")
                .font(.title3.weight(.semibold))
                .frame(
                    minWidth: Theme.HitTarget.minimum,
                    minHeight: Theme.HitTarget.minimum
                )
                .foregroundStyle(.green)
                .background(Color.green.opacity(0.12), in: Circle())
                .accessibilityLabel("Saved")
        } else {
            Button {
                Task {
                    await onSaveRecipe()
                }
            } label: {
                if isSavingRecipe || isCheckingDuplicates {
                    ProgressView()
                        .controlSize(.small)
                        .frame(
                            minWidth: Theme.HitTarget.minimum,
                            minHeight: Theme.HitTarget.minimum
                        )
                        .background(Color.cauldronOrange.opacity(0.12), in: Circle())
                } else {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(
                            minWidth: Theme.HitTarget.minimum,
                            minHeight: Theme.HitTarget.minimum
                        )
                        .foregroundStyle(Color.cauldronOrange)
                        .background(Color.cauldronOrange.opacity(0.12), in: Circle())
                }
            }
            .disabled(isSavingRecipe || isCheckingDuplicates)
            .accessibilityLabel("Save Recipe")
        }
    }

    @ViewBuilder
    private var sourcePill: some View {
        if let user = sharedBy {
            sourceNavigationPill(user: user, text: user.displayName)
        } else if let owner = recipeOwner, !recipe.isOwnedByCurrentUser() {
            let text = recipe.isFollowingSourceUpdates ? "Saved by \(owner.displayName)" : "Recipe by \(owner.displayName)"
            sourceNavigationPill(user: owner, text: text)
        } else if let creatorName = recipe.originalCreatorName {
            if let creator = originalCreator {
                sourceNavigationPill(user: creator, text: "Recipe by \(creatorName)")
            } else {
                metadataPill(systemImage: "person.circle.fill", text: "Recipe by \(creatorName)")
            }
        }
    }

    private func metadataPill(systemImage: String, text: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
                .foregroundColor(.cauldronOrange)
            Text(text)
                .lineLimit(1)
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .glassEffect(.regular, in: Capsule())
    }

    private func sourceNavigationPill(user: User, text: String) -> some View {
        NavigationLink {
            UserProfileView(user: user, dependencies: dependencies)
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                ProfileAvatar(user: user, size: 20, dependencies: dependencies)
                Text(text.recipeDetailLineBreakFriendly())
                    .lineLimit(1)

                if isLoadingCreator {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(Color(uiColor: .tertiaryLabel))
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .glassEffect(.regular, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
