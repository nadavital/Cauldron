import SwiftUI
import UIKit
import XCTest
@testable import Cauldron

/// Exercises the same mounted SwiftUI view through outer/inner-sized geometry
/// changes. These snapshots do not simulate a physical hinge reserved region.
@MainActor
final class CookModeAdaptiveRenderingTests: XCTestCase {
    @Observable
    final class Traits {
        var horizontal: UserInterfaceSizeClass = .compact
        var textSize: DynamicTypeSize = .large
    }

    private struct Probe: View {
        let traits: Traits
        let recipe: Recipe
        let dependencies: DependencyContainer
        let coordinator: CookModeCoordinator

        var body: some View {
            NavigationStack {
                CookModeView(recipe: recipe, coordinator: coordinator, dependencies: dependencies)
            }
            .environment(\.horizontalSizeClass, traits.horizontal)
            .environment(\.dynamicTypeSize, traits.textSize)
            .dependencies(dependencies)
        }
    }

    func testResizingPreservesActiveStepAndTimer() async throws {
        let dependencies = DependencyContainer.preview()
        let coordinator = CookModeCoordinator(
            dependencies: dependencies,
            applicationIsActive: false,
            observesApplicationLifecycle: false
        )
        let recipe = Recipe(
            title: "Slow roasted vegetables with lemon and herbs",
            ingredients: [
                Ingredient(name: "Carrots, peeled and cut into evenly sized pieces"),
                Ingredient(name: "Extra virgin olive oil"),
                Ingredient(name: "Fresh rosemary and thyme, finely chopped")
            ],
            steps: [
                CookStep(index: 0, text: "Prepare the vegetables."),
                CookStep(index: 1, text: "Spread the vegetables in a single layer. Turn them gently halfway through cooking, then continue roasting until the edges are golden and the centers are tender. Keep the smaller pieces toward the center of the tray so they do not burn."),
                CookStep(index: 2, text: "Finish with lemon and herbs.")
            ]
        )
        coordinator.currentRecipe = recipe
        coordinator.totalSteps = recipe.steps.count
        coordinator.currentStepIndex = 1
        dependencies.timerManager.startTimer(spec: TimerSpec(seconds: 600, label: "Roast"), stepIndex: 1, recipeName: recipe.title)
        let timer = try XCTUnwrap(dependencies.timerManager.activeTimers.first)
        defer { dependencies.timerManager.stopAllTimers() }

        let traits = Traits()
        let host = UIHostingController(rootView: Probe(
            traits: traits, recipe: recipe, dependencies: dependencies, coordinator: coordinator
        ))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 678))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }

        let configurations: [(String, CGSize, UserInterfaceSizeClass, DynamicTypeSize)] = [
            ("outer", CGSize(width: 466, height: 678), .compact, .large),
            ("inner-wide", CGSize(width: 951, height: 669), .regular, .large),
            ("inner-tall", CGSize(width: 669, height: 951), .regular, .large),
            ("narrow-split", CGSize(width: 320, height: 669), .compact, .large),
            ("accessibility", CGSize(width: 466, height: 678), .compact, .accessibility3),
            ("outer-again", CGSize(width: 466, height: 678), .compact, .large)
        ]
        for (name, size, sizeClass, textSize) in configurations {
            traits.horizontal = sizeClass
            traits.textSize = textSize
            window.frame.size = size
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))

            XCTAssertEqual(coordinator.currentRecipe?.id, recipe.id, name)
            XCTAssertEqual(coordinator.currentStepIndex, 1, name)
            XCTAssertEqual(dependencies.timerManager.activeTimers.first?.id, timer.id, name)
            XCTAssertEqual(dependencies.timerManager.activeTimers.first?.endDate, timer.endDate, name)

            let image = UIGraphicsImageRenderer(size: size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "cook-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
    func testScreenshotSceneMinimizesAndResumesWithoutResettingSession() async throws {
        let previousUser = CurrentUserSession.shared.currentUser
        CurrentUserSession.shared.currentUser = User(id: UUID(), username: "cook-test", displayName: "Cook Test", createdAt: .now)
        defer { CurrentUserSession.shared.currentUser = previousUser }
        let dependencies = DependencyContainer.preview()
        let coordinator = CookModeCoordinator(dependencies: dependencies,
                                              applicationIsActive: false,
                                              observesApplicationLifecycle: false)
        let ingredient = Ingredient(name: "Carrots")
        let recipe = Recipe(title: "Presentation regression", ingredients: [ingredient], steps: [
            CookStep(index: 0, text: "Prepare."),
            CookStep(index: 1, text: "Cook.")
        ])
        let host = UIHostingController(rootView: NavigationStack {
            ScreenshotCookModeScene(recipe: recipe, coordinator: coordinator, dependencies: dependencies)
        })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 669, height: 951))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .seconds(1))
        XCTAssertNotNil(host.presentedViewController)
        coordinator.nextStep()
        coordinator.updateReference(.toggleIngredient(ingredient.id))
        coordinator.updateReference(.selectPage(1))
        let selectedStep = coordinator.currentStepIndex
        coordinator.minimizeToBackground()
        try await Task.sleep(for: .seconds(1))
        XCTAssertNil(host.presentedViewController)
        XCTAssertTrue(coordinator.isActive)
        XCTAssertEqual(coordinator.currentStepIndex, selectedStep)
        XCTAssertEqual(coordinator.referenceState.checkedIngredientIDs, [ingredient.id])
        XCTAssertEqual(coordinator.referenceState.page, 1)
        coordinator.expandToFullScreen()
        try await Task.sleep(for: .seconds(1))
        XCTAssertNotNil(host.presentedViewController)
        XCTAssertEqual(coordinator.currentStepIndex, selectedStep)
        XCTAssertEqual(coordinator.referenceState.checkedIngredientIDs, [ingredient.id])
        XCTAssertEqual(coordinator.referenceState.page, 1)
        coordinator.minimizeToBackground()
        try await Task.sleep(for: .milliseconds(500))
        coordinator.endSession()
    }

}
