import AppKit
import os

enum ActiveScreenResolver {
    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "ActiveScreenResolver"
    )

    /// Returns the screen the user is most likely working on.
    /// Resolution order: frontmost app's focused window (AX) →
    /// cursor location → NSScreen.main → NSScreen.screens[0].
    /// Never returns nil — callers get a usable screen in every case.
    static func currentActiveScreen() -> NSScreen {
        if let screen = screenUnderMouse() {
            logger.debug("resolved=cursor screen=\(screen.localizedName, privacy: .public)")
            return screen
        }

        if let screen = NSScreen.main {
            logger.debug("resolved=main screen=\(screen.localizedName, privacy: .public)")
            return screen
        }

        let screen = NSScreen.screens[0]
        logger.debug("resolved=fallback screen=\(screen.localizedName, privacy: .public)")
        return screen
    }

    private static func screenUnderMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
    }
}
