import AppKit
import SwiftUI

/// Full-screen, click-through window that hosts the ambient border.
///
/// Never takes focus and never intercepts a click — it has to sit over whatever you are working in
/// without being in the way, which is the entire point of the ambient style.
@MainActor
final class AmbientRecorderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        // Not ignoring mouse events outright: the caption has buttons. Pass-through is handled
        // precisely by the hosting view below, which returns nil everywhere the SwiftUI content is
        // not hit-testable, so clicks fall to whatever is underneath.
        ignoresMouseEvents = false
        canHide = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    func positionOnActiveScreen() {
        guard let screen = NSScreen.main else { return }
        setFrame(screen.frame, display: true)
    }
}

/// A full-screen hosting view that only claims the clicks it actually draws something for.
///
/// `NSHostingView` returns itself for a hit anywhere in its bounds, which for a display-sized
/// window means swallowing every click on the machine. Returning nil when SwiftUI's own hit-test
/// resolves to the host itself lets AppKit pass the event to the window below.
@MainActor
final class AmbientPassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }
}

@MainActor
final class AmbientWindowManager {
    private var panel: AmbientRecorderPanel?
    private let makeView: () -> AnyView

    init(engine: VoiceInkEngine, recorder: Recorder) {
        self.makeView = {
            AnyView(AmbientRecorderView(stateProvider: engine, recorder: recorder))
        }
    }

    func show() {
        if panel == nil { build() }
        panel?.positionOnActiveScreen()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func destroyWindow() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func build() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let newPanel = AmbientRecorderPanel(contentRect: screenFrame)

        let host = AmbientPassthroughHostingView(rootView: makeView())
        host.frame = NSRect(origin: .zero, size: screenFrame.size)
        host.autoresizingMask = [.width, .height]
        newPanel.contentView = host

        panel = newPanel
    }
}
