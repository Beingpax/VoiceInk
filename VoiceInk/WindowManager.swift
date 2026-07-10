import SwiftUI
import AppKit
import OSLog

enum AppWindowLayout {
    static let width: CGFloat = 950
    static let minimumHeight: CGFloat = 730
}

enum AppWindowID {
    static let main = "main"
}

enum WindowDiagnostics {
    static func activationPolicyDescription(_ policy: NSApplication.ActivationPolicy) -> String {
        switch policy {
        case .regular:
            return "regular"
        case .accessory:
            return "accessory"
        case .prohibited:
            return "prohibited"
        @unknown default:
            return "unknown(\(policy.rawValue))"
        }
    }

    static func windowDescription(_ window: NSWindow) -> String {
        let identifier = window.identifier?.rawValue ?? "nil"
        let title = window.title.isEmpty ? "<empty>" : window.title
        return "id=\(identifier), title=\(title), visible=\(window.isVisible), key=\(window.isKeyWindow), main=\(window.isMainWindow), miniaturized=\(window.isMiniaturized), level=\(window.level.rawValue), styleMask=\(window.styleMask.rawValue)"
    }

    static func windowSnapshot() -> String {
        let windows = NSApplication.shared.windows
        guard !windows.isEmpty else {
            return "windows=0"
        }

        let descriptions = windows
            .enumerated()
            .map { index, window in
                "#\(index){\(windowDescription(window))}"
            }
            .joined(separator: " | ")

        return "windows=\(windows.count): \(descriptions)"
    }

    static func visibleUserFacingWindowSnapshot(excluding excludedWindow: NSWindow? = nil) -> String {
        let windows = visibleUserFacingWindows(excluding: excludedWindow)

        guard !windows.isEmpty else {
            return "visibleUserWindows=0"
        }

        let descriptions = windows
            .enumerated()
            .map { index, window in
                "#\(index){\(windowDescription(window))}"
            }
            .joined(separator: " | ")

        return "visibleUserWindows=\(windows.count): \(descriptions)"
    }

    static func visibleUserFacingWindows(excluding excludedWindow: NSWindow? = nil) -> [NSWindow] {
        NSApplication.shared.windows.filter { window in
            if let excludedWindow, window == excludedWindow {
                return false
            }

            return window.isVisible &&
                window.level == .normal &&
                window.styleMask.contains(.titled)
        }
    }
}

enum AppPresentationPolicy {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MenuBarWindowFlow")

    static func activateForUserFacingWindow(reason: String) {
        let beforePolicy = NSApplication.shared.activationPolicy()
        let didSet = NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        Self.logger.notice("🧭 Activated app for user-facing window. reason=\(reason, privacy: .public); menuBarOnlyPreference=\(UserDefaults.standard.bool(forKey: "IsMenuBarOnly"), privacy: .public); activationPolicyBefore=\(WindowDiagnostics.activationPolicyDescription(beforePolicy), privacy: .public); setPolicySuccess=\(didSet, privacy: .public); activationPolicyAfter=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)")
    }

    static func restoreAccessoryIfNeededAfterUserFacingWindowClosed(reason: String) {
        DispatchQueue.main.async {
            let menuBarOnly = UserDefaults.standard.bool(forKey: "IsMenuBarOnly")
            let hasVisibleUserWindows = !WindowDiagnostics.visibleUserFacingWindows().isEmpty
            let visibleUserWindows = WindowDiagnostics.visibleUserFacingWindowSnapshot()

            guard menuBarOnly else {
                Self.logger.notice("🧭 Skipped restoring accessory activation policy because menu-bar-only preference is disabled. reason=\(reason, privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); \(visibleUserWindows, privacy: .public)")
                return
            }

            guard !hasVisibleUserWindows else {
                Self.logger.notice("🧭 Skipped restoring accessory activation policy because another user-facing window is still visible. reason=\(reason, privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); \(visibleUserWindows, privacy: .public)")
                return
            }

            let beforePolicy = NSApplication.shared.activationPolicy()
            let didSet = NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.deactivate()
            Self.logger.notice("🧭 Restored accessory activation policy after closing user-facing windows. reason=\(reason, privacy: .public); activationPolicyBefore=\(WindowDiagnostics.activationPolicyDescription(beforePolicy), privacy: .public); setPolicySuccess=\(didSet, privacy: .public); activationPolicyAfter=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)")
        }
    }
}

class WindowManager: NSObject {
    static let shared = WindowManager()

    private static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("com.prakashjoshipax.voiceink.mainWindow")
    private static let mainWindowAutosaveName = NSWindow.FrameAutosaveName("VoiceInkMainWindowFrame")

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MenuBarWindowFlow")
    private weak var mainWindow: NSWindow?
    private var didApplyInitialPlacement = false
    private var shouldShowNextConfiguredMainWindow = false

    private override init() {
        super.init()
    }

    func prepareForUserRequestedMainWindow() {
        guard !shouldShowNextConfiguredMainWindow else { return }

        shouldShowNextConfiguredMainWindow = true
        logger.notice("🧭 Prepared next configured main window for user-requested presentation. menuBarOnly=\(UserDefaults.standard.bool(forKey: "IsMenuBarOnly"), privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); storedMainWindow=\(self.mainWindow.map(WindowDiagnostics.windowDescription) ?? "nil", privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)")
    }
    
    func configureWindow(_ window: NSWindow) {
        let hadPendingPresentation = shouldShowNextConfiguredMainWindow
        logger.notice("🧭 Configuring main window. pendingUserPresentation=\(hadPendingPresentation, privacy: .public); menuBarOnly=\(UserDefaults.standard.bool(forKey: "IsMenuBarOnly"), privacy: .public); incoming=\(WindowDiagnostics.windowDescription(window), privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)")

        if let existingWindow = NSApplication.shared.windows.first(where: { $0.identifier == Self.mainWindowIdentifier && $0 != window }) {
            window.close()
            if shouldShowNextConfiguredMainWindow {
                logger.notice("🧭 Duplicate main window arrived while presentation was pending; presenting existing main window. existing=\(WindowDiagnostics.windowDescription(existingWindow), privacy: .public)")
                presentMainWindow(existingWindow)
                shouldShowNextConfiguredMainWindow = false
            } else {
                logger.notice("🧭 Duplicate main window arrived without pending presentation; reusing existing main window. existing=\(WindowDiagnostics.windowDescription(existingWindow), privacy: .public)")
                existingWindow.makeKeyAndOrderFront(nil)
            }
            return
        }
        
        let requiredStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
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
            logger.notice("🧭 Presenting newly configured main window for user request. window=\(WindowDiagnostics.windowDescription(window), privacy: .public)")
            presentMainWindow(window)
        } else if UserDefaults.standard.bool(forKey: "IsMenuBarOnly") {
            logger.notice("🧭 Ordering out newly configured main window because menu-bar-only mode is enabled and no user presentation is pending. window=\(WindowDiagnostics.windowDescription(window), privacy: .public)")
            window.orderOut(nil)
        } else {
            logger.notice("🧭 Configured main window without pending presentation. window=\(WindowDiagnostics.windowDescription(window), privacy: .public)")
        }
    }
    
    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.identifier = Self.mainWindowIdentifier
        window.delegate = self
        logger.notice("🧭 Registered main window. window=\(WindowDiagnostics.windowDescription(window), privacy: .public)")
    }
    
    @discardableResult
    func showMainWindow() -> NSWindow? {
        logger.notice("🧭 Show main window requested. storedMainWindow=\(self.mainWindow.map(WindowDiagnostics.windowDescription) ?? "nil", privacy: .public); pendingUserPresentation=\(self.shouldShowNextConfiguredMainWindow, privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)")

        guard let window = resolveMainWindow() else {
            logger.error("🧭 Show main window could not resolve a native window.")
            return nil
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        presentMainWindow(window)
        return window
    }
    
    func hideMainWindow() {
        logger.notice("🧭 Hide main window requested. storedMainWindow=\(self.mainWindow.map(WindowDiagnostics.windowDescription) ?? "nil", privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)")

        guard let window = resolveMainWindow() else {
            logger.notice("🧭 Hide main window skipped because no native main window is registered yet.")
            return
        }

        window.orderOut(nil)
        logger.notice("🧭 Main window ordered out. window=\(WindowDiagnostics.windowDescription(window), privacy: .public)")
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
            logger.notice("🧭 Recovered main window by identifier. window=\(WindowDiagnostics.windowDescription(window), privacy: .public)")
            return window
        }

        return nil
    }

    private func presentMainWindow(_ window: NSWindow) {
        AppPresentationPolicy.activateForUserFacingWindow(reason: "WindowManager.presentMainWindow")

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if !window.isKeyWindow {
            window.orderFrontRegardless()
        }
        logger.notice("🧭 Presented main window. window=\(WindowDiagnostics.windowDescription(window), privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public)")
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.logger.notice("🧭 Confirmed main window presentation after runloop. window=\(WindowDiagnostics.windowDescription(window), privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)")
        }
    }
}

extension WindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window.identifier == Self.mainWindowIdentifier {
            logger.notice("🧭 Main window will close; clearing stored reference. window=\(WindowDiagnostics.windowDescription(window), privacy: .public)")
            mainWindow = nil
            didApplyInitialPlacement = false
        }
    }
}
