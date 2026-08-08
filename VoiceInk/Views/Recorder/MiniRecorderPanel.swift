import AppKit
import SwiftUI

class MiniRecorderPanel: NSPanel {
    /// Only the assistant needs to type into this panel. For everything else the panel must stay
    /// non-key: clicking a peek button was pulling focus off the app the text landed in, so the
    /// synthesized Cmd+Z went to the panel and Undo did nothing. Reactivating the target app
    /// afterwards proved unreliable — macOS 14+ restricts cross-app activation — so the fix is to
    /// never take focus in the first place.
    var needsKeyFocus: () -> Bool = { false }

    override var canBecomeKey: Bool { needsKeyFocus() }
    override var canBecomeMain: Bool { needsKeyFocus() }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    private func configurePanel() {
        isFloatingPanel = true
        canHide = false
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
    }

    static func calculateWindowMetrics() -> NSRect {
        let width: CGFloat = 540
        let height: CGFloat = 430

        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: width, height: height)
        }

        // Host stays large enough for assistant output; SwiftUI controls the visible mini width.
        let padding: CGFloat = 24

        let visibleFrame = screen.visibleFrame
        let centerX = visibleFrame.midX
        let xPosition = centerX - (width / 2)
        let yPosition = visibleFrame.minY + padding

        return NSRect(
            x: xPosition,
            y: yPosition,
            width: width,
            height: height
        )
    }

    func show() {
        let metrics = MiniRecorderPanel.calculateWindowMetrics()
        setFrame(metrics, display: true)
        orderFrontRegardless()
    }

}
