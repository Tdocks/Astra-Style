import XCTest
@testable import AstraStyle

/// Exercises real stream/queue cleanup without starting camera hardware or asking permission.
final class LiveCaptureSessionLifecycleTests: XCTestCase {
    func testReplacingQualityStreamFinishesThePreviousSubscriber() async {
        let controller = LiveCaptureSessionController()
        let previous = controller.qualityFrames()
        let replacement = controller.qualityFrames()
        let ended = expectation(description: "previous subscriber finishes")
        let task = Task {
            for await _ in previous {}
            ended.fulfill()
        }
        defer { task.cancel() }
        await fulfillment(of: [ended], timeout: 2)
        // The previous stream's termination must leave the replacement attached.
        let replacementEnded = expectation(description: "replacement is stopped")
        let replacementTask = Task {
            for await _ in replacement {}
            replacementEnded.fulfill()
        }
        defer { replacementTask.cancel() }
        controller.stop()
        await fulfillment(of: [replacementEnded], timeout: 2)
    }

    func testStopReleasesTheLockAndSupportsAnotherScan() async {
        let controller = LiveCaptureSessionController()
        let first = controller.qualityFrames()
        let secondScanEnded = expectation(description: "another scan can subscribe and stop")
        let task = Task {
            for await _ in first {}
            let second = controller.qualityFrames()
            controller.stop()
            for await _ in second {}
            secondScanEnded.fulfill()
        }
        defer { task.cancel() }
        controller.stop()
        await fulfillment(of: [secondScanEnded], timeout: 3)
    }
}
