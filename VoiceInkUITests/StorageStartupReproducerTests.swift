import Foundation
import XCTest

final class StorageStartupReproducerTests: XCTestCase {
    private let reproductionRootEnvironmentKey = "VOICEINK_STORAGE_REPRODUCTION_ROOT"
    private let persistentFailureMarkerName = "persistent-container-failed.txt"
    private let startupCompletedMarkerName = "startup-completed.txt"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCloudKitTeardownDoesNotDeadlockWhenLaterStoreFails() throws {
        let attempts = 5

        for attempt in 1...attempts {
            try runReproductionAttempt(attempt)
        }
    }

    @MainActor
    private func runReproductionAttempt(_ attempt: Int) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInk-CloudKitStartupReproducer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        // The production container loads stores in this order:
        // default (local), dictionary (CloudKit), stats (local).
        // Making the final store URL a directory forces initialization to roll
        // back after CloudKit setup has had an opportunity to begin.
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("stats.store", isDirectory: true),
            withIntermediateDirectories: false
        )

        let app = XCUIApplication()
        app.launchEnvironment[reproductionRootEnvironmentKey] = rootURL.path
        app.launch()

        let failureMarkerURL = rootURL.appendingPathComponent(persistentFailureMarkerName)
        let completedMarkerURL = rootURL.appendingPathComponent(startupCompletedMarkerName)
        let startupCompleted = waitForFile(at: completedMarkerURL, timeout: 20)

        if !startupCompleted {
            captureProcessSample(into: rootURL, attempt: attempt)

            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Storage startup reproduction attempt \(attempt)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        app.terminate()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: failureMarkerURL.path),
            "Attempt \(attempt) did not force the persistent-container failure."
        )
        XCTAssertTrue(
            startupCompleted,
            """
            Attempt \(attempt) did not finish startup within 20 seconds. On macOS 14.5,
            sample the VoiceInk process and check for PFCloudKitStoreMonitor waiting
            against PFCloudKitMetadataModelMigrator.
            """
        )
    }

    private func waitForFile(at url: URL, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return false
    }

    private func captureProcessSample(into rootURL: URL, attempt: Int) {
        let sampleURL = rootURL.appendingPathComponent("VoiceInk-storage-hang-sample.txt")
        let sampleProcess = Process()
        sampleProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        sampleProcess.arguments = ["VoiceInk", "5", "10", "-file", sampleURL.path]

        do {
            try sampleProcess.run()
            sampleProcess.waitUntilExit()

            guard FileManager.default.fileExists(atPath: sampleURL.path) else { return }
            let attachment = XCTAttachment(contentsOfFile: sampleURL)
            attachment.name = "Storage hang process sample attempt \(attempt)"
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTContext.runActivity(named: "Process sample capture failed") { activity in
                let attachment = XCTAttachment(string: error.localizedDescription)
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }
    }
}
