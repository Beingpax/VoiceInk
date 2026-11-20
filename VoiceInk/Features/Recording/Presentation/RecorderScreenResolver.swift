import AppKit

/// Prefers the retained display, then the cursor's screen, the active screen, and the first
/// available display. Returns `nil` when no screen is available.
@MainActor
enum RecorderScreenResolver {
    static func resolve(preferredDisplayID: CGDirectDisplayID? = nil) -> NSScreen? {
        // Read fresh screen objects: display geometry can change during a presentation.
        let screens = NSScreen.screens
        if let preferredDisplayID,
            let retainedScreen = screens.first(where: { displayID(for: $0) == preferredDisplayID })
        {
            return retainedScreen
        }

        let mouseLocation = NSEvent.mouseLocation
        if let screenUnderMouse = screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screenUnderMouse
        }

        return NSScreen.main ?? screens.first
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// Keeps one display until the recorder is dismissed or that display becomes unavailable.
@MainActor
struct RecorderScreenSelection {
    private var displayID: CGDirectDisplayID?

    mutating func resolve() -> NSScreen? {
        guard let screen = RecorderScreenResolver.resolve(preferredDisplayID: displayID) else { return nil }
        displayID = RecorderScreenResolver.displayID(for: screen)
        return screen
    }

    mutating func reset() {
        displayID = nil
    }
}
