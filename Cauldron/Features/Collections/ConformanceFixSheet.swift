//
//  ConformanceFixSheet.swift
//  Cauldron
//
//  Extracted from CollectionDetailView.swift to keep views focused.
//

import SwiftUI
import os

struct ConformanceFixSheet: View {
    let collection: Collection
    let nonConformingRecipes: [Recipe]
    let dependencies: DependencyContainer
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRecipeIds: Set<UUID> = []
    @State private var isUpdating = false
    @State private var errorMessage: String?
    @State private var showError = false

    var targetVisibility: RecipeVisibility {
        collection.visibility
    }

    // Separate owned recipes from references
    var ownedRecipes: [Recipe] {
        nonConformingRecipes.filter { recipe in
            guard let currentUserId = CurrentUserSession.shared.userId,
                  let ownerId = recipe.ownerId else {
                return false
            }
            return ownerId == currentUserId
        }
    }

    var referencedRecipes: [Recipe] {
        nonConformingRecipes.filter { recipe in
            guard let currentUserId = CurrentUserSession.shared.userId,
                  let ownerId = recipe.ownerId else {
                return false
            }
            return ownerId != currentUserId
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header explanation
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.cauldronOrange)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Visibility Issue")
                                .font(.title3)
                                .fontWeight(.bold)

                            Text("This \(collection.visibility.displayName.lowercased()) collection contains recipes that won't be visible to others")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.cauldronOrange.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding()

                // Select All button (above the list)
                if !ownedRecipes.isEmpty {
                    HStack {
                        Button {
                            if selectedRecipeIds.count == ownedRecipes.count {
                                selectedRecipeIds.removeAll()
                            } else {
                                selectedRecipeIds = Set(ownedRecipes.map(\.id))
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selectedRecipeIds.count == ownedRecipes.count ? "checkmark.square.fill" : "square")
                                    .foregroundColor(.cauldronOrange)
                                Text(selectedRecipeIds.count == ownedRecipes.count ? "Deselect All" : "Select All")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        Spacer()

                        Text("\(selectedRecipeIds.count) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                // ScrollView with recipes
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Owned recipes section
                        if !ownedRecipes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("YOUR RECIPES")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                    .padding(.top, 8)

                                Text("Select recipes to update to \(targetVisibility.displayName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                    .padding(.bottom, 8)

                                ForEach(ownedRecipes) { recipe in
                                    Button {
                                        toggleRecipe(recipe.id)
                                    } label: {
                                        recipeRow(recipe: recipe, selectable: true, dependencies: dependencies)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Referenced recipes section (non-selectable)
                        if !referencedRecipes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("REFERENCED RECIPES")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                    .padding(.top, 16)

                                Text("These are saved from others. You can't change their visibility.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                    .padding(.bottom, 8)

                                ForEach(referencedRecipes) { recipe in
                                    recipeRow(recipe: recipe, selectable: false, dependencies: dependencies)
                                }
                            }
                        }
                    }
                }

                // Update button (bottom)
                VStack(spacing: 12) {
                    Button {
                        Task {
                            await updateSelectedRecipes()
                        }
                    } label: {
                        HStack {
                            if isUpdating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isUpdating ? "Updating..." : "Update \(selectedRecipeIds.count) Recipe\(selectedRecipeIds.count == 1 ? "" : "s")")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedRecipeIds.isEmpty ? Color.gray : Color.cauldronOrange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(selectedRecipeIds.isEmpty || isUpdating)
                }
                .padding()
                .background(Color.appBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 8, y: -4)
            }
            .navigationTitle("Recipe Visibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(isUpdating)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }

    @ViewBuilder
    private func recipeRow(recipe: Recipe, selectable: Bool, dependencies: DependencyContainer) -> some View {
        HStack(spacing: 12) {
            RecipeImageView(thumbnailForRecipe: recipe, recipeImageService: dependencies.recipeImageService)
                .overlay(
                    Group {
                        if !selectable {
                            // Reference badge
                            Image(systemName: "bookmark.fill")
                                .font(.caption)
                                .foregroundStyle(Color(red: 0.5, green: 0.0, blue: 0.0))
                                .padding(6)
                                .glassEffect(.regular, in: Circle())
                                .padding(6)
                        }
                    },
                    alignment: .topLeading
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Image(systemName: recipe.visibility.icon)
                        .font(.caption)
                    Text(recipe.visibility.displayName)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            if selectable {
                if selectedRecipeIds.contains(recipe.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.cauldronOrange)
                        .font(.title3)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color.appBackground)
        .overlay(
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func toggleRecipe(_ recipeId: UUID) {
        if selectedRecipeIds.contains(recipeId) {
            selectedRecipeIds.remove(recipeId)
        } else {
            selectedRecipeIds.insert(recipeId)
        }
    }

    private func updateSelectedRecipes() async {
        isUpdating = true
        defer { isUpdating = false }

        var successCount = 0
        var failureCount = 0

        for recipeId in selectedRecipeIds {
            guard let recipe = nonConformingRecipes.first(where: { $0.id == recipeId }) else {
                continue
            }

            do {
                // Create updated recipe with new visibility
                let updatedRecipe = Recipe(
                    id: recipe.id,
                    title: recipe.title,
                    ingredients: recipe.ingredients,
                    steps: recipe.steps,
                    yields: recipe.yields,
                    totalMinutes: recipe.totalMinutes,
                    tags: recipe.tags,
                    nutrition: recipe.nutrition,
                    sourceURL: recipe.sourceURL,
                    sourceTitle: recipe.sourceTitle,
                    notes: recipe.notes,
                    imageURL: recipe.imageURL,
                    isFavorite: recipe.isFavorite,
                    visibility: targetVisibility,
                    ownerId: recipe.ownerId,
                    cloudRecordName: recipe.cloudRecordName,
                    cloudImageRecordName: recipe.cloudImageRecordName,
                    imageModifiedAt: recipe.imageModifiedAt,
                    createdAt: recipe.createdAt,
                    updatedAt: Date(),
                    originalRecipeId: recipe.originalRecipeId,
                    originalCreatorId: recipe.originalCreatorId,
                    originalCreatorName: recipe.originalCreatorName,
                    savedAt: recipe.savedAt,
                    sourceRecipeUpdatedAt: recipe.sourceRecipeUpdatedAt,
                    followsSourceUpdates: recipe.followsSourceUpdates,
                    relatedRecipeIds: recipe.relatedRecipeIds,
                    isPreview: recipe.isPreview
                )

                try await dependencies.recipeRepository.update(updatedRecipe)
                successCount += 1
                AppLogger.general.info("✅ Updated recipe visibility: \(recipe.title)")
            } catch {
                failureCount += 1
                AppLogger.general.error("❌ Failed to update recipe visibility: \(error.localizedDescription)")
            }
        }

        if failureCount > 0 {
            errorMessage = "Updated \(successCount) recipes, but \(failureCount) failed"
            showError = true
        } else {
            AppLogger.general.info("✅ Successfully updated \(successCount) recipe visibilities")
            dismiss()
            onDismiss()
        }
    }
}
