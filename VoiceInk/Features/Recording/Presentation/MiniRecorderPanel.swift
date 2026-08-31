import AppKit
import SwiftUI
import os

class MiniRecorderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MiniRecorderPanel")

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

    /// Returns `nil` when there is no screen at all, so callers can skip showing the panel
    /// instead of placing it at the global origin.
    static func calculateWindowMetrics() -> NSRect? {
        let width: CGFloat = 540
        let height: CGFloat = 430

        guard let screen = RecorderScreenResolver.resolve() else { return nil }

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

    @discardableResult
    func show() -> Bool {
        guard let metrics = MiniRecorderPanel.calculateWindowMetrics() else {
            logger.error("Mini panel show skipped: no screen available")
            return false
        }

        setFrame(metrics, display: true)
        orderFrontRegardless()

        logger.notice(
            "Mini panel frame=\(NSStringFromRect(self.frame), privacy: .public) screens=\(NSScreen.screens.count, privacy: .public) onActiveSpace=\(self.isOnActiveSpace, privacy: .public)"
        )
        return true
    }

    deinit {
        logger.debug("Mini panel deallocated")
    }
}
