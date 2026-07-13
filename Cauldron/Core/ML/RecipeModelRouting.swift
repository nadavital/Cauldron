import Foundation

nonisolated enum RecipeIntelligenceTask: Sendable, Equatable {
    case generateRecipe(promptLength: Int)
    case parseText(characterCount: Int)
    case parseImage
    case clarifyStep
    case adaptRecipe(characterCount: Int)

    nonisolated var requiresVision: Bool {
        self == .parseImage
    }

    nonisolated var benefitsFromExtendedReasoning: Bool {
        switch self {
        case .parseImage, .adaptRecipe:
            return true
        case .generateRecipe(let promptLength), .parseText(let promptLength):
            return promptLength > 4_000
        case .clarifyStep:
            return false
        }
    }
}

nonisolated enum RecipeModelRoute: String, Sendable, Codable, Equatable {
    case onDevice
    case privateCloudCompute
    case deterministic
}

nonisolated struct RecipeModelAvailability: Sendable, Equatable {
    var supportsIOS27Models: Bool
    var onDeviceAvailable: Bool
    var onDeviceSupportsVision: Bool
    var privateCloudAvailable: Bool
    var privateCloudSupportsVision: Bool
    var privateCloudQuotaReached: Bool

    static let unavailable = RecipeModelAvailability(
        supportsIOS27Models: false,
        onDeviceAvailable: false,
        onDeviceSupportsVision: false,
        privateCloudAvailable: false,
        privateCloudSupportsVision: false,
        privateCloudQuotaReached: false
    )
}

nonisolated struct RecipeModelRoutingPolicy: Sendable {
    nonisolated init() {}

    nonisolated func route(
        task: RecipeIntelligenceTask,
        availability: RecipeModelAvailability
    ) -> RecipeModelRoute {
        if shouldUsePrivateCloud(for: task, availability: availability) {
            return .privateCloudCompute
        }

        guard availability.onDeviceAvailable else {
            return .deterministic
        }

        if task.requiresVision && !availability.onDeviceSupportsVision {
            return .deterministic
        }

        return .onDevice
    }

    nonisolated private func shouldUsePrivateCloud(
        for task: RecipeIntelligenceTask,
        availability: RecipeModelAvailability
    ) -> Bool {
        guard availability.supportsIOS27Models,
              availability.privateCloudAvailable,
              !availability.privateCloudQuotaReached,
              task.benefitsFromExtendedReasoning || !availability.onDeviceAvailable else {
            return false
        }

        return !task.requiresVision || availability.privateCloudSupportsVision
    }
}

nonisolated struct RecipeIntelligenceStatus: Sendable, Equatable {
    var selectedRoute: RecipeModelRoute
    var privateCloudApproachingLimit: Bool
    var fallbackReason: String?
}
