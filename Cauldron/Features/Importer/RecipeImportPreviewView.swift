//
//  RecipeImportPreviewView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/4/25.
//

import SwiftUI
import os

/// Preview and edit imported recipe before saving
struct RecipeImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let importedRecipe: Recipe
    let dependencies: DependencyContainer
    let sourceInfo: String
    let destinationRecipeID: UUID?
    let onSave: () async -> Bool

    @State private var editedRecipe: Recipe
    @State private var isSaving = false
    @State private var showSuccess = false
    @State private var showingEditSheet = false

    init(
        importedRecipe: Recipe,
        dependencies: DependencyContainer,
        sourceInfo: String,
        destinationRecipeID: UUID? = nil,
        onSave: @escaping () async -> Bool = { true }
    ) {
        self.importedRecipe = importedRecipe
        self.dependencies = dependencies
        self.sourceInfo = sourceInfo
        self.destinationRecipeID = destinationRecipeID
        self.onSave = onSave
        self._editedRecipe = State(initialValue: importedRecipe)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                RecipeReviewPresentation(
                    recipe: editedRecipe,
                    dependencies: dependencies,
                    sourceDescription: sourceInfo
                )
            }
            .appPageChrome()
            .navigationTitle("Preview Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Edit", systemImage: "pencil") {
                        showingEditSheet = true
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        // Prevent race condition by setting isSaving immediately
                        guard !isSaving else { return }
                        isSaving = true

                        Task {
                            await saveRecipe()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                RecipeEditorView(
                    dependencies: dependencies,
                    recipe: destinationRecipeID.map {
                        ImportedRecipeSaveBuilder.recipeForSave(
                            from: editedRecipe,
                            userId: CurrentUserSession.shared.userId,
                            destinationID: $0
                        )
                    } ?? editedRecipe,
                    onSaveAndDismiss: {
                        // When editor saves during import, dismiss the entire import flow
                        Task { @MainActor in
                            if await onSave() {
                                dismiss()
                            } else {
                                isSaving = false
                            }
                        }
                    },
                    isImporting: true
                )
                .appSheetSizing(.large)
            }
            .alert("Recipe Saved!", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your recipe has been saved to your library.")
            }
        }
    }

    private func saveRecipe() async {
        // Note: isSaving is set in the button action to prevent race condition
        // It will be reset on error, and on success the view will dismiss

        do {
            guard let userId = CurrentUserSession.shared.userId else {
                AppLogger.parsing.error("Cannot save imported recipe without a current user")
                isSaving = false
                return
            }

            let recipeToSave = ImportedRecipeSaveBuilder.recipeForSave(
                from: editedRecipe,
                userId: userId,
                destinationID: destinationRecipeID
            )

            // A durable import always reuses the job UUID. If the app was
            // terminated after create but before completing the inbox entry,
            // relaunch converges on the existing recipe instead of duplicating it.
            if let destinationRecipeID,
                let existing = try await dependencies.recipeRepository.fetch(id: destinationRecipeID),
                existing.ownerId == userId
            {
                guard await onSave() else {
                    isSaving = false
                    return
                }
                dismiss()
                return
            }
            try await dependencies.recipeRepository.create(recipeToSave)
            Task {
                guard
                    let stagedImage = await ImportedRecipeSaveBuilder.stageRemoteImage(
                        for: recipeToSave,
                        imageManager: dependencies.imageManager
                    ), stagedImage.expectedModificationDate == nil
                else { return }
                guard CurrentUserSession.shared.userId == userId else { return }
                guard
                    let savedImage = try? await dependencies.imageManager.saveDownloadedImageDataWithToken(
                        stagedImage.data,
                        recipeId: recipeToSave.id,
                        expectedModificationDate: stagedImage.expectedModificationDate
                    )
                else { return }
                let localizedImageURL = await dependencies.imageManager.imageURL(for: savedImage.filename)
                let promotedModificationDate = savedImage.modificationDate
                guard CurrentUserSession.shared.userId == userId else {
                    await dependencies.imageManager.deleteImageIfUnchanged(
                        recipeId: recipeToSave.id,
                        modificationDate: promotedModificationDate
                    )
                    return
                }
                do {
                    let promoted = try await dependencies.recipeRepository.promoteImportedImageIfCurrent(
                        recipeId: recipeToSave.id,
                        ownerId: userId,
                        expectedUpdatedAt: recipeToSave.updatedAt,
                        expectedImageURL: recipeToSave.imageURL,
                        localizedImageURL: localizedImageURL
                    )
                    guard promoted else {
                        await dependencies.imageManager.deleteImageIfUnchanged(
                            recipeId: recipeToSave.id,
                            modificationDate: promotedModificationDate
                        )
                        return
                    }
                } catch {
                    await dependencies.imageManager.deleteImageIfUnchanged(
                        recipeId: recipeToSave.id,
                        modificationDate: promotedModificationDate
                    )
                }
            }
            AppLogger.parsing.info("Successfully saved imported recipe: \(recipeToSave.title)")
            NotificationCenter.default.post(name: .recipeAdded, object: recipeToSave.id)

            Haptics.success()

            // Call the callback to notify parent view
            guard await onSave() else {
                isSaving = false
                return
            }

            // Dismiss this view
            dismiss()

        } catch {
            AppLogger.parsing.error("Failed to save recipe: \(error.localizedDescription)")
            isSaving = false
        }
    }

}

#Preview {
    RecipeImportPreviewView(
        importedRecipe: Recipe(
            title: "Chocolate Chip Cookies",
            ingredients: [
                Ingredient(name: "flour", quantity: Quantity(value: 2, unit: .cup)),
                Ingredient(name: "sugar", quantity: Quantity(value: 1, unit: .cup)),
            ],
            steps: [
                CookStep(index: 0, text: "Mix ingredients"),
                CookStep(index: 1, text: "Bake at 350°F for 12 minutes"),
            ]
        ),
        dependencies: .preview(),
        sourceInfo: "Imported from allrecipes.com"
    )
}
