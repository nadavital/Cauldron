import XCTest
@testable import Cauldron

@MainActor
final class AIRecipePrimaryActionTests: XCTestCase {
    func testEmptyAndWhitespaceInputKeepGenerateDisabled() {
        let model = AIRecipeGeneratorViewModel(dependencies: .preview())
        XCTAssertEqual(model.primaryActionState(isAvailable: true), .generate(isEnabled: false))
        model.prompt = " \n\t "
        XCTAssertEqual(model.primaryActionState(isAvailable: true), .generate(isEnabled: false))
    }

    func testPromptEnablesGenerateAndClearingDisablesIt() {
        let model = AIRecipeGeneratorViewModel(dependencies: .preview())
        model.prompt = "Crispy lemon chickpeas"
        XCTAssertEqual(model.primaryActionState(isAvailable: true), .generate(isEnabled: true))
        model.prompt = ""
        XCTAssertEqual(model.primaryActionState(isAvailable: true), .generate(isEnabled: false))
    }

    func testCategoriesEnableGenerateWithoutPrompt() {
        let model = AIRecipeGeneratorViewModel(dependencies: .preview())
        model.selectedDiets = [.vegetarian]
        XCTAssertEqual(model.primaryActionState(isAvailable: true), .generate(isEnabled: true))
        model.selectedDiets = []
        XCTAssertEqual(model.primaryActionState(isAvailable: true), .generate(isEnabled: false))
    }

    func testUnavailableModelDisablesGenerateEvenWithInput() {
        let model = AIRecipeGeneratorViewModel(dependencies: .preview())
        model.prompt = "Dinner"
        XCTAssertEqual(model.primaryActionState(isAvailable: false), .generate(isEnabled: false))
    }

    func testGeneratingActionRemainsPresentButCannotBeTriggeredAgain() {
        let model = AIRecipeGeneratorViewModel(dependencies: .preview())
        model.prompt = "Dinner"
        model.isGenerating = true
        XCTAssertEqual(model.primaryActionState(isAvailable: true), .generating)
        XCTAssertFalse(model.primaryActionState(isAvailable: true).isEnabled)
    }

    func testCompletedRecipeCanBeSavedRegardlessOfPromptOrModelAvailability() {
        let model = AIRecipeGeneratorViewModel(dependencies: .preview())
        model.generatedRecipe = Recipe(title: "Dinner", ingredients: [], steps: [])
        XCTAssertEqual(model.primaryActionState(isAvailable: false), .save)
        XCTAssertTrue(model.primaryActionState(isAvailable: false).isEnabled)
    }

    func testSavingDisablesDuplicateSavesAndFailureAllowsRetry() {
        let model = AIRecipeGeneratorViewModel(dependencies: .preview())
        model.generatedRecipe = Recipe(title: "Dinner", ingredients: [], steps: [])
        model.isSaving = true
        XCTAssertEqual(model.primaryActionState(isAvailable: true), .saving)
        XCTAssertFalse(model.primaryActionState(isAvailable: true).isEnabled)
        model.isSaving = false
        model.errorMessage = "Save failed"
        XCTAssertEqual(model.primaryActionState(isAvailable: true), .save)
    }

    func testGenerationErrorRestoresGenerateForRetry() {
        let model = AIRecipeGeneratorViewModel(dependencies: .preview())
        model.prompt = "Dinner"
        model.isGenerating = false
        model.errorMessage = "Generation failed"
        XCTAssertEqual(model.primaryActionState(isAvailable: true), .generate(isEnabled: true))
    }
}
