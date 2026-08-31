import AppKit
import SwiftData
import SwiftUI

class MenuBarManager: ObservableObject {
    @Published var isMenuBarOnly: Bool {
        didSet {
            UserDefaults.standard.set(isMenuBarOnly, forKey: "IsMenuBarOnly")
            applyActivationPolicy()
        }
    }

    private var modelContainer: ModelContainer?
    private var engine: VoiceInkEngine?
    private var configuredActivationPolicy: NSApplication.ActivationPolicy {
        isMenuBarOnly ? .accessory : .regular
    }

    init() {
        self.isMenuBarOnly = UserDefaults.standard.bool(forKey: "IsMenuBarOnly")
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
            window.styleMask.contains(.titled)
        else {
            return
        }

        AppPresentationPolicy.restoreAccessoryIfNeededAfterUserFacingWindowClosed()
    }

    func configure(modelContainer: ModelContainer, engine: VoiceInkEngine) {
        self.modelContainer = modelContainer
        self.engine = engine
    }

    func toggleMenuBarOnly() {
        isMenuBarOnly.toggle()
    }

    func applyActivationPolicy() {
        let applyPolicy = { [weak self] in
            guard let self else { return }

            NSApplication.shared.setActivationPolicy(self.configuredActivationPolicy)

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
        let activate = {
            AppPresentationPolicy.activateForUserFacingWindow()
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
            return
        }

        let openWindow = { [weak self] in
            self?.activateForPresentedWindow()

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
