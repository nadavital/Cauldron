import XCTest
@testable import Cauldron

final class RecipeModelRoutingTests: XCTestCase {
    private let policy = RecipeModelRoutingPolicy()

    func testShortTasksPreferOnDevice() {
        XCTAssertEqual(
            policy.route(task: .clarifyStep, availability: fullyAvailable),
            .onDevice
        )
        XCTAssertEqual(
            policy.route(task: .parseText(characterCount: 500), availability: fullyAvailable),
            .onDevice
        )
    }

    func testComplexTasksPreferPrivateCloud() {
        XCTAssertEqual(
            policy.route(task: .parseText(characterCount: 8_000), availability: fullyAvailable),
            .privateCloudCompute
        )
        XCTAssertEqual(
            policy.route(task: .adaptRecipe(characterCount: 2_000), availability: fullyAvailable),
            .privateCloudCompute
        )
        XCTAssertEqual(
            policy.route(task: .parseImage, availability: fullyAvailable),
            .privateCloudCompute
        )
    }

    func testQuotaAndAvailabilityFallBackToOnDevice() {
        var availability = fullyAvailable
        availability.privateCloudQuotaReached = true
        XCTAssertEqual(
            policy.route(task: .adaptRecipe(characterCount: 10_000), availability: availability),
            .onDevice
        )

        availability.privateCloudQuotaReached = false
        availability.privateCloudAvailable = false
        XCTAssertEqual(
            policy.route(task: .parseText(characterCount: 10_000), availability: availability),
            .onDevice
        )
    }

    func testVisionRequiresVisionCapableModel() {
        var availability = fullyAvailable
        availability.privateCloudSupportsVision = false
        XCTAssertEqual(policy.route(task: .parseImage, availability: availability), .onDevice)

        availability.onDeviceSupportsVision = false
        XCTAssertEqual(policy.route(task: .parseImage, availability: availability), .deterministic)
    }

    func testUnavailableModelsUseDeterministicFallback() {
        XCTAssertEqual(
            policy.route(task: .parseText(characterCount: 100), availability: .unavailable),
            .deterministic
        )
    }

    func testPrivateCloudIsUsedForShortTasksWhenOnDeviceIsUnavailable() {
        var availability = fullyAvailable
        availability.onDeviceAvailable = false

        XCTAssertEqual(
            policy.route(task: .clarifyStep, availability: availability),
            .privateCloudCompute
        )
        XCTAssertEqual(
            policy.route(task: .parseText(characterCount: 50), availability: availability),
            .privateCloudCompute
        )
    }

    func testPrivateCloudOnlyImageStillRequiresVisionCapability() {
        var availability = fullyAvailable
        availability.onDeviceAvailable = false
        availability.privateCloudSupportsVision = false

        XCTAssertEqual(
            policy.route(task: .parseImage, availability: availability),
            .deterministic
        )
    }

    private var fullyAvailable: RecipeModelAvailability {
        RecipeModelAvailability(
            supportsIOS27Models: true,
            onDeviceAvailable: true,
            onDeviceSupportsVision: true,
            privateCloudAvailable: true,
            privateCloudSupportsVision: true,
            privateCloudQuotaReached: false
        )
    }
}
