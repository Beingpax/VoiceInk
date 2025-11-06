import SwiftUI
import AppKit

class MenuBarManager: ObservableObject {
    @Published var isMenuBarOnly: Bool {
        didSet {
            UserDefaults.standard.set(isMenuBarOnly, forKey: "IsMenuBarOnly")
            updateAppActivationPolicy()
        }
    }

    @Published var isMenuBarIconHidden: Bool {
        didSet {
            UserDefaults.standard.set(isMenuBarIconHidden, forKey: "IsMenuBarIconHidden")
            NotificationCenter.default.post(name: .init("MenuBarIconVisibilityChanged"), object: nil)
        }
    }

    init() {
        self.isMenuBarOnly = UserDefaults.standard.bool(forKey: "IsMenuBarOnly")
        self.isMenuBarIconHidden = UserDefaults.standard.bool(forKey: "IsMenuBarIconHidden")
        updateAppActivationPolicy()
    }

    func toggleMenuBarOnly() {
        isMenuBarOnly.toggle()
    }

    func toggleMenuBarIconVisibility() {
        isMenuBarIconHidden.toggle()
    }

    func applyActivationPolicy() {
        updateAppActivationPolicy()
    }

    func focusMainWindow() {
        applyActivationPolicy()
        DispatchQueue.main.async {
            if WindowManager.shared.showMainWindow() == nil {
                print("MenuBarManager: Unable to locate main window to focus")
            }
        }
    }

    private func updateAppActivationPolicy() {
        let applyPolicy = { [weak self] in
            guard let self else { return }
            let application = NSApplication.shared
            if self.isMenuBarOnly {
                application.setActivationPolicy(.accessory)
                WindowManager.shared.hideMainWindow()
            } else {
                application.setActivationPolicy(.regular)
                WindowManager.shared.showMainWindow()
            }
        }

        if Thread.isMainThread {
            applyPolicy()
        } else {
            DispatchQueue.main.async(execute: applyPolicy)
        }
    }

    func openMainWindowAndNavigate(to destination: String) {
        print("MenuBarManager: Navigating to \(destination)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.applyActivationPolicy()

            guard WindowManager.shared.showMainWindow() != nil else {
                print("MenuBarManager: Unable to show main window for navigation")
                return
            }

            // Post a notification to navigate to the desired destination
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(
                    name: .navigateToDestination,
                    object: nil,
                    userInfo: ["destination": destination]
                )
                print("MenuBarManager: Posted navigation notification for \(destination)")
            }
        }
    }
}
