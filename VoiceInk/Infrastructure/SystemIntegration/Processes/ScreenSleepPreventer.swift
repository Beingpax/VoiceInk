import Foundation
import IOKit.pwr_mgt
import os

final class ScreenSleepPreventer {
    static let shared = ScreenSleepPreventer()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ScreenSleepPreventer")
    private var assertionID: IOPMAssertionID = 0
    private let queue = DispatchQueue(label: "com.prakashjoshipax.voiceink.screenSleepPreventer")

    private init() {}

    func startPreventingSleep() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.assertionID == 0 else { return }
            
            let reason = "VoiceInk Recording Activity" as CFString
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &self.assertionID
            )
            
            if status != kIOReturnSuccess {
                self.logger.error("Failed to create power assertion to prevent display sleep: \(status)")
                self.assertionID = 0
            } else {
                self.logger.notice("Successfully created power assertion to prevent display sleep during recording")
            }
        }
    }

    func stopPreventingSleep() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.assertionID != 0 else { return }
            
            let currentAssertionID = self.assertionID
            self.assertionID = 0
            
            let status = IOPMAssertionRelease(currentAssertionID)
            if status != kIOReturnSuccess {
                self.logger.error("Failed to release power assertion: \(status)")
            } else {
                self.logger.notice("Successfully released power assertion")
            }
        }
    }
}
