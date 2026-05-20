//
//  RecipeDetailView+Actions.swift
//  Cauldron
//
//  Action methods for RecipeDetailView
//

import SwiftUI

extension RecipeDetailView {

    func loadRelatedRecipes() async {
        if recipe.relatedRecipeIds.isEmpty {
            self.relatedRecipes = []
            return
        }

        do {
            let localResolution = try await dependencies.recipeRepository.resolveLocalRelatedRecipes(
                referenceIds: recipe.relatedRecipeIds,
                includePreviews: true,
                preferredOwnerId: CurrentUserSession.shared.userId
            )
            var loadedRecipes = localResolution.recipes
            let missingIds = localResolution.missingIds

            if !missingIds.isEmpty {
                AppLogger.general.info("📥 Fetching \(missingIds.count) missing related recipes from CloudKit")

                do {
                    let fetchedRecipesById = try await dependencies.recipeDiscoveryCache.fetchPublicRecipes(ids: missingIds)
                    for missingId in missingIds {
                        if let fetchedRecipe = fetchedRecipesById[missingId] {
                            let previewRecipe = Recipe(
                                id: fetchedRecipe.id,
                                title: fetchedRecipe.title,
                                ingredients: fetchedRecipe.ingredients,
                                steps: fetchedRecipe.steps,
                                yields: fetchedRecipe.yields,
                                totalMinutes: fetchedRecipe.totalMinutes,
                                tags: fetchedRecipe.tags,
                                nutrition: fetchedRecipe.nutrition,
                                sourceURL: fetchedRecipe.sourceURL,
                                sourceTitle: fetchedRecipe.sourceTitle,
                                notes: fetchedRecipe.notes,
                                imageURL: nil,
                                isFavorite: false,
                                visibility: fetchedRecipe.visibility,
                                ownerId: fetchedRecipe.ownerId,
                                cloudRecordName: fetchedRecipe.cloudRecordName,
                                cloudImageRecordName: fetchedRecipe.cloudImageRecordName,
                                imageModifiedAt: fetchedRecipe.imageModifiedAt,
                                createdAt: fetchedRecipe.createdAt,
                                updatedAt: fetchedRecipe.updatedAt,
                                originalRecipeId: fetchedRecipe.originalRecipeId,
                                originalCreatorId: fetchedRecipe.originalCreatorId,
                                originalCreatorName: fetchedRecipe.originalCreatorName,
                                savedAt: fetchedRecipe.savedAt,
                                sourceRecipeUpdatedAt: fetchedRecipe.sourceRecipeUpdatedAt,
                                followsSourceUpdates: fetchedRecipe.followsSourceUpdates,
                                relatedRecipeIds: fetchedRecipe.relatedRecipeIds,
                                isPreview: true
                            )

                            do {
                                try await self.dependencies.recipeRepository.create(previewRecipe, skipCloudSync: true)
                                AppLogger.general.info("📝 Saved related recipe as preview: \(fetchedRecipe.title)")

                                if fetchedRecipe.cloudImageRecordName != nil {
                                    do {
                                        if let filename = try await self.dependencies.imageManager.downloadImageFromCloud(
                                            recipeId: previewRecipe.id,
                                            fromPublic: true
                                        ) {
                                            let imageURL = await self.dependencies.imageManager.imageURL(for: filename)
                                            let updatedPreview = previewRecipe.withImageState(
                                                imageURL: imageURL,
                                                cloudImageRecordName: previewRecipe.cloudImageRecordName,
                                                imageModifiedAt: previewRecipe.imageModifiedAt
                                            )
                                            try await self.dependencies.recipeRepository.update(
                                                updatedPreview,
                                                shouldUpdateTimestamp: false,
                                                skipImageSync: true,
                                                skipCloudSync: true
                                            )
                                            AppLogger.general.info("✅ Downloaded image for preview recipe: \(fetchedRecipe.title)")
                                            loadedRecipes.append(updatedPreview)
                                        } else {
                                            loadedRecipes.append(previewRecipe)
                                        }
                                    } catch {
                                        AppLogger.general.warning("Failed to download image for preview recipe: \(error.localizedDescription)")
                                        loadedRecipes.append(previewRecipe)
                                    }
                                } else {
                                    loadedRecipes.append(previewRecipe)
                                }
                            } catch {
                                AppLogger.general.warning("Failed to save preview recipe: \(error.localizedDescription)")
                                loadedRecipes.append(fetchedRecipe)
                            }
                        }
                    }
                } catch {
                    AppLogger.general.warning("Failed to batch fetch related recipes: \(error.localizedDescription)")
                }

                AppLogger.general.info("✅ Loaded \(loadedRecipes.count) total related recipes")
            }

            self.relatedRecipes = loadedRecipes
        } catch {
            AppLogger.general.error("Failed to load related recipes: \(error.localizedDescription)")
        }
    }

    func handleCookButtonTap() {
        if dependencies.cookModeCoordinator.isActive,
           let currentRecipe = dependencies.cookModeCoordinator.currentRecipe,
           currentRecipe.id != recipe.id {
            dependencies.cookModeCoordinator.pendingRecipe = recipe
            showSessionConflictAlert = true
        } else {
            Task {
                await dependencies.cookModeCoordinator.startCooking(recipe)
            }
        }
    }

    func addToGroceryList() async {
        do {
            let items: [(name: String, quantity: Quantity?)] = scaledRecipe.ingredients.map {
                ($0.name, $0.quantity)
            }

            try await dependencies.groceryRepository.addItemsFromRecipe(
                recipeID: recipe.id.uuidString,
                recipeName: recipe.title,
                items: items
            )

            AppLogger.general.info("Added \(items.count) ingredients to grocery list from '\(recipe.title)'")

            withAnimation {
                showingToast = true
            }
        } catch {
            AppLogger.general.error("Failed to add ingredients to grocery list: \(error.localizedDescription)")
        }
    }

    func toggleFavorite() {
        Task {
            do {
                try await dependencies.recipeRepository.toggleFavorite(id: recipe.id)
                localIsFavorite.toggle()
            } catch {
                AppLogger.general.error("Failed to toggle favorite: \(error.localizedDescription)")
            }
        }
    }

    func generateShareLink() async {
        isGeneratingShareLink = true

        do {
            let link = try await dependencies.externalShareService.shareRecipe(recipe)
            shareLink = link
            showShareSheet = true
        } catch {
            errorMessage = "Failed to generate share link: \(error.localizedDescription)"
            showErrorAlert = true
            AppLogger.general.error("Failed to generate share link: \(error.localizedDescription)")
        }

        isGeneratingShareLink = false
    }

    func refreshRecipe() async {
        do {
            if let updatedRecipe = try await dependencies.recipeRepository.fetch(id: recipe.id) {
                recipe = updatedRecipe
                localIsFavorite = updatedRecipe.isFavorite
                currentVisibility = updatedRecipe.visibility
                imageRefreshID = UUID()

                AppLogger.general.info("✅ Refreshed recipe: \(updatedRecipe.title)")
                await loadRelatedRecipes()
            }
        } catch {
            AppLogger.general.error("Failed to refresh recipe: \(error.localizedDescription)")
        }
    }

    func refreshPublicRecipeIfNeeded() async {
        guard RecipeDetailDisplayPolicy.shouldRefreshPublicRecipeOnOpen(
            recipe,
            currentUserId: CurrentUserSession.shared.userId
        ) else {
            return
        }

        do {
            guard let refreshedRecipe = try await dependencies.recipeDiscoveryCache.fetchPublicRecipe(
                id: recipe.id,
                forceRefresh: true
            ) else {
                return
            }

            recipe = refreshedRecipe
            currentVisibility = refreshedRecipe.visibility
            imageRefreshID = UUID()
            AppLogger.general.info("✅ Refreshed public recipe before preview save: \(refreshedRecipe.title)")
        } catch {
            AppLogger.general.warning("Failed to refresh public recipe: \(error.localizedDescription)")
        }
    }

    func deleteRecipe() async {
        do {
            try await dependencies.recipeRepository.delete(id: recipe.id)
            AppLogger.general.info("Deleted recipe: \(recipe.title)")
            recipeWasDeleted = true
        } catch {
            AppLogger.general.error("Failed to delete recipe: \(error.localizedDescription)")
        }
    }

    func loadRecipeOwner(_ ownerId: UUID) async {
        isLoadingOwner = true
        defer { isLoadingOwner = false }

        do {
            recipeOwner = try await dependencies.userCloudService.fetchUser(byUserId: ownerId)
            AppLogger.general.info("Loaded recipe owner: \(recipeOwner?.displayName ?? "unknown")")
        } catch {
            AppLogger.general.warning("Failed to load recipe owner: \(error.localizedDescription)")
        }
    }

    func loadOriginalCreator(_ creatorId: UUID) async {
        isLoadingCreator = true
        defer { isLoadingCreator = false }

        do {
            originalCreator = try await dependencies.userCloudService.fetchUser(byUserId: creatorId)
            AppLogger.general.info("Loaded original creator: \(originalCreator?.displayName ?? "unknown")")
        } catch {
            AppLogger.general.warning("Failed to load original creator: \(error.localizedDescription)")
        }
    }

    func saveRecipeToLibrary() async {
        guard let userId = CurrentUserSession.shared.userId else {
            AppLogger.general.error("Cannot save recipe - no current user")
            return
        }

        if recipe.ownerId == userId {
            AppLogger.general.info("Skipping save - recipe already belongs to current user: \(recipe.title)")
            hasOwnedCopy = true
            return
        }

        do {
            let missingRelatedRecipes = try await dependencies.recipeSaveService.missingRelatedRecipesForSave(recipe)
            if !missingRelatedRecipes.isEmpty {
                relatedRecipesToSave = missingRelatedRecipes
                showSaveRelatedRecipesPrompt = true
                return
            }
        } catch {
            AppLogger.general.warning("Failed to check for related recipes: \(error.localizedDescription)")
        }

        await performSaveRecipe(saveRelatedRecipes: false)
    }

    func performSaveRecipe(saveRelatedRecipes: Bool) async {
        guard let userId = CurrentUserSession.shared.userId else {
            AppLogger.general.error("Cannot save recipe - no current user")
            return
        }

        if recipe.ownerId == userId {
            AppLogger.general.info("Skipping save - recipe already belongs to current user: \(recipe.title)")
            hasOwnedCopy = true
            return
        }

        isSavingRecipe = true
        defer { isSavingRecipe = false }

        do {
            let result = try await dependencies.recipeSaveService.saveRecipeToLibrary(
                recipe,
                originalCreatorId: recipe.ownerId,
                originalCreatorName: recipeOwner?.displayName,
                relatedRecipesToSave: saveRelatedRecipes ? relatedRecipesToSave : []
            )

            withAnimation {
                recipe = result.recipe
                currentVisibility = result.recipe.visibility
                localIsFavorite = result.recipe.isFavorite
                hasOwnedCopy = true
                showSaveSuccessToast = !result.reusedExistingCopy
                imageRefreshID = UUID()
            }

            relatedRecipesToSave = []
        } catch {
            AppLogger.general.error("❌ Failed to save recipe: \(error.localizedDescription)")
            errorMessage = "Failed to save recipe: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    func saveAsPreviewIfNeeded() async {
        // Safety check: Don't create preview for recipes owned by current user
        // This prevents race conditions where isOwnedByCurrentUser() returns false
        // for a recipe that was just created (before ownerId is properly set on the view's recipe object)
        if let currentUserId = CurrentUserSession.shared.userId,
           let recipeOwnerId = recipe.ownerId,
           currentUserId == recipeOwnerId {
            AppLogger.general.debug("Skipping preview save - recipe belongs to current user: \(recipe.title)")
            return
        }

        do {
            if let existingRecipe = try await dependencies.recipeRepository.fetch(id: recipe.id) {
                // Recipe already exists locally - don't create a duplicate
                // Only download image if this is a preview recipe (not user's own recipe)
                if existingRecipe.isPreview {
                    let refreshedPreview = Recipe(
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
                        imageURL: existingRecipe.imageURL,
                        isFavorite: existingRecipe.isFavorite,
                        visibility: recipe.visibility,
                        ownerId: recipe.ownerId,
                        cloudRecordName: recipe.cloudRecordName,
                        cloudImageRecordName: recipe.cloudImageRecordName,
                        imageModifiedAt: recipe.imageModifiedAt,
                        createdAt: recipe.createdAt,
                        updatedAt: recipe.updatedAt,
                        originalRecipeId: recipe.originalRecipeId,
                        originalCreatorId: recipe.originalCreatorId,
                        originalCreatorName: recipe.originalCreatorName,
                        savedAt: recipe.savedAt,
                        sourceRecipeUpdatedAt: recipe.sourceRecipeUpdatedAt,
                        followsSourceUpdates: recipe.followsSourceUpdates,
                        relatedRecipeIds: recipe.relatedRecipeIds,
                        isPreview: true
                    )

                    try await dependencies.recipeRepository.update(
                        refreshedPreview,
                        shouldUpdateTimestamp: false,
                        skipImageSync: true,
                        skipCloudSync: true
                    )
                    self.recipe = refreshedPreview
                    AppLogger.general.info("🔄 Refreshed existing preview recipe: \(recipe.title)")

                    if refreshedPreview.imageURL == nil && recipe.cloudImageRecordName != nil {
                        AppLogger.general.info("📥 Downloading image for existing preview recipe: \(recipe.title)")
                        if let filename = try await dependencies.imageManager.downloadImageFromCloud(
                            recipeId: recipe.id,
                            fromPublic: true
                        ) {
                            let imageURL = await dependencies.imageManager.imageURL(for: filename)
                            let updatedRecipe = refreshedPreview.withImageState(
                                imageURL: imageURL,
                                cloudImageRecordName: refreshedPreview.cloudImageRecordName,
                                imageModifiedAt: refreshedPreview.imageModifiedAt
                            )
                            try await dependencies.recipeRepository.update(
                                updatedRecipe,
                                shouldUpdateTimestamp: false,
                                skipImageSync: true,
                                skipCloudSync: true
                            )
                            AppLogger.general.info("✅ Updated preview with image: \(recipe.title)")

                            self.recipe = updatedRecipe
                            imageRefreshID = UUID()
                        }
                    } else if refreshedPreview.imageURL != existingRecipe.imageURL ||
                                refreshedPreview.cloudImageRecordName != existingRecipe.cloudImageRecordName ||
                                refreshedPreview.imageModifiedAt != existingRecipe.imageModifiedAt {
                        imageRefreshID = UUID()
                    }
                }

                return
            }

            let previewRecipe = Recipe(
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
                imageURL: nil,
                isFavorite: false,
                visibility: recipe.visibility,
                ownerId: recipe.ownerId,
                cloudRecordName: recipe.cloudRecordName,
                cloudImageRecordName: recipe.cloudImageRecordName,
                imageModifiedAt: recipe.imageModifiedAt,
                createdAt: recipe.createdAt,
                updatedAt: recipe.updatedAt,
                originalRecipeId: recipe.originalRecipeId,
                originalCreatorId: recipe.originalCreatorId,
                originalCreatorName: recipe.originalCreatorName,
                savedAt: recipe.savedAt,
                sourceRecipeUpdatedAt: recipe.sourceRecipeUpdatedAt,
                followsSourceUpdates: recipe.followsSourceUpdates,
                relatedRecipeIds: recipe.relatedRecipeIds,
                isPreview: true
            )

            try await dependencies.recipeRepository.create(previewRecipe, skipCloudSync: true)
            AppLogger.general.info("📝 Saved recipe as preview: \(recipe.title)")

            if recipe.cloudImageRecordName != nil {
                do {
                    if let filename = try await dependencies.imageManager.downloadImageFromCloud(
                        recipeId: previewRecipe.id,
                        fromPublic: true
                        ) {
                            let imageURL = await dependencies.imageManager.imageURL(for: filename)
                        let updatedPreview = previewRecipe.withImageState(
                            imageURL: imageURL,
                            cloudImageRecordName: previewRecipe.cloudImageRecordName,
                            imageModifiedAt: previewRecipe.imageModifiedAt
                        )
                        try await dependencies.recipeRepository.update(
                            updatedPreview,
                            shouldUpdateTimestamp: false,
                            skipImageSync: true,
                            skipCloudSync: true
                        )
                        AppLogger.general.info("✅ Downloaded image for preview recipe: \(recipe.title)")

                        self.recipe = updatedPreview
                        imageRefreshID = UUID()
                    }
                } catch {
                    AppLogger.general.warning("Failed to download image for preview: \(error.localizedDescription)")
                }
            }
        } catch {
            AppLogger.general.error("Failed to save preview recipe: \(error.localizedDescription)")
        }
    }

    func checkForOwnedCopy() async {
        guard let userId = CurrentUserSession.shared.userId else {
            return
        }

        isCheckingDuplicates = true
        defer { isCheckingDuplicates = false }

        do {
            if recipe.ownerId == userId {
                hasOwnedCopy = true
                AppLogger.general.info("Owned copy check: true for current user's recipe '\(recipe.title)'")
                return
            }

            let sourceRecipeID = recipe.relatedGraphReferenceID
            let ownedCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
                originalRecipeIds: [sourceRecipeID],
                ownerId: userId
            )
            hasOwnedCopy = ownedCopies.contains { $0.ownerId == userId }
            AppLogger.general.info("Owned copy check: \(hasOwnedCopy) for recipe '\(recipe.title)'")
        } catch {
            AppLogger.general.error("Failed to check for owned copy: \(error.localizedDescription)")
        }
    }

    func changeVisibility(to newVisibility: RecipeVisibility) async {
        isChangingVisibility = true
        defer { isChangingVisibility = false }

        do {
            try await dependencies.recipeRepository.updateVisibility(
                id: recipe.id,
                visibility: newVisibility
            )

            currentVisibility = newVisibility

            withAnimation {
                recipe = Recipe(
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
                    visibility: newVisibility,
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
            }

            AppLogger.general.info("Changed recipe '\(recipe.title)' visibility to \(newVisibility.displayName)")
        } catch {
            AppLogger.general.error("Failed to change visibility: \(error.localizedDescription)")
            errorMessage = "Failed to change visibility: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    func checkForRecipeUpdates() async {
        guard let originalRecipeId = recipe.originalRecipeId else {
            return
        }

        guard recipe.isFollowingSourceUpdates else {
            hasUpdates = false
            originalRecipe = nil
            return
        }

        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        do {
            guard let original = try await dependencies.recipeCloudService.fetchPublicRecipe(id: originalRecipeId) else {
                AppLogger.general.warning("Original recipe not found: \(originalRecipeId)")
                return
            }

            originalRecipe = original

            let sourceVersion = recipe.sourceRecipeUpdatedAt ?? recipe.savedAt
            if let sourceVersion,
               original.updatedAt > sourceVersion {
                if recipe.shouldPreserveLegacyEdits(comparedTo: original) {
                    let migratedRecipe = recipe.withSourceTracking(
                        sourceRecipeUpdatedAt: original.updatedAt,
                        followsSourceUpdates: false
                    )
                    try await dependencies.recipeRepository.update(migratedRecipe, shouldUpdateTimestamp: false, skipImageSync: true)
                    self.recipe = migratedRecipe
                    hasUpdates = false
                    originalRecipe = nil
                    return
                }

                let shouldRemoveImage = original.cloudImageRecordName == nil
                let needsImageRefresh = !shouldRemoveImage &&
                    (original.imageModifiedAt != recipe.imageModifiedAt || recipe.imageURL == nil)
                let pendingSourceVersion = needsImageRefresh
                    ? (recipe.sourceRecipeUpdatedAt ?? recipe.savedAt ?? recipe.updatedAt)
                    : original.updatedAt

                var updatedRecipe = recipe
                    .applyingSourceSnapshot(original)
                    .withSourceTracking(
                        sourceRecipeUpdatedAt: pendingSourceVersion,
                        followsSourceUpdates: true
                    )
                if needsImageRefresh {
                    updatedRecipe = updatedRecipe
                        .withImageState(
                            imageURL: recipe.imageURL,
                            cloudImageRecordName: recipe.cloudImageRecordName,
                            imageModifiedAt: recipe.imageModifiedAt
                        )
                        .withSourceTracking(
                            sourceRecipeUpdatedAt: pendingSourceVersion,
                            followsSourceUpdates: true
                        )
                }

                try await dependencies.recipeRepository.update(updatedRecipe, shouldUpdateTimestamp: false, skipImageSync: true)

                var didRefreshImage = false
                if shouldRemoveImage {
                    await dependencies.imageManager.deleteImage(recipeId: updatedRecipe.id)
                    didRefreshImage = true
                } else if needsImageRefresh {
                    do {
                        if let imageData = try await dependencies.recipeCloudService.downloadImageAsset(
                            recipeId: originalRecipeId,
                            fromPublic: true
                        ), let image = UIImage(data: imageData) {
                            let filename = try await dependencies.imageManager.saveImage(image, recipeId: updatedRecipe.id)
                            let imageURL = await dependencies.imageManager.imageURL(for: filename)
                            updatedRecipe = updatedRecipe
                                .withImageState(
                                    imageURL: imageURL,
                                    cloudImageRecordName: original.cloudImageRecordName,
                                    imageModifiedAt: original.imageModifiedAt
                                )
                                .withSourceTracking(
                                    sourceRecipeUpdatedAt: original.updatedAt,
                                    followsSourceUpdates: true
                                )
                            try await dependencies.recipeRepository.update(updatedRecipe, shouldUpdateTimestamp: false, skipImageSync: true)
                            didRefreshImage = true
                        }
                    } catch {
                        AppLogger.general.warning("Failed to refresh image from source recipe: \(error.localizedDescription)")
                    }
                }

                self.recipe = updatedRecipe
                currentVisibility = updatedRecipe.visibility
                localIsFavorite = updatedRecipe.isFavorite
                if didRefreshImage {
                    imageRefreshID = UUID()
                }
                hasUpdates = false
                AppLogger.general.info("✅ Auto-updated saved recipe '\(recipe.title)' from source")
                NotificationCenter.default.post(name: NSNotification.Name("RecipeUpdated"), object: updatedRecipe.id)
            } else {
                if recipe.requiresLegacySourceTrackingMigration {
                    let migratedRecipe = recipe.withSourceTracking(
                        sourceRecipeUpdatedAt: original.updatedAt,
                        followsSourceUpdates: true
                    )
                    try await dependencies.recipeRepository.update(migratedRecipe, shouldUpdateTimestamp: false, skipImageSync: true)
                    self.recipe = migratedRecipe
                }
                hasUpdates = false
                AppLogger.general.info("✅ Recipe '\(recipe.title)' is up to date")
            }
        } catch {
            AppLogger.general.error("❌ Failed to check for recipe updates: \(error.localizedDescription)")
            hasUpdates = false
        }
    }

    func updateRecipeCopy() async {
        guard let original = originalRecipe else {
            AppLogger.general.error("Cannot update recipe - original not loaded")
            return
        }

        isUpdatingRecipe = true
        defer { isUpdatingRecipe = false }

        do {
            let shouldRemoveImage = original.cloudImageRecordName == nil
            let needsImageRefresh = !shouldRemoveImage &&
                (original.imageModifiedAt != recipe.imageModifiedAt || recipe.imageURL == nil)
            let pendingSourceVersion = needsImageRefresh
                ? (recipe.sourceRecipeUpdatedAt ?? recipe.savedAt ?? recipe.updatedAt)
                : original.updatedAt

            var updatedRecipe = recipe
                .applyingSourceSnapshot(original)
                .withSourceTracking(
                    sourceRecipeUpdatedAt: pendingSourceVersion,
                    followsSourceUpdates: true
                )
            if needsImageRefresh {
                updatedRecipe = updatedRecipe
                    .withImageState(
                        imageURL: recipe.imageURL,
                        cloudImageRecordName: recipe.cloudImageRecordName,
                        imageModifiedAt: recipe.imageModifiedAt
                    )
                    .withSourceTracking(
                        sourceRecipeUpdatedAt: pendingSourceVersion,
                        followsSourceUpdates: true
                    )
            }

            try await dependencies.recipeRepository.update(updatedRecipe, shouldUpdateTimestamp: false, skipImageSync: true)

            var didRefreshImage = false
            if shouldRemoveImage {
                await dependencies.imageManager.deleteImage(recipeId: updatedRecipe.id)
                didRefreshImage = true
            } else if needsImageRefresh {
                do {
                    if let imageData = try await dependencies.recipeCloudService.downloadImageAsset(
                        recipeId: original.id,
                        fromPublic: true
                    ), let image = UIImage(data: imageData) {
                        let filename = try await dependencies.imageManager.saveImage(image, recipeId: updatedRecipe.id)
                        let imageURL = await dependencies.imageManager.imageURL(for: filename)
                        updatedRecipe = updatedRecipe
                            .withImageState(
                                imageURL: imageURL,
                                cloudImageRecordName: original.cloudImageRecordName,
                                imageModifiedAt: original.imageModifiedAt
                            )
                            .withSourceTracking(
                                sourceRecipeUpdatedAt: original.updatedAt,
                                followsSourceUpdates: true
                            )
                        try await dependencies.recipeRepository.update(updatedRecipe, shouldUpdateTimestamp: false, skipImageSync: true)
                        didRefreshImage = true
                    }
                } catch {
                    AppLogger.general.warning("Failed to refresh image while updating recipe from source: \(error.localizedDescription)")
                }
            }

            self.recipe = updatedRecipe
            currentVisibility = updatedRecipe.visibility
            localIsFavorite = updatedRecipe.isFavorite
            if didRefreshImage {
                imageRefreshID = UUID()
            }

            AppLogger.general.info("✅ Successfully refreshed recipe '\(recipe.title)' from source")

            hasUpdates = false

            withAnimation {
                showUpdateSuccessToast = true
            }

            NotificationCenter.default.post(name: NSNotification.Name("RecipeUpdated"), object: nil)
        } catch {
            AppLogger.general.error("❌ Failed to update recipe: \(error.localizedDescription)")
            errorMessage = "Failed to update recipe: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    func startTimer(_ timer: TimerSpec, stepIndex: Int) {
        dependencies.timerManager.startTimer(
            spec: timer,
            stepIndex: stepIndex,
            recipeName: recipe.title
        )
    }
}
