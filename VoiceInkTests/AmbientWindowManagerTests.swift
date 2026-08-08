import AppKit
import SwiftUI
import Testing

@testable import VoiceInk

/// The ambient window's lifecycle, which is where the worst bug of the session lived.
///
/// Switching the recorder style to Mini left this window alive — the teardown was skipped whenever
/// the panel was not currently on screen — and the 1s watchdog that keeps it on the active display
/// went on calling `orderFrontRegardless` forever. A display-sized window forced itself to the
/// front once a second while the user was in a different recorder style entirely, and swallowed
/// every click on the machine.
///
/// Nothing here was covered, and none of it is hard to cover. The through-line of these tests is
/// that a window told to go away stays away, including past the watchdog's next tick.
@MainActor
struct AmbientWindowManagerTests {

    /// Longer than the 1s watchdog interval, so anything that resurrects the panel has had its
    /// chance to do so before the assertion runs.
    private let pastOneWatchdogTick = Duration.milliseconds(1_400)

    private func makeManager() -> AmbientWindowManager {
        AmbientWindowManager { _ in AnyView(Color.clear) }
    }

    // MARK: - Showing

    @Test func showPutsAPanelOnScreen() {
        let manager = makeManager()
        defer { manager.destroyWindow() }

        manager.show()
        #expect(manager.panelExists)
        #expect(manager.isPanelOnScreen)
    }

    @Test func theWindowNeverTakesFocus() {
        // It sits over whatever you are working in. Becoming key would pull focus out of the app
        // the text is about to land in, which is the failure that broke Undo earlier.
        let manager = makeManager()
        defer { manager.destroyWindow() }

        manager.show()
        #expect(manager.panelCanBecomeKey == false)
    }

    @Test func showingTwiceIsHarmless() {
        let manager = makeManager()
        defer { manager.destroyWindow() }

        manager.show()
        manager.show()
        #expect(manager.isPanelOnScreen)
    }

    // MARK: - The mouse
    //
    // The window is display-sized, so accepting events it does not need is how it ends up eating
    // clicks meant for other apps.

    @Test func theWindowIgnoresTheMouseByDefault() {
        let manager = makeManager()
        defer { manager.destroyWindow() }

        manager.show()
        #expect(manager.panelIgnoresMouseEvents == true)
    }

    @Test func itAcceptsClicksOnlyWhileSomethingIsClickable() {
        let manager = makeManager()
        defer { manager.destroyWindow() }
        manager.show()

        manager.setInteractive(true)
        #expect(manager.panelIgnoresMouseEvents == false)

        manager.setInteractive(false)
        #expect(manager.panelIgnoresMouseEvents == true)
    }

    @Test func hidingAlsoGivesTheMouseBack() {
        // Belt and braces: if the view is torn down mid-interaction it may never report going
        // non-interactive, and a hidden window holding the mouse is unrecoverable from the UI.
        let manager = makeManager()
        defer { manager.destroyWindow() }

        manager.show()
        manager.setInteractive(true)
        manager.hide()
        #expect(manager.panelIgnoresMouseEvents == true)
    }

    // MARK: - Going away, and staying away

    @Test func hideTakesThePanelOffScreen() {
        let manager = makeManager()
        defer { manager.destroyWindow() }

        manager.show()
        manager.hide()
        #expect(!manager.isPanelOnScreen)
    }

    @Test func destroyLeavesNothingBehind() {
        let manager = makeManager()
        manager.show()
        manager.destroyWindow()
        #expect(!manager.panelExists)
    }

    @Test func aHiddenPanelIsNotResurrectedByTheWatchdog() async throws {
        // The exact shape of the bug. The watchdog exists to put the window back when a display
        // change strands it, and it must not confuse "hidden on purpose" with "stranded".
        let manager = makeManager()
        defer { manager.destroyWindow() }

        manager.show()
        manager.hide()

        try await Task.sleep(for: pastOneWatchdogTick)
        #expect(!manager.isPanelOnScreen)
        #expect(manager.panelIgnoresMouseEvents == true)
    }

    @Test func aDestroyedPanelStaysDestroyed() async throws {
        let manager = makeManager()
        manager.show()
        manager.destroyWindow()

        try await Task.sleep(for: pastOneWatchdogTick)
        #expect(!manager.panelExists)
    }

    @Test func destroyingWithoutShowingIsSafe() {
        let manager = makeManager()
        manager.destroyWindow()
        #expect(!manager.panelExists)
    }

    @Test func itCanBeShownAgainAfterBeingDestroyed() {
        // Switching recorder style away and back does exactly this.
        let manager = makeManager()
        defer { manager.destroyWindow() }

        manager.show()
        manager.destroyWindow()
        manager.show()
        #expect(manager.isPanelOnScreen)
    }

    // MARK: - Click-through

    @Test func theHostViewPassesThroughWhatItDoesNotDraw() {
        // NSHostingView answers a hit anywhere in its bounds with itself, which for a display-sized
        // window means claiming every click on the machine. Returning nil in that case is what lets
        // the event reach the window underneath.
        let host = AmbientPassthroughHostingView(rootView: Color.clear)
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        #expect(host.hitTest(NSPoint(x: 400, y: 300)) == nil)
    }
}

/// Apps where the light is suppressed. Small, but it decides whether a full-screen overlay appears
/// during a video call.
@MainActor
struct AmbientAppExclusionsTests {

    private func withCleanExclusions(_ body: () -> Void) {
        let original = AmbientAppExclusions.bundleIdentifiers
        defer { AmbientAppExclusions.bundleIdentifiers = original }
        AmbientAppExclusions.bundleIdentifiers = []
        body()
    }

    @Test func nothingIsExcludedByDefault() {
        withCleanExclusions {
            #expect(!AmbientAppExclusions.isExcluded("com.example.anything"))
        }
    }

    @Test func anExcludedAppIsRecognised() {
        withCleanExclusions {
            AmbientAppExclusions.bundleIdentifiers = ["us.zoom.xos"]
            #expect(AmbientAppExclusions.isExcluded("us.zoom.xos"))
            #expect(!AmbientAppExclusions.isExcluded("com.apple.TextEdit"))
        }
    }

    @Test func anUnknownAppIsNotExcluded() {
        // A nil bundle identifier is normal — some processes have none — and must not be treated
        // as a match, which would suppress the light at random.
        withCleanExclusions {
            AmbientAppExclusions.bundleIdentifiers = ["us.zoom.xos"]
            #expect(!AmbientAppExclusions.isExcluded(nil))
        }
    }

    @Test func duplicatesCollapse() {
        withCleanExclusions {
            AmbientAppExclusions.bundleIdentifiers = ["a", "b", "a"]
            #expect(AmbientAppExclusions.bundleIdentifiers == ["a", "b"])
        }
    }

    @Test func removalSticks() {
        withCleanExclusions {
            AmbientAppExclusions.bundleIdentifiers = ["a", "b"]
            AmbientAppExclusions.bundleIdentifiers = ["b"]
            #expect(!AmbientAppExclusions.isExcluded("a"))
            #expect(AmbientAppExclusions.isExcluded("b"))
        }
    }

    @Test func changingTheListAnnouncesItself() {
        // The window manager re-evaluates on this notification. Without it a newly excluded app
        // keeps the light until the next take.
        withCleanExclusions {
            var announced = false
            let token = NotificationCenter.default.addObserver(
                forName: .ambientExclusionsChanged, object: nil, queue: .main
            ) { _ in announced = true }
            defer { NotificationCenter.default.removeObserver(token) }

            AmbientAppExclusions.bundleIdentifiers = ["us.zoom.xos"]
            #expect(announced)
        }
    }
}
