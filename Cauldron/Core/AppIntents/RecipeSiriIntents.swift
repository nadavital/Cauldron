import AppIntents
import Foundation

struct StartCookingRecipeIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Cooking a Recipe"
    static var description = IntentDescription("Start Cook Mode for a recipe in your Cauldron library.")
    static var openAppWhenRun = true

    @Parameter(title: "Recipe")
    var recipe: RecipeIntentEntity

    init() {}

    init(recipe: RecipeIntentEntity) {
        self.recipe = recipe
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch try await RecipeIntentProvider.shared.startCooking(recipeID: recipe.id) {
        case .started, .alreadyActive:
            return .result(dialog: "Starting \(recipe.title) in Cook Mode.")
        case .conflict:
            return .result(dialog: "Another recipe is already cooking. Choose whether to replace it in Cauldron.")
        case .invalidRecipe:
            return .result(dialog: "That recipe is no longer available or doesn't have cooking steps.")
        }
    }
}

struct CurrentCookingStepIntent: AppIntent {
    static var title: LocalizedStringResource = "Current Cooking Step"
    static var description = IntentDescription("Read the current step in your active Cauldron cooking session.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = CookSessionSharedStore.read() else {
            return .result(dialog: "There isn't an active cooking session.")
        }
        guard let instructions = snapshot.stepInstructions,
              instructions.indices.contains(snapshot.stepIndex) else {
            return .result(dialog: "A cooking session is active, but its step text isn't available. Open Cauldron to continue.")
        }
        return .result(
            dialog: "Step \(snapshot.stepIndex + 1) of \(snapshot.totalSteps): \(instructions[snapshot.stepIndex])"
        )
    }
}

struct ResumeCookingIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Cooking"
    static var description = IntentDescription("Open your active Cauldron cooking session.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = CookSessionSharedStore.read() else {
            return .result(dialog: "There isn't an active cooking session.")
        }
        guard await RecipeIntentProvider.shared.resumeCooking(expectedRecipeID: snapshot.recipeID) else {
            return .result(dialog: "Cauldron couldn't restore that cooking session.")
        }
        return .result(dialog: "Opening your current cooking session.")
    }
}

struct EndCookingIntent: AppIntent {
    static var title: LocalizedStringResource = "End Cooking"
    static var description = IntentDescription("End the active Cauldron cooking session and its timers.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let expected = CookSessionSharedStore.read() else {
            return .result(dialog: "There isn't an active cooking session.")
        }
        try await requestConfirmation(
            result: .result(dialog: "End Cook Mode and stop all active cooking timers?")
        )
        if await RecipeIntentProvider.shared.endCooking(expected: expected) {
            return .result(dialog: "Cook Mode ended.")
        }
        return .result(dialog: "The cooking session changed, so Cauldron didn't end it.")
    }
}

struct CauldronAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartCookingRecipeIntent(),
            phrases: [
                "Start cooking \(\.$recipe) in \(.applicationName)",
                "Cook \(\.$recipe) with \(.applicationName)"
            ],
            shortTitle: "Start Cooking",
            systemImageName: "flame.fill"
        )
        AppShortcut(
            intent: CurrentCookingStepIntent(),
            phrases: [
                "What's my current step in \(.applicationName)",
                "Repeat my cooking step in \(.applicationName)"
            ],
            shortTitle: "Current Step",
            systemImageName: "list.number"
        )
        AppShortcut(
            intent: ResumeCookingIntent(),
            phrases: ["Resume cooking in \(.applicationName)"],
            shortTitle: "Resume Cooking",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: EndCookingIntent(),
            phrases: ["End cooking in \(.applicationName)"],
            shortTitle: "End Cooking",
            systemImageName: "stop.fill"
        )
    }
}
