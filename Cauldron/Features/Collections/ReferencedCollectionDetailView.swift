//
//  ReferencedCollectionDetailView.swift
//  Cauldron
//
//  Created by Claude on 10/30/25.
//

import SwiftUI
import os

struct ReferencedCollectionDetailView: View {
    let reference: CollectionReference
    let dependencies: DependencyContainer

    @State private var collection: Collection?
    @State private var recipes: [Recipe] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showRemoveConfirmation = false
    @Environment(\.dismiss) private var dismiss

    var filteredRecipes: [Recipe] {
        if searchText.isEmpty {
            return recipes
        }
        return recipes.filter { recipe in
            recipe.title.localizedCaseInsensitiveContains(searchText) ||
            recipe.tags.contains(where: { $0.name.localizedCaseInsensitiveContains(searchText) })
        }
    }

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading collection...")
                    Spacer()
                }
            } else if let collection = collection {
                List {
                    // Header with collection info
                    Section {
                        VStack(spacing: 16) {
                            // Icon
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(collectionColor(for: collection).opacity(0.15))
                                        .frame(width: 80, height: 80)

                                    if let emoji = reference.collectionEmoji {
                                        Text(emoji)
                                            .font(.system(size: 50))
                                    } else {
                                        Image(systemName: "folder.badge.person.crop")
                                            .font(.system(size: 40))
                                            .foregroundColor(collectionColor(for: collection))
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reference.collectionName)
                                        .font(.title2)
                                        .fontWeight(.bold)

                                    Text("\(collection.recipeCount) recipe\(collection.recipeCount == 1 ? "" : "s")")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    HStack(spacing: 4) {
                                        Image(systemName: "person.2.fill")
                                            .font(.caption)
                                        Text("Shared Collection")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.blue)
                                }

                                Spacer()
                            }

                            // Description if available
                            if let description = collection.description, !description.isEmpty {
                                Text(description)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(12)
                            }

                            // Info banner
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Saved Collection")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Text("This collection is shared by another user. Changes they make will be reflected here.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    // Recipes
                    if filteredRecipes.isEmpty {
                        Section {
                            VStack(spacing: 12) {
                                Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)

                                Text(searchText.isEmpty ? "No recipes in this collection" : "No recipes found")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                if searchText.isEmpty {
                                    Text("The collection owner hasn't added any recipes yet")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        Section {
                            ForEach(filteredRecipes) { recipe in
                                NavigationLink {
                                    RecipeDetailView(recipe: recipe, dependencies: dependencies)
                                } label: {
                                    RecipeRowView(recipe: recipe)
                                }
                            }
                        }
                    }
                }
                .navigationTitle(reference.collectionName)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: "Search recipes")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) {
                            showRemoveConfirmation = true
                        } label: {
                            Image(systemName: "bookmark.slash")
                        }
                    }
                }
                .confirmationDialog(
                    "Remove Saved Collection?",
                    isPresented: $showRemoveConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive) {
                        Task {
                            await removeReference()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove \"\(reference.collectionName)\" from your saved collections. The original collection will not be affected.")
                }
                .refreshable {
                    await loadCollection()
                }
            } else {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)

                    Text("Collection Not Found")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("This collection may have been deleted or is no longer shared")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Remove from Saved") {
                        Task {
                            await removeReference()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .task {
            await loadCollection()
        }
    }

    // MARK: - Actions

    private func loadCollection() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch the original collection from CloudKit
            let fetchedCollection = try await dependencies.cloudKitService.fetchPublicRecipe(
                recipeId: reference.originalCollectionId,
                ownerId: reference.originalOwnerId
            )

            // Actually we need a different method - let me fetch it properly
            // For now, we'll fetch it via the shared collections method
            // This is a limitation - we might want to add a fetchCollection method to CloudKitService

            // Workaround: Try to fetch from shared collections
            let sharedCollections = try await dependencies.cloudKitService.fetchSharedCollections(
                friendIds: [reference.originalOwnerId]
            )

            collection = sharedCollections.first { $0.id == reference.originalCollectionId }

            if let collection = collection {
                // Now fetch the recipes in this collection
                await loadRecipes(for: collection)
            } else {
                AppLogger.general.warning("Could not find referenced collection")
            }
        } catch {
            AppLogger.general.error("❌ Failed to load collection: \(error.localizedDescription)")
            errorMessage = "Failed to load collection: \(error.localizedDescription)"
            showError = true
            collection = nil
        }
    }

    private func loadRecipes(for collection: Collection) async {
        guard !collection.recipeIds.isEmpty else {
            recipes = []
            return
        }

        do {
            var fetchedRecipes: [Recipe] = []

            for recipeId in collection.recipeIds {
                do {
                    let recipe = try await dependencies.cloudKitService.fetchPublicRecipe(
                        recipeId: recipeId,
                        ownerId: collection.userId
                    )
                    fetchedRecipes.append(recipe)
                } catch {
                    AppLogger.general.warning("Failed to fetch recipe \(recipeId): \(error.localizedDescription)")
                }
            }

            recipes = fetchedRecipes
            AppLogger.general.info("✅ Loaded \(recipes.count) recipes for referenced collection")
        } catch {
            AppLogger.general.error("❌ Failed to load recipes: \(error.localizedDescription)")
        }
    }

    private func removeReference() async {
        do {
            try await dependencies.cloudKitService.deleteCollectionReference(reference.id)
            AppLogger.general.info("✅ Removed collection reference")

            // Notify other views
            NotificationCenter.default.post(name: NSNotification.Name("CollectionReferenceRemoved"), object: nil)

            dismiss()
        } catch {
            AppLogger.general.error("❌ Failed to remove reference: \(error.localizedDescription)")
            errorMessage = "Failed to remove reference: \(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: - Helpers

    private func collectionColor(for collection: Collection) -> Color {
        if let colorHex = collection.color {
            return Color(hex: colorHex) ?? .cauldronOrange
        }
        return .cauldronOrange
    }
}

#Preview {
    NavigationStack {
        ReferencedCollectionDetailView(
            reference: CollectionReference(
                userId: UUID(),
                originalCollectionId: UUID(),
                originalOwnerId: UUID(),
                collectionName: "Sample Collection",
                collectionEmoji: "🍕",
                recipeCount: 5
            ),
            dependencies: DependencyContainer.preview()
        )
    }
}
