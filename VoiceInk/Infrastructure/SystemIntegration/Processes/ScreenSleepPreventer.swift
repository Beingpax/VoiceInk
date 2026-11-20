import Foundation
import IOKit.pwr_mgt
import os

/// Holds a display-sleep power assertion while recording is active.
/// Main-actor isolated and synchronous so the assertion exists before
/// hardware setup begins and start/stop calls can never be reordered.
@MainActor
final class ScreenSleepPreventer {
    static let shared = ScreenSleepPreventer()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ScreenSleepPreventer")
    private var assertionID: IOPMAssertionID = 0

    private init() {}

    func startPreventingSleep() {
        guard assertionID == 0 else { return }

        var newAssertionID: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "VoiceInk Recording Activity" as CFString,
            &newAssertionID
        )

        if status == kIOReturnSuccess {
            assertionID = newAssertionID
            logger.notice("Created power assertion to prevent display sleep during recording")
        } else {
            logger.error("Failed to create power assertion to prevent display sleep: \(status)")
        }
    }

    func stopPreventingSleep() {
        guard assertionID != 0 else { return }

        // Clear before releasing: a failed release means the ID is no longer valid,
        // and keeping it would block every later recording from taking a new assertion.
        let releasingID = assertionID
        assertionID = 0

        let status = IOPMAssertionRelease(releasingID)
        if status == kIOReturnSuccess {
            logger.notice("Released power assertion")
        } else {
            logger.error("Failed to release power assertion: \(status)")
        }
    }
}
