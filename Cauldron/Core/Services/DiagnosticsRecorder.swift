import Foundation
import os

nonisolated enum DiagnosticsEvent: Sendable, Equatable {
    case importCompleted(source: ImportSource, durationMilliseconds: Int)
    case importFailed(source: ImportSource, category: FailureCategory)
    case modelRoute(task: ModelTask, route: RecipeModelRoute, usedFallback: Bool)
    case queuedUpload(count: Int, oldestAgeSeconds: Int?)
    case cookSession(action: CookAction)

    enum ImportSource: String, Sendable { case url, text, image, shareExtension }
    enum FailureCategory: String, Sendable { case invalidInput, network, quota, parsing, persistence, unknown }
    enum ModelTask: String, Sendable { case generate, parseText, parseImage, clarify, adapt }
    enum CookAction: String, Sendable { case started, resumed, advanced, completed, ended }
}

extension DiagnosticsEvent {
    nonisolated var sanitized: DiagnosticsEvent {
        switch self {
        case .importCompleted(let source, let duration):
            let clamped = min(max(duration, 0), 120_000)
            return .importCompleted(
                source: source,
                durationMilliseconds: (clamped / 100) * 100
            )
        case .queuedUpload(let count, let age):
            return .queuedUpload(
                count: min(max(count, 0), 10_000),
                oldestAgeSeconds: age.map { min(max($0, 0), 604_800) }
            )
        default:
            return self
        }
    }
}

nonisolated protocol DiagnosticsRecording: Sendable {
    func record(_ event: DiagnosticsEvent) async
}

nonisolated final class PrivacySafeDiagnosticsRecorder: DiagnosticsRecording, @unchecked Sendable {
    private let logger = Logger(subsystem: "app.cauldron", category: "ProductHealth")

    init() {}

    func record(_ event: DiagnosticsEvent) async {
        // Events intentionally contain only bounded enums, counts, booleans,
        // and durations. Recipe text, URLs, names, and identifiers are excluded.
        switch event.sanitized {
        case .importCompleted(let source, let duration):
            logger.info("import_completed source=\(source.rawValue, privacy: .public) duration_ms=\(duration, privacy: .public)")
        case .importFailed(let source, let category):
            logger.error("import_failed source=\(source.rawValue, privacy: .public) category=\(category.rawValue, privacy: .public)")
        case .modelRoute(let task, let route, let fallback):
            logger.info("model_route task=\(task.rawValue, privacy: .public) route=\(route.rawValue, privacy: .public) fallback=\(fallback, privacy: .public)")
        case .queuedUpload(let count, let age):
            logger.info("queued_upload count=\(count, privacy: .public) oldest_s=\(age ?? -1, privacy: .public)")
        case .cookSession(let action):
            logger.info("cook_session action=\(action.rawValue, privacy: .public)")
        }
    }
}

actor InMemoryDiagnosticsRecorder: DiagnosticsRecording {
    private(set) var events: [DiagnosticsEvent] = []

    init() {}

    func record(_ event: DiagnosticsEvent) {
        events.append(event.sanitized)
    }

    func recordedEvents() -> [DiagnosticsEvent] { events }
}
