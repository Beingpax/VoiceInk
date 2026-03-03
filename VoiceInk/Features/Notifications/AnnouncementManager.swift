import SwiftUI
import AppKit

final class AnnouncementManager {
    static let shared = AnnouncementManager()

    private var panel: NSPanel?

    private init() {}

    @MainActor
    func showAnnouncement(title: String, description: String?, learnMoreURL: URL?, onDismiss: @escaping () -> Void) {
        dismiss()

        let view = AnnouncementView(
            title: title,
            description: description ?? "",
            onClose: { [weak self] in
                onDismiss()
                self?.dismiss()
            },
            onLearnMore: { [weak self] in
                if let url = learnMoreURL {
                    NSWorkspace.shared.open(url)
                }
                onDismiss()
                self?.dismiss()
            }
        )

        let hosting = NSHostingController(rootView: view)
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hosting.view
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        position(panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil as Any?)
        self.panel = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    @MainActor
    func dismiss() {
        guard let panel = panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.close()
        })
    }

    @MainActor
    private func position(_ panel: NSPanel) {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        // Match MiniRecorder: bottom padding 24, centered horizontally
        let bottomPadding: CGFloat = 24
        let x = visibleFrame.midX - (panel.frame.width / 2)
        // Ensure bottom padding, but if the panel is taller, anchor its bottom at padding
        let y = max(visibleFrame.minY + bottomPadding, visibleFrame.minY + bottomPadding)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}


