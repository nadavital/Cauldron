import XCTest
@testable import Cauldron

final class DiagnosticsRecorderTests: XCTestCase {
    func testRecorderStoresOnlyTypedBoundedEvents() async {
        let recorder = InMemoryDiagnosticsRecorder()
        await recorder.record(.modelRoute(task: .parseImage, route: .privateCloudCompute, usedFallback: true))
        await recorder.record(.importFailed(source: .shareExtension, category: .persistence))

        let events = await recorder.recordedEvents()
        XCTAssertEqual(
            events,
            [
                .modelRoute(task: .parseImage, route: .privateCloudCompute, usedFallback: true),
                .importFailed(source: .shareExtension, category: .persistence)
            ]
        )
    }

    func testNumericMetricsAreClampedAndBucketed() async {
        let recorder = InMemoryDiagnosticsRecorder()
        await recorder.record(.importCompleted(source: .url, durationMilliseconds: 999_999))
        await recorder.record(.queuedUpload(count: -4, oldestAgeSeconds: 9_999_999))

        let events = await recorder.recordedEvents()
        XCTAssertEqual(
            events,
            [
                .importCompleted(source: .url, durationMilliseconds: 120_000),
                .queuedUpload(count: 0, oldestAgeSeconds: 604_800)
            ]
        )
    }
}
