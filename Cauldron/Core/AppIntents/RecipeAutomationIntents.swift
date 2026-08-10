import AppIntents
import Foundation

struct OpenRecipeIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open Recipe"

    @Parameter(title: "Recipe")
    var target: RecipeIntentEntity

    init() {}

    init(target: RecipeIntentEntity) {
        self.target = target
    }

    func perform() async throws -> some IntentResult {
        RecipeIntentNavigationStore.save(recipeID: target.id)
        await MainActor.run {
            NotificationCenter.default.post(name: .openRecipeFromIntent, object: target.id)
        }
        return .result()
    }
}

struct NextCookingStepIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Cooking Step"
    static var description = IntentDescription("Move to the next step in the active Cauldron cooking session.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let previous = await RecipeIntentProvider.shared.activeCookingSnapshot() else {
            return .result(dialog: "There isn't an active cooking session.")
        }
        guard previous.stepIndex < previous.totalSteps - 1 else {
            return .result(dialog: "You're already on the final step.")
        }
        guard let updated = CookSessionSharedStore.move(by: 1, expected: previous) else {
            return .result(dialog: "Cauldron couldn't advance the cooking session.")
        }
        notifyCookModeStepChanged(updated)
        await updateLiveActivityIfAvailable(updated)
        return .result(dialog: stepDialog(for: updated))
    }
}

struct PreviousCookingStepIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Cooking Step"
    static var description = IntentDescription("Move to the previous step in the active Cauldron cooking session.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let previous = await RecipeIntentProvider.shared.activeCookingSnapshot() else {
            return .result(dialog: "There isn't an active cooking session.")
        }
        guard previous.stepIndex > 0 else {
            return .result(dialog: "You're already on the first step.")
        }
        guard let updated = CookSessionSharedStore.move(by: -1, expected: previous) else {
            return .result(dialog: "Cauldron couldn't move back in the cooking session.")
        }
        notifyCookModeStepChanged(updated)
        await updateLiveActivityIfAvailable(updated)
        return .result(dialog: stepDialog(for: updated))
    }
}

struct AddRecipeIngredientsToGroceriesIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Recipe Ingredients to Groceries"
    static var description = IntentDescription("Add all ingredients from a Cauldron recipe to your grocery list.")

    @Parameter(title: "Recipe")
    var recipe: RecipeIntentEntity

    init() {}

    init(recipe: RecipeIntentEntity) {
        self.recipe = recipe
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let resolved = try await RecipeIntentProvider.shared.recipe(id: recipe.id) else {
            return .result(dialog: "That recipe is no longer in your Cauldron library.")
        }
        guard let resolvedOwnerID = resolved.ownerId,
              let identityContext = await MainActor.run(body: {
            CurrentUserSession.shared.verifiedMutationContext(ownerID: resolvedOwnerID)
        }) else {
            return .result(dialog: "Your iCloud account changed. Please try again.")
        }
        let items = resolved.ingredients.map { (name: $0.name, quantity: $0.quantity) }
        guard !items.isEmpty else {
            return .result(dialog: "\(resolved.title) doesn't have any ingredients to add.")
        }
        let addedCount = try await DependencyContainer.shared.groceryRepository
            .addItemsFromRecipeIfAbsent(
                recipeID: resolved.id.uuidString,
                recipeName: resolved.title,
                items: items,
                isAuthorizedToCommit: {
                    CurrentUserSession.shared.permitsMutation(identityContext)
                }
            )
        guard let addedCount else {
            return .result(
                dialog: "Your iCloud account changed while adding ingredients. Please try again."
            )
        }
        if addedCount == 0 {
            return .result(dialog: "The ingredients for \(resolved.title) are already in your grocery list.")
        }
        return .result(dialog: "Added \(addedCount) ingredients from \(resolved.title) to your grocery list.")
    }
}

struct QueueRecipeURLImportIntent: AppIntent {
    static var title: LocalizedStringResource = "Import Recipe from URL"
    static var description = IntentDescription("Add a webpage to Cauldron's durable Import Inbox for review.")

    @Parameter(title: "Recipe URL")
    var url: URL

    init() {}

    init(url: URL) {
        self.url = url
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            return .result(dialog: "Please provide a valid HTTP or HTTPS recipe URL.")
        }
        let result = try await DependencyContainer.shared.recipeImportInboxStore.enqueueIfAbsentWithDisposition(
            source: .url(url.absoluteString)
        )
        switch result.disposition {
        case .enqueued:
            return .result(dialog: "Added that page to Cauldron's Import Inbox.")
        case .alreadyQueued:
            return .result(dialog: "That page is already queued in Cauldron's Import Inbox.")
        case .retried:
            return .result(dialog: "Queued that page again in Cauldron's Import Inbox.")
        }
    }
}

struct QueueRecipeTextImportIntent: AppIntent {
    static var title: LocalizedStringResource = "Import Recipe Text"
    static var description = IntentDescription("Add recipe text to Cauldron's durable Import Inbox for review.")

    @Parameter(title: "Recipe Text")
    var recipeText: String

    init() {}

    init(recipeText: String) {
        self.recipeText = recipeText
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = recipeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Please provide some recipe text to import.")
        }
        guard trimmed.count <= 50_000 else {
            return .result(dialog: "That recipe text is too long. Please shorten it before importing.")
        }
        let result = try await DependencyContainer.shared.recipeImportInboxStore.enqueueIfAbsentWithDisposition(
            source: .text(trimmed)
        )
        switch result.disposition {
        case .enqueued:
            return .result(dialog: "Added that recipe text to Cauldron's Import Inbox.")
        case .alreadyQueued:
            return .result(dialog: "That recipe text is already queued in Cauldron's Import Inbox.")
        case .retried:
            return .result(dialog: "Queued that recipe text again in Cauldron's Import Inbox.")
        }
    }
}

struct StartCookingTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Cooking Timer"
    static var description = IntentDescription("Start a timer for the active Cauldron cooking step.")

    @Parameter(title: "Minutes", inclusiveRange: (1, 1_440))
    var minutes: Int

    @Parameter(title: "Label", default: "Cooking Timer")
    var label: String

    init() {}

    init(minutes: Int, label: String = "Cooking Timer") {
        self.minutes = minutes
        self.label = label
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let session = await RecipeIntentProvider.shared.activeCookingSnapshot() else {
            return .result(dialog: "Start Cook Mode before creating a cooking timer.")
        }
        let coordinator = await MainActor.run { DependencyContainer.shared.cookModeCoordinator }
        guard await coordinator.reconcileExternalState() else {
            return .result(dialog: "Cauldron couldn't restore the active cooking session. Open Cook Mode and try again.")
        }
        guard let recipeTitle = await MainActor.run(body: {
            coordinator.currentRecipe?.id == session.recipeID
                ? coordinator.currentRecipe?.title
                : nil
        }) else {
            return .result(dialog: "Cauldron couldn't find the recipe for the active cooking session.")
        }
        let safeLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let didStart = await MainActor.run {
            guard let current = CookSessionSharedStore.read(),
                  current.recipeID == session.recipeID,
                  current.ownerID == session.ownerID,
                  current.revision == session.revision,
                  current.sessionStartTime == session.sessionStartTime,
                  CurrentUserSession.shared.userId == session.ownerID else {
                return false
            }
            let dependencies = DependencyContainer.shared
            dependencies.timerManager.startTimer(
                spec: TimerSpec(seconds: minutes * 60, label: safeLabel.isEmpty ? "Cooking Timer" : safeLabel),
                stepIndex: current.stepIndex,
                recipeName: recipeTitle
            )
            // Accessing the coordinator installs the timer callback even when the
            // intent launched Cauldron before the SwiftUI scene was constructed.
            coordinator.updateLiveActivityForTimerChange()
            return true
        }
        guard didStart else {
            return .result(dialog: "The cooking session changed before the timer could start. Please try again.")
        }
        return .result(dialog: "Started a \(minutes)-minute timer for \(recipeTitle).")
    }
}

struct ListCookingTimersIntent: AppIntent {
    static var title: LocalizedStringResource = "List Cooking Timers"
    static var description = IntentDescription("Show the active timers in Cauldron.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard await RecipeIntentProvider.shared.activeCookingSnapshot() != nil else {
            return .result(dialog: "There isn't an active cooking session.")
        }
        let timers = await MainActor.run { DependencyContainer.shared.timerManager.activeTimers }
        guard !timers.isEmpty else {
            return .result(dialog: "There aren't any active cooking timers.")
        }
        let summary = timers.prefix(5).map { timer in
            let remainingMinutes = max(1, Int(ceil(Double(timer.remainingSeconds()) / 60)))
            return "\(timer.spec.label), about \(remainingMinutes) minutes remaining"
        }.joined(separator: "; ")
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}

nonisolated private func stepDialog(for snapshot: CookSessionSharedSnapshot) -> IntentDialog {
    if let instructions = snapshot.stepInstructions,
       instructions.indices.contains(snapshot.stepIndex) {
        return "Step \(snapshot.stepIndex + 1) of \(snapshot.totalSteps): \(instructions[snapshot.stepIndex])"
    }
    return "Moved to step \(snapshot.stepIndex + 1) of \(snapshot.totalSteps)."
}

nonisolated private func updateLiveActivityIfAvailable(_ snapshot: CookSessionSharedSnapshot) async {
    #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    await CookSessionLiveActivityUpdater.update(from: snapshot)
    #endif
}

nonisolated private func notifyCookModeStepChanged(_ snapshot: CookSessionSharedSnapshot) {
    NotificationCenter.default.post(
        name: NSNotification.Name("CookModeStepChanged"),
        object: snapshot
    )
}
