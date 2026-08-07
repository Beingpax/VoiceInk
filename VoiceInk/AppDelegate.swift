import Cocoa
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {
    weak var menuBarManager: MenuBarManager?
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchedAsLoginItem = Self.isLoginItemLaunch(NSAppleEventManager.shared().currentAppleEvent)

        guard !launchedAsLoginItem, Self.areBothIconsHidden else { return }
        AppPresentationPolicy.activateForUserFacingWindow()
        WindowManager.shared.prepareForUserRequestedMainWindow()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !launchedAsLoginItem, Self.areBothIconsHidden else {
            menuBarManager?.applyActivationPolicy()
            return
        }

        menuBarManager?.activateForPresentedWindow()
        if WindowManager.shared.showMainWindow() == nil {
            WindowManager.shared.prepareForUserRequestedMainWindow()
        }
    }

    private static func isLoginItemLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        return event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    private static var areBothIconsHidden: Bool {
        let defaults = UserDefaults.standard
        return AppIconVisibility(
            isDockIconHidden: defaults.bool(forKey: AppPreferenceKey.isMenuBarOnly),
            isMenuBarIconHidden: !defaults.bool(forKey: AppPreferenceKey.showMenuBarIcon)
        ).areBothIconsHidden
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if WindowManager.shared.currentMainWindow() != nil {
            WindowManager.shared.showMainWindow()
            return false
        }

        WindowManager.shared.prepareForUserRequestedMainWindow()
        NotificationCenter.default.post(name: .showMainWindowRequested, object: nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // Stash URL when app cold-starts to avoid spawning a new window/tab
    var pendingOpenFileURL: URL?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { SupportedMedia.isSupported(url: $0) }) else {
            return
        }

        if let menuBarManager {
            menuBarManager.activateForPresentedWindow()
        } else {
            AppPresentationPolicy.activateForUserFacingWindow()
        }

        if WindowManager.shared.currentMainWindow() == nil {
            // Cold start: do NOT create a window here to avoid extra window/tab.
            // Defer to SwiftUI's main window scene and let ContentView process this later.
            pendingOpenFileURL = url
            WindowManager.shared.prepareForUserRequestedMainWindow()
            NotificationCenter.default.post(name: .showMainWindowRequested, object: nil)
        } else {
            // Running: focus current window and route in-place to Transcribe Audio
            WindowManager.shared.showMainWindow()
            NotificationCenter.default.post(
                name: .navigateToDestination, object: nil, userInfo: ["destination": "Transcribe Audio"])
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openFileForTranscription, object: nil, userInfo: ["url": url])
            }
        }
    }
}
