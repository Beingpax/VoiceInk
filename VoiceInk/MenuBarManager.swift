import AppKit
import OSLog
import SwiftData
import SwiftUI

class MenuBarManager: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MenuBarWindowFlow")

    @Published var isMenuBarOnly: Bool {
        didSet {
            guard isReadyToApplyActivationPolicy else { return }
            UserDefaults.standard.set(isMenuBarOnly, forKey: "IsMenuBarOnly")
            applyActivationPolicy(logPreferenceChange: true)
        }
    }

    /// Controls whether the SwiftUI `MenuBarExtra` is present in the system menu bar.
    /// Kept on the manager (not `@State`) so launch / activation-policy changes can re-insert it.
    /// Applying `.accessory` too early or flipping policy can drop the extra on recent macOS builds.
    @Published var isMenuBarExtraInserted = true

    private var modelContainer: ModelContainer?
    private var engine: VoiceInkEngine?
    /// Skips activation-policy work during `init` (didSet runs on first assignment).
    private var isReadyToApplyActivationPolicy = false
    private var configuredActivationPolicy: NSApplication.ActivationPolicy {
        isMenuBarOnly ? .accessory : .regular
    }

    init() {
        Self.repairMenuBarStatusItemDefaults()
        self.isMenuBarOnly = UserDefaults.standard.bool(forKey: "IsMenuBarOnly")
        self.isReadyToApplyActivationPolicy = true
        logger.notice(
            "🧭 MenuBarManager initialized. isMenuBarOnly=\(self.isMenuBarOnly, privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public)"
        )
        // Do not call setActivationPolicy here — NSApp / MenuBarExtra are not ready during
        // StateObject construction. AppDelegate.applicationDidFinishLaunching applies it.

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userFacingWindowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func userFacingWindowWillClose(_ notification: Notification) {
        guard isMenuBarOnly,
            let window = notification.object as? NSWindow,
            window.level == .normal,
            window.styleMask.contains(.titled)
        else {
            return
        }

        AppPresentationPolicy.restoreAccessoryIfNeededAfterUserFacingWindowClosed(
            reason: "userFacingWindowWillClose"
        )
        // Re-assert the tray icon after accessory restore; policy flips can drop MenuBarExtra.
        ensureMenuBarExtraVisible()
    }

    func ensureMenuBarExtraVisible() {
        let ensure = { [weak self] in
            guard let self else { return }
            Self.repairMenuBarStatusItemDefaults()
            if !self.isMenuBarExtraInserted {
                self.logger.notice("🧭 Re-inserting MenuBarExtra into the system menu bar.")
                self.isMenuBarExtraInserted = true
            }
        }

        if Thread.isMainThread {
            ensure()
        } else {
            DispatchQueue.main.async(execute: ensure)
        }
    }

    /// SwiftUI's `MenuBarExtra` persists visibility/position under `NSStatusItem * Item-0`.
    /// On recent macOS builds the item can end up with `Visible=0` or an absurd preferred
    /// position (thousands of points), which hides it from the menu bar even though the
    /// process is running. Force it back into a sane visible state on launch.
    private static func repairMenuBarStatusItemDefaults(
        in defaults: UserDefaults = .standard
    ) {
        let visibleKey = "NSStatusItem Visible Item-0"
        let positionKey = "NSStatusItem Preferred Position Item-0"

        if defaults.object(forKey: visibleKey) as? Bool == false {
            defaults.set(true, forKey: visibleKey)
        }

        // Positions for real menu-bar slots are typically low hundreds; values in the
        // thousands usually mean the item was shoved into the overflow / off-screen.
        if let position = defaults.object(forKey: positionKey) as? Double, position > 2000 {
            defaults.removeObject(forKey: positionKey)
        } else if let position = defaults.object(forKey: positionKey) as? Int, position > 2000 {
            defaults.removeObject(forKey: positionKey)
        }
    }

    func configure(modelContainer: ModelContainer, engine: VoiceInkEngine) {
        self.modelContainer = modelContainer
        self.engine = engine
        logger.notice(
            "🧭 MenuBarManager configured. hasModelContainer=\((self.modelContainer != nil), privacy: .public); hasEngine=\((self.engine != nil), privacy: .public)"
        )
    }

    func toggleMenuBarOnly() {
        isMenuBarOnly.toggle()
    }

    func applyActivationPolicy(logPreferenceChange: Bool = false) {
        let changedPreferenceValue = isMenuBarOnly

        let applyPolicy = { [weak self] in
            guard let self else { return }
            if logPreferenceChange {
                self.logger.notice(
                    "🧭 Menu-bar-only preference changed. newValue=\(changedPreferenceValue, privacy: .public); activationPolicyBefore=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)"
                )
            }

            let didSet = NSApplication.shared.setActivationPolicy(self.configuredActivationPolicy)
            self.logger.notice(
                "🧭 Applied menu-bar activation policy. isMenuBarOnly=\(self.isMenuBarOnly, privacy: .public); desiredPolicy=\(WindowDiagnostics.activationPolicyDescription(self.configuredActivationPolicy), privacy: .public); success=\(didSet, privacy: .public); activationPolicyAfter=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public)"
            )

            // Always keep the tray icon inserted. Menu-bar-only mode has no Dock fallback,
            // and setActivationPolicy transitions can clear SwiftUI's MenuBarExtra.
            self.isMenuBarExtraInserted = true

            if self.isMenuBarOnly {
                WindowManager.shared.hideMainWindow()
            }
        }

        if Thread.isMainThread {
            applyPolicy()
        } else {
            DispatchQueue.main.async(execute: applyPolicy)
        }
    }

    func activateForPresentedWindow() {
        activateForPresentedWindow(reason: "Presented Window")
    }

    func activateForPresentedWindow(reason: String) {
        let activate = { [weak self] in
            guard let self else { return }
            self.logger.notice(
                "🧭 Full window presentation requested. reason=\(reason, privacy: .public); isMenuBarOnlyPreference=\(self.isMenuBarOnly, privacy: .public); activationPolicyBefore=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)"
            )
            AppPresentationPolicy.activateForUserFacingWindow(reason: reason)
        }

        if Thread.isMainThread {
            activate()
        } else {
            DispatchQueue.main.async(execute: activate)
        }
    }

    func openHistoryWindow() {
        guard let modelContainer = modelContainer,
            let engine = engine
        else {
            logger.error(
                "🧭 History window requested before MenuBarManager dependencies were configured. hasModelContainer=\((self.modelContainer != nil), privacy: .public); hasEngine=\((self.engine != nil), privacy: .public)"
            )
            return
        }

        let openWindow = { [weak self] in
            self?.logger.notice(
                "🧭 History window requested from menu bar. isMenuBarOnly=\(self?.isMenuBarOnly ?? false, privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)"
            )
            self?.activateForPresentedWindow(reason: "History")

            HistoryWindowController.shared.showHistoryWindow(
                modelContainer: modelContainer,
                engine: engine
            )
        }

        if Thread.isMainThread {
            openWindow()
        } else {
            DispatchQueue.main.async(execute: openWindow)
        }
    }
}
