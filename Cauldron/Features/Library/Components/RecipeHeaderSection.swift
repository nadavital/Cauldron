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
    @Binding var scaleFactor: Double
    @Binding var currentVisibility: RecipeVisibility
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
    let onChangeVisibility: (RecipeVisibility) async -> Void
    let onSaveRecipe: () async -> Void
    let onUpdateRecipe: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recipe.title)
                .font(.largeTitle.bold())
                .fontDesign(.serif)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                if let time = recipe.displayTime {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .foregroundColor(.cauldronOrange)
                        Text(time)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "person.2")
                        .foregroundColor(.cauldronOrange)
                    Text(scaledRecipe.yields)
                }

                Spacer()

                if recipe.isOwnedByCurrentUser() || hasOwnedCopy {
                    Button {
                        onToggleFavorite()
                    } label: {
                        Image(systemName: localIsFavorite ? "star.fill" : "star")
                            .foregroundStyle(localIsFavorite ? .yellow : .secondary)
                            .font(.title3)
                    }
                }
            }
            .foregroundColor(.secondary)

            if !recipe.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
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

            // Shared By Banner
            if let user = sharedBy {
                NavigationLink {
                    UserProfileView(user: user, dependencies: dependencies)
                } label: {
                    HStack {
                        ProfileAvatar(user: user, size: 32, dependencies: dependencies)

                        Text("Shared by \(user.displayName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(uiColor: .tertiaryLabel))

                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Owner Banner (if not shared and not owned)
            else if let owner = recipeOwner, !recipe.isOwnedByCurrentUser() {
                NavigationLink {
                    UserProfileView(user: owner, dependencies: dependencies)
                } label: {
                    HStack {
                        ProfileAvatar(user: owner, size: 32, dependencies: dependencies)

                        Text("Recipe by \(owner.displayName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(uiColor: .tertiaryLabel))

                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Attribution for saved recipes
            if let creatorName = recipe.originalCreatorName {
                Group {
                    if let creator = originalCreator {
                        NavigationLink {
                            UserProfileView(user: creator, dependencies: dependencies)
                        } label: {
                            attributionContent(creatorName: creatorName, showChevron: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        attributionContent(creatorName: creatorName, showChevron: false)
                    }
                }
            }

            // Updates Available Banner
            if hasUpdates {
                Button {
                    Task {
                        await onUpdateRecipe()
                    }
                } label: {
                    HStack(spacing: 12) {
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
                    .padding(12)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingRecipe)
            }

            // Settings Row (Visibility & Scale)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    // Visibility Picker (Only for owned recipes)
                    if recipe.isOwnedByCurrentUser() {
                        Menu {
                            Picker("Visibility", selection: Binding(
                                get: { currentVisibility },
                                set: { newValue in
                                    Task {
                                        await onChangeVisibility(newValue)
                                    }
                                }
                            )) {
                                ForEach([RecipeVisibility.publicRecipe, RecipeVisibility.privateRecipe], id: \.self) { visibility in
                                    Label(visibility.displayName, systemImage: visibility.icon)
                                        .tag(visibility)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: currentVisibility.icon)
                                Text(currentVisibility.displayName)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.cauldronOrange.opacity(0.15))
                            .foregroundColor(.cauldronOrange)
                            .clipShape(Capsule())
                        }
                    }

                    // Save Button (For non-owned recipes)
                    if !recipe.isOwnedByCurrentUser() {
                        Button {
                            Task {
                                await onSaveRecipe()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if isSavingRecipe {
                                    ProgressView()
                                        .tint(.cauldronOrange)
                                        .scaleEffect(0.7)
                                        .frame(width: 12, height: 12)
                                } else if hasOwnedCopy {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                } else {
                                    Image(systemName: "bookmark")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                }

                                Text(hasOwnedCopy ? "Saved" : "Save")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.cauldronOrange.opacity(0.15))
                            .foregroundColor(.cauldronOrange)
                            .clipShape(Capsule())
                        }
                        .disabled(isSavingRecipe || hasOwnedCopy || isCheckingDuplicates)
                    }

                    // Scale Picker
                    Menu {
                        Picker("Scale", selection: $scaleFactor) {
                            Text("½×").tag(0.5)
                            Text("1×").tag(1.0)
                            Text("2×").tag(2.0)
                            Text("3×").tag(3.0)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                            Text("\(scaleFactor.formatted())x")
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.cauldronOrange.opacity(0.15))
                        .foregroundColor(.cauldronOrange)
                        .clipShape(Capsule())
                    }
                }

                // Scaling warnings
                if !scaledResult.warnings.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(scaledResult.warnings) { warning in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: warning.icon)
                                    .foregroundColor(warning.color)
                                    .font(.caption)

                                Text(warning.message)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(warning.color.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .cardStyle()
    }

    @ViewBuilder
    private func attributionContent(creatorName: String, showChevron: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.title3)
                .foregroundColor(.cauldronOrange)

            VStack(alignment: .leading, spacing: 3) {
                Text("Recipe by \(creatorName)")
                    .font(.subheadline)
                    .foregroundColor(.primary)

                if let savedDate = recipe.savedAt {
                    Text("Saved \(savedDate.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isLoadingCreator {
                ProgressView()
                    .scaleEffect(0.8)
            } else if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.cauldronOrange.opacity(0.08))
        .cornerRadius(10)
    }
}
