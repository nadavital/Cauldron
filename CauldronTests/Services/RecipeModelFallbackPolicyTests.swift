import XCTest
import FoundationModels
@testable import Cauldron

final class RecipeModelFallbackPolicyTests: XCTestCase {
    func testNetworkFallbackOnlyBeforeOutputAndWithLocalModel() {
        let error = URLError(.notConnectedToInternet)
        XCTAssertTrue(RecipeModelFallbackPolicy.shouldRetryOnDevice(error: error, route: .privateCloudCompute, onDeviceAvailable: true))
        XCTAssertFalse(RecipeModelFallbackPolicy.shouldRetryOnDevice(error: error, route: .privateCloudCompute, onDeviceAvailable: true, emittedResponse: true))
        XCTAssertFalse(RecipeModelFallbackPolicy.shouldRetryOnDevice(error: error, route: .privateCloudCompute, onDeviceAvailable: false))
        XCTAssertFalse(RecipeModelFallbackPolicy.shouldRetryOnDevice(error: error, route: .onDevice, onDeviceAvailable: true))
    }

    func testCancellationAndUnknownErrorsDoNotRetry() {
        for error: any Error in [CancellationError(), URLError(.cancelled), NSError(domain: "test", code: 1)] {
            XCTAssertFalse(RecipeModelFallbackPolicy.shouldRetryOnDevice(error: error, route: .privateCloudCompute, onDeviceAvailable: true))
        }
    }

    func testCloudQuotaAndServiceErrorsRetryButRefusalDoesNot() throws {
        #if canImport(FoundationModels, _version: 2.0)
        guard #available(iOS 27.0, macCatalyst 27.0, *) else { throw XCTSkip("Requires iOS 27 models") }
        let quota = PrivateCloudComputeLanguageModel.Error.quotaLimitReached(.init(debugDescription: "test quota"))
        let service = PrivateCloudComputeLanguageModel.Error.serviceUnavailable(.init(debugDescription: "test service"))
        XCTAssertTrue(RecipeModelFallbackPolicy.shouldRetryOnDevice(error: quota, route: .privateCloudCompute, onDeviceAvailable: true))
        XCTAssertTrue(RecipeModelFallbackPolicy.shouldRetryOnDevice(error: service, route: .privateCloudCompute, onDeviceAvailable: true))
        let error = LanguageModelSession.GenerationError.guardrailViolation(.init(debugDescription: "test guardrail"))
        XCTAssertFalse(RecipeModelFallbackPolicy.shouldRetryOnDevice(error: error, route: .privateCloudCompute, onDeviceAvailable: true))
        #endif
    }
}
