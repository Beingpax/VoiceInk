import SwiftUI
import AppKit

class VoiceLoopPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

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
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
    }

    static func calculateWindowMetrics() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 320, height: 140)
        }

        let width: CGFloat = 320
        let height: CGFloat = 140
        let padding: CGFloat = 80

        let visibleFrame = screen.visibleFrame
        let xPosition = visibleFrame.midX - (width / 2)
        let yPosition = visibleFrame.minY + padding

        return NSRect(x: xPosition, y: yPosition, width: width, height: height)
    }

    func show() {
        let metrics = VoiceLoopPanel.calculateWindowMetrics()
        setFrame(metrics, display: true)
        orderFrontRegardless()
    }
}
