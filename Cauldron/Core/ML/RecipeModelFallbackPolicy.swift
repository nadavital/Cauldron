import Foundation
import FoundationModels

nonisolated enum RecipeModelFallbackPolicy {
    static func shouldRetryOnDevice(
        error: any Error,
        route: RecipeModelRoute,
        onDeviceAvailable: Bool,
        emittedResponse: Bool = false
    ) -> Bool {
        guard route == .privateCloudCompute, onDeviceAvailable, !emittedResponse,
              !(error is CancellationError) else { return false }
        if let error = error as? URLError {
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                    .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(error.code)
        }
        #if canImport(FoundationModels, _version: 2.0)
        if #available(iOS 27.0, macCatalyst 27.0, *) {
            if let error = error as? PrivateCloudComputeLanguageModel.Error {
                switch error {
                case .networkFailure, .quotaLimitReached, .serviceUnavailable: return true
                @unknown default: return false
                }
            }
            if let error = error as? LanguageModelError {
                switch error {
                case .timeout, .rateLimited: return true
                default: return false
                }
            }
        }
        #endif
        // Refusals, guardrails, malformed output, and programming errors must
        // not silently trigger a second model request.
        return false
    }
}
