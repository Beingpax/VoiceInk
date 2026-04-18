import AppKit
import ApplicationServices
import os

enum ActiveScreenResolver {
    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "ActiveScreenResolver"
    )

    private static let ownBundleIdentifier = "com.prakashjoshipax.VoiceInk"

    /// Returns the screen the user is most likely working on.
    /// Resolution order: frontmost app's focused window (AX) →
    /// cursor location → NSScreen.main → NSScreen.screens[0].
    /// Never returns nil — callers get a usable screen in every case.
    static func currentActiveScreen() -> NSScreen {
        if let screen = screenFromFrontmostAppFocusedWindow() {
            logger.debug("resolved=ax screen=\(screen.localizedName, privacy: .public)")
            return screen
        }

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

    // MARK: - AX branch

    private static func screenFromFrontmostAppFocusedWindow() -> NSScreen? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        // Don't target our own windows (Settings, About, onboarding).
        if frontmost.bundleIdentifier == ownBundleIdentifier { return nil }

        let appElement = AXUIElementCreateApplication(frontmost.processIdentifier)

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowValue = windowRef else { return nil }
        let window = windowValue as! AXUIElement

        guard let frame = axWindowFrame(window) else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    /// Reads a window's frame via AX and converts to AppKit coordinates.
    /// AX uses top-left origin with y growing downward; AppKit uses
    /// bottom-left origin with y growing upward. The flip reference is the
    /// primary screen's maxY (that's the origin AX reports against).
    private static func axWindowFrame(_ window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        let primaryMaxY = NSScreen.screens[0].frame.maxY
        let flippedY = primaryMaxY - position.y - size.height
        return CGRect(x: position.x, y: flippedY, width: size.width, height: size.height)
    }

    // MARK: - Cursor branch

    private static func screenUnderMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
    }
}
