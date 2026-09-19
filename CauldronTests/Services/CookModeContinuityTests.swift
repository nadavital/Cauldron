import XCTest
@testable import Cauldron

@MainActor
final class CookModeContinuityTests: XCTestCase {
    func testReferenceStateRestoresWithSessionAndResetsForNewSession() async throws {
        let previousUser = CurrentUserSession.shared.currentUser
        CurrentUserSession.shared.currentUser = User(id: UUID(), username: "continuity", displayName: "Continuity", createdAt: .now)
        let dependencies = DependencyContainer.preview()
        let first = CookModeCoordinator(dependencies: dependencies, applicationIsActive: false, observesApplicationLifecycle: false)
        defer {
            first.endSession()
            CurrentUserSession.shared.currentUser = previousUser
        }
        first.endSession()
        let ingredient = Ingredient(name: "Chickpeas")
        // A shared recipe can restore from the cached session payload when it
        // isn't in the owner's library. This exercises the real cold restore.
        let recipe = Recipe(title: "Continuity", ingredients: [ingredient], steps: [
            CookStep(index: 0, text: "Prepare."), CookStep(index: 1, text: "Cook.")
        ], ownerId: UUID())
        let outcome = await first.startCooking(recipe)
        XCTAssertEqual(outcome, .started)
        first.nextStep()
        first.updateReference(.toggleIngredient(ingredient.id))
        first.updateReference(.selectPage(1))
        first.minimizeToBackground()
        first.expandToFullScreen()
        XCTAssertEqual(first.referenceState.checkedIngredientIDs, [ingredient.id])

        let restored = CookModeCoordinator(dependencies: dependencies, applicationIsActive: false, observesApplicationLifecycle: false)
        await restored.restoreState()
        XCTAssertTrue(restored.isActive)
        XCTAssertEqual(restored.currentRecipe?.id, recipe.id)
        XCTAssertEqual(restored.currentStepIndex, 1)
        XCTAssertEqual(restored.referenceState.checkedIngredientIDs, [ingredient.id])
        XCTAssertEqual(restored.referenceState.page, 1)
        restored.updateReference(.toggleIngredient(UUID()))
        XCTAssertEqual(restored.referenceState.checkedIngredientIDs, [ingredient.id])
        restored.endSession()
        let restarted = await restored.startCooking(recipe)
        XCTAssertEqual(restarted, .started)
        XCTAssertEqual(restored.referenceState, CookSessionReferenceState())
        restored.endSession()
    }
}
