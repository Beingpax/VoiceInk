import SwiftUI
import SwiftData
import AppKit
import OSLog

class MenuBarManager: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MenuBarWindowFlow")

    @Published var isMenuBarOnly: Bool {
        didSet {
            UserDefaults.standard.set(isMenuBarOnly, forKey: "IsMenuBarOnly")
            applyActivationPolicy(logPreferenceChange: true)
        }
    }

    private var modelContainer: ModelContainer?
    private var engine: VoiceInkEngine?
    private var configuredActivationPolicy: NSApplication.ActivationPolicy {
        isMenuBarOnly ? .accessory : .regular
    }

    init() {
        self.isMenuBarOnly = UserDefaults.standard.bool(forKey: "IsMenuBarOnly")
        logger.notice("🧭 MenuBarManager initialized. isMenuBarOnly=\(self.isMenuBarOnly, privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public)")
        applyActivationPolicy()

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
              window.styleMask.contains(.titled) else {
            return
        }

        AppPresentationPolicy.restoreAccessoryIfNeededAfterUserFacingWindowClosed(
            reason: "userFacingWindowWillClose"
        )
    }

    func configure(modelContainer: ModelContainer, engine: VoiceInkEngine) {
        self.modelContainer = modelContainer
        self.engine = engine
        logger.notice("🧭 MenuBarManager configured. hasModelContainer=\((self.modelContainer != nil), privacy: .public); hasEngine=\((self.engine != nil), privacy: .public)")
    }
    
    func toggleMenuBarOnly() {
        isMenuBarOnly.toggle()
    }
    
    func applyActivationPolicy(logPreferenceChange: Bool = false) {
        let changedPreferenceValue = isMenuBarOnly

        let applyPolicy = { [weak self] in
            guard let self else { return }
            if logPreferenceChange {
                self.logger.notice("🧭 Menu-bar-only preference changed. newValue=\(changedPreferenceValue, privacy: .public); activationPolicyBefore=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)")
            }

            let didSet = NSApplication.shared.setActivationPolicy(self.configuredActivationPolicy)
            self.logger.notice("🧭 Applied menu-bar activation policy. isMenuBarOnly=\(self.isMenuBarOnly, privacy: .public); desiredPolicy=\(WindowDiagnostics.activationPolicyDescription(self.configuredActivationPolicy), privacy: .public); success=\(didSet, privacy: .public); activationPolicyAfter=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public)")

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
            self.logger.notice("🧭 Full window presentation requested. reason=\(reason, privacy: .public); isMenuBarOnlyPreference=\(self.isMenuBarOnly, privacy: .public); activationPolicyBefore=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)")
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
              let engine = engine else {
            logger.error("🧭 History window requested before MenuBarManager dependencies were configured. hasModelContainer=\((self.modelContainer != nil), privacy: .public); hasEngine=\((self.engine != nil), privacy: .public)")
            return
        }

        let openWindow = { [weak self] in
            self?.logger.notice("🧭 History window requested from menu bar. isMenuBarOnly=\(self?.isMenuBarOnly ?? false, privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)")
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
