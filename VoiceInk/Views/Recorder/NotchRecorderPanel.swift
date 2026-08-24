import AppKit
import SwiftUI
import os

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class NotchRecorderPanel: KeyablePanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "NotchRecorderPanel")

    init(contentRect: NSRect) {
        // Previously this initializer ignored `contentRect` and recomputed the metrics itself.
        // The only caller passes the metrics it just computed, so behaviour is unchanged.
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .hudWindow],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.canHide = false
        self.level = .statusBar + 3
        self.backgroundColor = .clear
        self.isOpaque = false
        self.alphaValue = 1.0
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.appearance = NSAppearance(named: .darkAqua)
        self.styleMask.remove(.titled)
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.isMovable = false
    }

    /// Returns `nil` when there is no screen at all, so callers can skip showing the panel
    /// instead of placing it at the global origin.
    static func calculateWindowMetrics() -> (frame: NSRect, notchWidth: CGFloat, notchHeight: CGFloat)? {
        guard let screen = RecorderScreenResolver.resolve() else { return nil }

        let safeAreaInsets = screen.safeAreaInsets
        let notchHeight: CGFloat = safeAreaInsets.top > 0 ? safeAreaInsets.top : NSStatusBar.system.thickness

        let notchWidth: CGFloat = {
            if let left = screen.auxiliaryTopLeftArea?.width,
                let right = screen.auxiliaryTopRightArea?.width
            {
                return screen.frame.width - left - right
            }
            return 180
        }()

        let maxSideExpansion: CGFloat = 240
        let sideMargin: CGFloat = 10
        let totalWidth = notchWidth + (maxSideExpansion + sideMargin) * 2

        let maxContentHeight: CGFloat = 430
        let xPosition = screen.frame.midX - (totalWidth / 2)
        let yPosition = screen.frame.maxY - maxContentHeight

        let frame = NSRect(x: xPosition, y: yPosition, width: totalWidth, height: maxContentHeight)
        return (frame, notchWidth, notchHeight)
    }

    @discardableResult
    func show() -> Bool {
        guard let metrics = NotchRecorderPanel.calculateWindowMetrics() else {
            logger.error("Notch panel show skipped: no screen available")
            return false
        }

        setFrame(metrics.frame, display: true)
        orderFrontRegardless()

        logger.notice(
            "Notch panel frame=\(NSStringFromRect(self.frame), privacy: .public) notch=\(metrics.notchWidth, privacy: .public)x\(metrics.notchHeight, privacy: .public) screens=\(NSScreen.screens.count, privacy: .public) onActiveSpace=\(self.isOnActiveSpace, privacy: .public)"
        )
        return true
    }

    deinit {
        logger.debug("Notch panel deallocated")
    }
}

class NotchRecorderHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
