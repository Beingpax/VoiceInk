import SwiftUI
import AppKit

class NotificationManager {
    static let shared = NotificationManager()

    private var notificationWindow: NSPanel?
    private var dismissTimer: Timer?

    private init() {}

    @MainActor
    func showNotification(
        title: String,
        type: AppNotificationView.NotificationType,
        duration: TimeInterval = 3.0,
        onTap: (() -> Void)? = nil
    ) {
        dismissTimer?.invalidate()
        dismissTimer = nil

        if let existingWindow = notificationWindow {
            existingWindow.close()
            notificationWindow = nil
        }
        
        // Play esc sound for error notifications
        if type == .error {
            SoundManager.shared.playEscSound()
        }
        
        let notificationView = AppNotificationView(
            title: title,
            type: type,
            duration: duration,
            onClose: { [weak self] in
                Task { @MainActor in
                    self?.dismissNotification()
                }
            },
            onTap: onTap
        )
        let hostingController = NSHostingController(rootView: notificationView)
        let size = hostingController.view.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.contentView = hostingController.view
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level.mainMenu
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        
        positionWindow(panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil as Any?)
        
        self.notificationWindow = panel
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        })
        
        // Schedule a new timer to dismiss the new notification.
        dismissTimer = Timer.scheduledTimer(
            withTimeInterval: duration,
            repeats: false
        ) { [weak self] _ in
            self?.dismissNotification()
        }
    }

    @MainActor
    private func positionWindow(_ window: NSWindow) {
        let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let screenRect = activeScreen.visibleFrame
        let notificationRect = window.frame
        
        // Position notification centered horizontally on screen
        let notificationX = screenRect.midX - (notificationRect.width / 2)
        
        // Position notification near bottom of screen with appropriate spacing
        let bottomPadding: CGFloat = 24
        let componentHeight: CGFloat = 34
        let notificationSpacing: CGFloat = 16
        let notificationY = screenRect.minY + bottomPadding + componentHeight + notificationSpacing
        
        window.setFrameOrigin(NSPoint(x: notificationX, y: notificationY))
    }

    @MainActor
    func dismissNotification() {
        guard let window = notificationWindow else { return }
        
        notificationWindow = nil
        
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()

        })
    }
} 