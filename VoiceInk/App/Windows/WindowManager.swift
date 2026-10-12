import AppKit
import SwiftUI

enum AppWindowLayout {
    static let width: CGFloat = 950
    static let minimumHeight: CGFloat = 750
}

enum AppWindowID {
    static let main = "main"
}

enum WindowDiagnostics {
    static func visibleUserFacingWindows(excluding excludedWindow: NSWindow? = nil) -> [NSWindow] {
        NSApplication.shared.windows.filter { window in
            if let excludedWindow, window == excludedWindow {
                return false
            }

            return window.isVisible && window.level == .normal && window.styleMask.contains(.titled)
        }
    }
}

enum AppPresentationPolicy {
    static func activateForUserFacingWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    static func restoreAccessoryIfNeededAfterUserFacingWindowClosed() {
        DispatchQueue.main.async {
            let menuBarOnly = UserDefaults.standard.bool(forKey: "IsMenuBarOnly")
            let hasVisibleUserWindows = !WindowDiagnostics.visibleUserFacingWindows().isEmpty

            guard menuBarOnly else { return }
            guard !hasVisibleUserWindows else { return }

            NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.deactivate()
        }
    }
}

class WindowManager: NSObject {
    static let shared = WindowManager()

    private static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("com.prakashjoshipax.voiceink.mainWindow")
    private static let mainWindowAutosaveName = NSWindow.FrameAutosaveName("VoiceInkMainWindowFrame")

    private weak var mainWindow: NSWindow?
    private var didApplyInitialPlacement = false
    private var shouldShowNextConfiguredMainWindow = false

    private override init() {
        super.init()
    }

    func prepareForUserRequestedMainWindow() {
        guard !shouldShowNextConfiguredMainWindow else { return }
        shouldShowNextConfiguredMainWindow = true
    }

    func configureWindow(_ window: NSWindow) {
        if let existingWindow = NSApplication.shared.windows.first(where: {
            $0.identifier == Self.mainWindowIdentifier && $0 != window
        }) {
            window.close()
            if shouldShowNextConfiguredMainWindow {
                presentMainWindow(existingWindow)
                shouldShowNextConfiguredMainWindow = false
            } else {
                existingWindow.makeKeyAndOrderFront(nil)
            }
            return
        }

        let requiredStyleMask: NSWindow.StyleMask = [
            .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
        ]
        window.styleMask.formUnion(requiredStyleMask)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.title = "VoiceInk"
        window.collectionBehavior = [.fullScreenPrimary]
        window.level = .normal
        window.isOpaque = false
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: AppWindowLayout.width, height: AppWindowLayout.minimumHeight)
        window.maxSize = NSSize(width: AppWindowLayout.width, height: CGFloat.greatestFiniteMagnitude)
        window.setFrameAutosaveName(Self.mainWindowAutosaveName)
        applyInitialPlacementIfNeeded(to: window)
        registerMainWindowIfNeeded(window)

        if shouldShowNextConfiguredMainWindow {
            shouldShowNextConfiguredMainWindow = false
            presentMainWindow(window)
        } else if UserDefaults.standard.bool(forKey: "IsMenuBarOnly") {
            window.orderOut(nil)
        }
    }

    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.identifier = Self.mainWindowIdentifier
        window.delegate = self
    }

    @discardableResult
    func showMainWindow() -> NSWindow? {
        guard let window = resolveMainWindow() else {
            return nil
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        presentMainWindow(window)
        return window
    }

    func hideMainWindow() {
        guard let window = resolveMainWindow() else {
            return
        }

        window.orderOut(nil)
    }

    func currentMainWindow() -> NSWindow? {
        resolveMainWindow()
    }

    private func registerMainWindowIfNeeded(_ window: NSWindow) {
        if window.identifier == nil || window.identifier != Self.mainWindowIdentifier {
            registerMainWindow(window)
        }
    }

    private func applyInitialPlacementIfNeeded(to window: NSWindow) {
        guard !didApplyInitialPlacement else { return }
        // Attempt to restore previous frame if one exists; otherwise fall back to a centered placement
        if window.setFrameUsingName(Self.mainWindowAutosaveName) {
            enforceMainWindowFrameIfNeeded(on: window, preserveRestoredOrigin: true)
        } else {
            enforceMainWindowFrameIfNeeded(on: window, preserveRestoredOrigin: false)
            window.center()
        }
        didApplyInitialPlacement = true
    }

    private func enforceMainWindowFrameIfNeeded(on window: NSWindow, preserveRestoredOrigin: Bool) {
        let currentFrame = window.frame
        guard currentFrame.width != AppWindowLayout.width || currentFrame.height < AppWindowLayout.minimumHeight else {
            return
        }

        let height = max(currentFrame.height, AppWindowLayout.minimumHeight)
        let x = preserveRestoredOrigin ? currentFrame.origin.x : currentFrame.midX - (AppWindowLayout.width / 2)
        let frame = NSRect(
            x: x,
            y: currentFrame.maxY - height,
            width: AppWindowLayout.width,
            height: height
        )
        window.setFrame(frame, display: true)
    }

    private func resolveMainWindow() -> NSWindow? {
        if let window = mainWindow {
            return window
        }

        if let window = NSApplication.shared.windows.first(where: { $0.identifier == Self.mainWindowIdentifier }) {
            mainWindow = window
            window.delegate = self
            return window
        }

        return nil
    }

    private func presentMainWindow(_ window: NSWindow) {
        AppPresentationPolicy.activateForUserFacingWindow()

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if !window.isKeyWindow {
            window.orderFrontRegardless()
        }
    }
}

extension WindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window.identifier == Self.mainWindowIdentifier {
            mainWindow = nil
            didApplyInitialPlacement = false
        }
    }
}
