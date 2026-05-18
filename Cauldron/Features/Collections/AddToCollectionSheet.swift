//
//  AddToCollectionSheet.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import SwiftUI
import os

struct AddToCollectionSheet: View {
    let recipe: Recipe
    let dependencies: DependencyContainer

    @Environment(\.dismiss) private var dismiss
    @State private var collections: [Collection] = []
    @State private var isLoading = false
    @State private var showingCreateSheet = false
    @State private var selectedCollectionIds = Set<UUID>()
    @State private var collectionMembershipRecipeIdsByCollectionId: [UUID: UUID] = [:]
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showingPublicMembershipRepairConfirmation = false
    @State private var pendingPublicMembershipRepairPlan = PublicCollectionMembershipRepairPlan(
        privateOwnedRecipeCount: 0,
        referencedRecipeCount: 0
    )

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading collections...")
                } else if collections.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(collections) { collection in
                            Button {
                                toggleCollection(collection)
                            } label: {
                                HStack {
                                    // Collection icon
                                    if let emoji = collection.emoji {
                                        Text(emoji)
                                            .font(.title3)
                                    } else {
                                        Image(systemName: "folder.fill")
                                            .foregroundColor(collectionColor(collection))
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(collection.name)
                                            .font(.body)
                                            .foregroundColor(.primary)

                                        Text("\(collection.recipeCount) recipe\(collection.recipeCount == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if selectedCollectionIds.contains(collection.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.cauldronOrange)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task {
                            await saveSelections()
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .sheet(isPresented: $showingCreateSheet, onDismiss: {
                // Reload collections after creating a new one
                Task {
                    await loadCollections()
                }
            }) {
                CollectionFormView()
                    .environment(\.dependencies, dependencies)
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .alert(
                "Make Recipes Public?",
                isPresented: $showingPublicMembershipRepairConfirmation
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Continue") {
                    Task {
                        await saveSelections(confirmingPublicMembershipRepair: true)
                    }
                }
            } message: {
                Text(pendingPublicMembershipRepairPlan.confirmationMessage)
            }
            .task {
                await loadCollections()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No Collections Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a collection to organize your recipes")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingCreateSheet = true
            } label: {
                Label("Create Collection", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cauldronOrange)
            .padding(.top, 8)
        }
        .padding()
    }

    // MARK: - Actions

    private func loadCollections() async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let currentUserId = CurrentUserSession.shared.userId else {
                collections = []
                selectedCollectionIds.removeAll()
                return
            }

            collections = try await dependencies.collectionRepository.fetchAll()
                .filter { $0.userId == currentUserId }

            // Pre-select collections that already contain this recipe
            selectedCollectionIds.removeAll()
            collectionMembershipRecipeIdsByCollectionId.removeAll()
            let membershipCandidateIds = try await membershipCandidateRecipeIds()
            for collection in collections {
                if let membershipRecipeId = collection.recipeIds.first(where: { membershipCandidateIds.contains($0) }) {
                    selectedCollectionIds.insert(collection.id)
                    collectionMembershipRecipeIdsByCollectionId[collection.id] = membershipRecipeId
                }
            }

            AppLogger.general.info("✅ Loaded \(collections.count) collections")
        } catch {
            AppLogger.general.error("❌ Failed to load collections: \(error.localizedDescription)")
            errorMessage = "Failed to load collections: \(error.localizedDescription)"
            showError = true
        }
    }

    private func toggleCollection(_ collection: Collection) {
        guard collection.userId == CurrentUserSession.shared.userId else { return }

        if selectedCollectionIds.contains(collection.id) {
            selectedCollectionIds.remove(collection.id)
        } else {
            selectedCollectionIds.insert(collection.id)
        }
    }

    private func saveSelections(confirmingPublicMembershipRepair: Bool = false) async {
        do {
            if !confirmingPublicMembershipRepair {
                let repairPlan = try await publicMembershipRepairPlanForPendingAdds()
                if repairPlan.requiresRepair {
                    pendingPublicMembershipRepairPlan = repairPlan
                    showingPublicMembershipRepairConfirmation = true
                    return
                }
            }

            for collection in collections {
                guard collection.userId == CurrentUserSession.shared.userId else {
                    continue
                }

                let shouldBeInCollection = selectedCollectionIds.contains(collection.id)
                let currentMembershipRecipeId = collectionMembershipRecipeIdsByCollectionId[collection.id]
                let isCurrentlyInCollection = currentMembershipRecipeId != nil

                if shouldBeInCollection && !isCurrentlyInCollection {
                    let recipeToAdd = try await recipeForCollectionMembership(collection)
                    let desiredRecipeIds = collection.recipeIds + [recipeToAdd.id]
                    let resolution = try await dependencies.publicCollectionMembershipResolver.resolveRecipeIdsForOwnedPublicCollection(
                        recipeIds: desiredRecipeIds,
                        ownerId: collection.userId,
                        visibility: collection.visibility
                    )
                    try await dependencies.collectionRepository.update(collection.updated(recipeIds: resolution.recipeIds))
                    AppLogger.general.info("✅ Added recipe to collection: \(collection.name)")
                } else if !shouldBeInCollection && isCurrentlyInCollection {
                    // Remove recipe from collection
                    try await dependencies.collectionRepository.removeRecipe(currentMembershipRecipeId ?? recipe.id, from: collection.id)
                    AppLogger.general.info("✅ Removed recipe from collection: \(collection.name)")
                }
            }

            dismiss()
        } catch {
            AppLogger.general.error("❌ Failed to save collection changes: \(error.localizedDescription)")
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
            showError = true
        }
    }

    private func publicMembershipRepairPlanForPendingAdds() async throws -> PublicCollectionMembershipRepairPlan {
        var privateOwnedRecipeCount = 0
        var referencedRecipeCount = 0

        for collection in collections {
            guard collection.userId == CurrentUserSession.shared.userId,
                  collection.visibility == .publicRecipe,
                  selectedCollectionIds.contains(collection.id),
                  collectionMembershipRecipeIdsByCollectionId[collection.id] == nil else {
                continue
            }

            let recipeIsOwnedByCollectionOwner = recipe.ownerId == collection.userId && !recipe.isPreview
            let desiredRecipeIds = recipeIsOwnedByCollectionOwner
                ? collection.recipeIds + [recipe.id]
                : collection.recipeIds
            let repairPlan = try await dependencies.publicCollectionMembershipResolver.repairPlan(
                recipeIds: desiredRecipeIds,
                ownerId: collection.userId,
                visibility: collection.visibility
            )
            privateOwnedRecipeCount += repairPlan.privateOwnedRecipeCount
            referencedRecipeCount += repairPlan.referencedRecipeCount

            if !recipeIsOwnedByCollectionOwner {
                referencedRecipeCount += 1
            }
        }

        return PublicCollectionMembershipRepairPlan(
            privateOwnedRecipeCount: privateOwnedRecipeCount,
            referencedRecipeCount: referencedRecipeCount
        )
    }

    private func recipeForCollectionMembership(_ collection: Collection) async throws -> Recipe {
        guard recipe.ownerId != collection.userId || recipe.isPreview else {
            return recipe
        }

        return try await dependencies.recipeSaveService.materializeRecipeForOwnedCollectionMembership(
            recipe,
            minimumVisibility: collection.visibility,
            originalCreatorId: recipe.originalCreatorId ?? recipe.ownerId,
            originalCreatorName: recipe.originalCreatorName
        )
    }

    private func membershipCandidateRecipeIds() async throws -> Set<UUID> {
        let sourceRecipeId = recipe.relatedGraphReferenceID
        let ownedCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [sourceRecipeId]
        )

        return Set([recipe.id, sourceRecipeId] + ownedCopies.map(\.id))
    }

    // MARK: - Helpers

    private func collectionColor(_ collection: Collection) -> Color {
        if let colorHex = collection.color {
            return Color(hex: colorHex) ?? .cauldronOrange
        }
        return .cauldronOrange
    }
}

#Preview {
    AddToCollectionSheet(
        recipe: Recipe(
            id: UUID(),
            title: "Test Recipe",
            ingredients: [],
            steps: [],
            yields: "4 servings",
            tags: [],
            isFavorite: false,
            visibility: .privateRecipe,
            createdAt: Date(),
            updatedAt: Date()
        ),
        dependencies: DependencyContainer.preview()
    )
}
