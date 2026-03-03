import SwiftUI
import AppKit

class MiniRecorderPanel: NSPanel {
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
        hasShadow = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
    }
    
    static func calculateWindowMetrics() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 184, height: 60)
        }

        // Fixed compact window size - minimal and unobtrusive
        let width: CGFloat = 184
        let height: CGFloat = 60
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
    
    func hide(completion: @escaping () -> Void) {
        completion()
    }
} 