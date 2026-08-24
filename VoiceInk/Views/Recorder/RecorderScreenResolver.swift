import AppKit

/// Resolves the screen the recorder panel should be placed on.
///
/// `NSScreen.main` is the screen containing the window with keyboard focus. VoiceInk is a
/// menu-bar style app that usually has no key window, so `NSScreen.main` can return `nil` —
/// most plausibly while displays are asleep or being reconfigured.
///
/// The point of this helper is the fallback chain, not the nil case itself: callers must never
/// fall back to a rect at the global origin, because a transparent, shadowless panel placed at
/// (0, 0) sits behind the Dock and is indistinguishable from a panel that never appeared.
enum RecorderScreenResolver {
    static func resolve() -> NSScreen? {
        if let main = NSScreen.main { return main }

        let mouseLocation = NSEvent.mouseLocation
        if let screenUnderMouse = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screenUnderMouse
        }

        return NSScreen.screens.first
    }
}
