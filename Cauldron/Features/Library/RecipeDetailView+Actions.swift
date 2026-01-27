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
            let localRecipes = try await dependencies.recipeRepository.fetch(ids: recipe.relatedRecipeIds)
            var loadedRecipes = localRecipes

            let localIds = Set(localRecipes.map { $0.id })
            var missingIds = recipe.relatedRecipeIds.filter { !localIds.contains($0) }

            if !missingIds.isEmpty {
                let allUserRecipes = try await dependencies.recipeRepository.fetchAll()
                for userRecipe in allUserRecipes {
                    if let originalId = userRecipe.originalRecipeId, missingIds.contains(originalId) {
                        loadedRecipes.append(userRecipe)
                        missingIds.removeAll { $0 == originalId }
                        AppLogger.general.info("✅ Found owned copy for related recipe: \(userRecipe.title)")
                    }
                }
            }

            if !missingIds.isEmpty {
                AppLogger.general.info("📥 Fetching \(missingIds.count) missing related recipes from CloudKit")

                await withTaskGroup(of: Recipe?.self) { group in
                    for missingId in missingIds {
                        group.addTask {
                            try? await self.dependencies.recipeCloudService.fetchPublicRecipe(id: missingId)
                        }
                    }

                    for await fetchedRecipe in group {
                        if let fetchedRecipe = fetchedRecipe {
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
                                relatedRecipeIds: fetchedRecipe.relatedRecipeIds,
                                isPreview: true
                            )

                            do {
                                try await self.dependencies.recipeRepository.create(previewRecipe)
                                AppLogger.general.info("📝 Saved related recipe as preview: \(fetchedRecipe.title)")

                                if fetchedRecipe.cloudImageRecordName != nil {
                                    do {
                                        if let filename = try await self.dependencies.imageManager.downloadImageFromCloud(
                                            recipeId: previewRecipe.id,
                                            fromPublic: true
                                        ) {
                                            let imageURL = await self.dependencies.imageManager.imageURL(for: filename)
                                            let updatedPreview = previewRecipe.withImageURL(imageURL)
                                            try await self.dependencies.recipeRepository.update(updatedPreview)
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
                }

                AppLogger.general.info("✅ Loaded \(loadedRecipes.count) total related recipes (\(localRecipes.count) local, \(loadedRecipes.count - localRecipes.count) from CloudKit)")
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

        if !recipe.relatedRecipeIds.isEmpty {
            do {
                let localRelated = try await dependencies.recipeRepository.fetch(ids: recipe.relatedRecipeIds)
                let missingIds = Set(recipe.relatedRecipeIds).subtracting(localRelated.map { $0.id })

                if !missingIds.isEmpty {
                    var fetchedRelated: [Recipe] = []
                    await withTaskGroup(of: Recipe?.self) { group in
                        for missingId in missingIds {
                            group.addTask {
                                try? await self.dependencies.recipeCloudService.fetchPublicRecipe(id: missingId)
                            }
                        }

                        for await recipe in group {
                            if let recipe = recipe {
                                fetchedRelated.append(recipe)
                            }
                        }
                    }

                    if !fetchedRelated.isEmpty {
                        relatedRecipesToSave = fetchedRelated
                        showSaveRelatedRecipesPrompt = true
                        return
                    }
                }
            } catch {
                AppLogger.general.warning("Failed to check for related recipes: \(error.localizedDescription)")
            }
        }

        await performSaveRecipe(saveRelatedRecipes: false)
    }

    func performSaveRecipe(saveRelatedRecipes: Bool) async {
        guard let userId = CurrentUserSession.shared.userId else {
            AppLogger.general.error("Cannot save recipe - no current user")
            return
        }

        isSavingRecipe = true
        defer { isSavingRecipe = false }

        var relatedRecipeIdMapping: [UUID: UUID] = [:]

        do {
            if saveRelatedRecipes && !relatedRecipesToSave.isEmpty {
                AppLogger.general.info("📥 Saving \(relatedRecipesToSave.count) related recipes...")

                for relatedRecipe in relatedRecipesToSave {
                    let copiedRelated = relatedRecipe.withOwner(
                        userId,
                        originalCreatorId: relatedRecipe.ownerId,
                        originalCreatorName: nil
                    )
                    try await dependencies.recipeRepository.create(copiedRelated)
                    relatedRecipeIdMapping[relatedRecipe.id] = copiedRelated.id

                    if relatedRecipe.cloudImageRecordName != nil {
                        do {
                            if let imageData = try await dependencies.recipeCloudService.downloadImageAsset(
                                recipeId: relatedRecipe.id,
                                fromPublic: true
                            ), let image = UIImage(data: imageData) {
                                let filename = try await dependencies.imageManager.saveImage(image, recipeId: copiedRelated.id)
                                let imageURL = await dependencies.imageManager.imageURL(for: filename)
                                let updatedRelated = copiedRelated.withImageURL(imageURL)
                                try await dependencies.recipeRepository.update(updatedRelated)
                                AppLogger.general.info("✅ Downloaded image for related recipe: \(relatedRecipe.title)")
                            }
                        } catch {
                            AppLogger.general.warning("Failed to download image for related recipe: \(error.localizedDescription)")
                        }
                    }
                }

                AppLogger.general.info("✅ Saved \(relatedRecipesToSave.count) related recipes")
            }

            let existingRecipe = try await dependencies.recipeRepository.fetch(id: recipe.id)

            var copiedRecipe: Recipe
            if let existingPreview = existingRecipe, existingPreview.isPreview {
                AppLogger.general.info("🔄 Converting preview to owned recipe: \(recipe.title)")

                try await dependencies.recipeRepository.delete(id: existingPreview.id)

                let originalCloudImageRecordName = existingPreview.cloudImageRecordName
                let originalRecipeId = existingPreview.originalRecipeId ?? existingPreview.id

                let remappedRelatedIds = existingPreview.relatedRecipeIds.map { originalId in
                    relatedRecipeIdMapping[originalId] ?? originalId
                }

                copiedRecipe = Recipe(
                    id: UUID(),
                    title: existingPreview.title,
                    ingredients: existingPreview.ingredients,
                    steps: existingPreview.steps,
                    yields: existingPreview.yields,
                    totalMinutes: existingPreview.totalMinutes,
                    tags: existingPreview.tags,
                    nutrition: existingPreview.nutrition,
                    sourceURL: existingPreview.sourceURL,
                    sourceTitle: existingPreview.sourceTitle,
                    notes: existingPreview.notes,
                    imageURL: nil,
                    isFavorite: false,
                    visibility: .publicRecipe,
                    ownerId: userId,
                    cloudRecordName: nil,
                    cloudImageRecordName: nil,
                    imageModifiedAt: nil,
                    createdAt: Date(),
                    updatedAt: Date(),
                    originalRecipeId: originalRecipeId,
                    originalCreatorId: existingPreview.originalCreatorId ?? existingPreview.ownerId,
                    originalCreatorName: existingPreview.originalCreatorName ?? recipeOwner?.displayName,
                    savedAt: Date(),
                    relatedRecipeIds: remappedRelatedIds,
                    isPreview: false
                )

                try await dependencies.recipeRepository.create(copiedRecipe)

                if originalCloudImageRecordName != nil {
                    do {
                        if let imageData = try await dependencies.recipeCloudService.downloadImageAsset(
                            recipeId: originalRecipeId,
                            fromPublic: true
                        ), let image = UIImage(data: imageData) {
                            let filename = try await dependencies.imageManager.saveImage(image, recipeId: copiedRecipe.id)
                            let imageURL = await dependencies.imageManager.imageURL(for: filename)

                            let updatedRecipe = copiedRecipe.withImageURL(imageURL)
                            try await dependencies.recipeRepository.update(updatedRecipe, shouldUpdateTimestamp: false, skipImageSync: true)

                            AppLogger.general.info("✅ Downloaded and saved image for copied recipe")
                            copiedRecipe = updatedRecipe
                        }
                    } catch {
                        AppLogger.general.warning("Failed to download image for copied recipe: \(error.localizedDescription)")
                    }
                }

                AppLogger.general.info("✅ Converted preview to owned recipe: \(recipe.title)")
            } else {
                var tempCopiedRecipe = recipe.withOwner(
                    userId,
                    originalCreatorId: recipe.ownerId,
                    originalCreatorName: recipeOwner?.displayName
                )

                if !relatedRecipeIdMapping.isEmpty {
                    let remappedRelatedIds = tempCopiedRecipe.relatedRecipeIds.map { originalId in
                        relatedRecipeIdMapping[originalId] ?? originalId
                    }
                    tempCopiedRecipe = Recipe(
                        id: tempCopiedRecipe.id,
                        title: tempCopiedRecipe.title,
                        ingredients: tempCopiedRecipe.ingredients,
                        steps: tempCopiedRecipe.steps,
                        yields: tempCopiedRecipe.yields,
                        totalMinutes: tempCopiedRecipe.totalMinutes,
                        tags: tempCopiedRecipe.tags,
                        nutrition: tempCopiedRecipe.nutrition,
                        sourceURL: tempCopiedRecipe.sourceURL,
                        sourceTitle: tempCopiedRecipe.sourceTitle,
                        notes: tempCopiedRecipe.notes,
                        imageURL: tempCopiedRecipe.imageURL,
                        isFavorite: tempCopiedRecipe.isFavorite,
                        visibility: tempCopiedRecipe.visibility,
                        ownerId: tempCopiedRecipe.ownerId,
                        cloudRecordName: tempCopiedRecipe.cloudRecordName,
                        cloudImageRecordName: tempCopiedRecipe.cloudImageRecordName,
                        imageModifiedAt: tempCopiedRecipe.imageModifiedAt,
                        createdAt: tempCopiedRecipe.createdAt,
                        updatedAt: tempCopiedRecipe.updatedAt,
                        originalRecipeId: tempCopiedRecipe.originalRecipeId,
                        originalCreatorId: tempCopiedRecipe.originalCreatorId,
                        originalCreatorName: tempCopiedRecipe.originalCreatorName,
                        savedAt: tempCopiedRecipe.savedAt,
                        relatedRecipeIds: remappedRelatedIds,
                        isPreview: tempCopiedRecipe.isPreview
                    )
                }
                copiedRecipe = tempCopiedRecipe

                try await dependencies.recipeRepository.create(copiedRecipe)
                AppLogger.general.info("✅ Saved recipe to library: \(recipe.title)")

                if recipe.cloudImageRecordName != nil && copiedRecipe.imageURL == nil {
                    do {
                        if let imageData = try await dependencies.recipeCloudService.downloadImageAsset(
                            recipeId: recipe.id,
                            fromPublic: true
                        ), let image = UIImage(data: imageData) {
                            let filename = try await dependencies.imageManager.saveImage(image, recipeId: copiedRecipe.id)
                            let imageURL = await dependencies.imageManager.imageURL(for: filename)
                            let updatedRecipe = copiedRecipe.withImageURL(imageURL)
                            try await dependencies.recipeRepository.update(updatedRecipe)
                            AppLogger.general.info("✅ Downloaded and saved recipe image: \(filename)")
                        }
                    } catch {
                        AppLogger.general.warning("Failed to download recipe image: \(error.localizedDescription)")
                    }
                }
            }

            NotificationCenter.default.post(name: NSNotification.Name("RecipeAdded"), object: nil)

            withAnimation {
                recipe = copiedRecipe
                currentVisibility = copiedRecipe.visibility
                localIsFavorite = copiedRecipe.isFavorite
                hasOwnedCopy = true
                showSaveSuccessToast = true
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
                if existingRecipe.isPreview && existingRecipe.imageURL == nil && recipe.cloudImageRecordName != nil {
                    AppLogger.general.info("📥 Downloading image for existing preview recipe: \(recipe.title)")
                    if let filename = try await dependencies.imageManager.downloadImageFromCloud(
                        recipeId: recipe.id,
                        fromPublic: true
                    ) {
                        let imageURL = await dependencies.imageManager.imageURL(for: filename)
                        let updatedRecipe = existingRecipe.withImageURL(imageURL)
                        try await dependencies.recipeRepository.update(updatedRecipe, skipImageSync: true)
                        AppLogger.general.info("✅ Updated preview with image: \(recipe.title)")

                        self.recipe = updatedRecipe
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
                relatedRecipeIds: recipe.relatedRecipeIds,
                isPreview: true
            )

            try await dependencies.recipeRepository.create(previewRecipe)
            AppLogger.general.info("📝 Saved recipe as preview: \(recipe.title)")

            if recipe.cloudImageRecordName != nil {
                do {
                    if let filename = try await dependencies.imageManager.downloadImageFromCloud(
                        recipeId: previewRecipe.id,
                        fromPublic: true
                    ) {
                        let imageURL = await dependencies.imageManager.imageURL(for: filename)
                        let updatedPreview = previewRecipe.withImageURL(imageURL)
                        try await dependencies.recipeRepository.update(updatedPreview)
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
            hasOwnedCopy = try await dependencies.recipeRepository.hasSimilarRecipe(
                title: recipe.title,
                ownerId: userId,
                ingredientCount: recipe.ingredients.count
            )
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
                    savedAt: recipe.savedAt
                )
            }

            AppLogger.general.info("Changed recipe '\(recipe.title)' visibility to \(newVisibility.displayName)")

            showingVisibilityPicker = false
        } catch {
            AppLogger.general.error("Failed to change visibility: \(error.localizedDescription)")
            errorMessage = "Failed to change visibility: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    func checkForRecipeUpdates() async {
        guard let originalRecipeId = recipe.originalRecipeId,
              let originalOwnerId = recipe.originalCreatorId else {
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

            if let savedAt = recipe.savedAt,
               original.updatedAt > savedAt {
                hasUpdates = true
                AppLogger.general.info("🔄 Updates available for recipe '\(recipe.title)': original updated at \(original.updatedAt), saved at \(savedAt)")
            } else {
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
            let updatedRecipe = Recipe(
                id: recipe.id,
                title: original.title,
                ingredients: original.ingredients,
                steps: original.steps,
                yields: original.yields,
                totalMinutes: original.totalMinutes,
                tags: original.tags,
                nutrition: original.nutrition,
                sourceURL: original.sourceURL,
                sourceTitle: original.sourceTitle,
                notes: original.notes,
                imageURL: original.imageURL,
                isFavorite: recipe.isFavorite,
                visibility: recipe.visibility,
                ownerId: recipe.ownerId,
                cloudRecordName: recipe.cloudRecordName,
                cloudImageRecordName: recipe.cloudImageRecordName,
                imageModifiedAt: recipe.imageModifiedAt,
                createdAt: recipe.createdAt,
                updatedAt: Date(),
                originalRecipeId: recipe.originalRecipeId,
                originalCreatorId: recipe.originalCreatorId,
                originalCreatorName: recipe.originalCreatorName,
                savedAt: Date()
            )

            try await dependencies.recipeRepository.update(updatedRecipe)

            AppLogger.general.info("✅ Successfully updated recipe '\(recipe.title)' from original")

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
