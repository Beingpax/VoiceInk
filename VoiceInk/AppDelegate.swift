import Cocoa
import SwiftUI
import UniformTypeIdentifiers
import OSLog

class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MenuBarWindowFlow")

    weak var menuBarManager: MenuBarManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.notice("🧭 Application finished launching. hasMenuBarManager=\((self.menuBarManager != nil), privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)")
        menuBarManager?.applyActivationPolicy()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        logger.notice("🧭 Dock/app reopen requested. hasVisibleWindowsFlag=\(flag, privacy: .public); isMenuBarOnly=\(self.menuBarManager?.isMenuBarOnly ?? UserDefaults.standard.bool(forKey: "IsMenuBarOnly"), privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(sender.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)")

        if let menuBarManager, !menuBarManager.isMenuBarOnly {
            if WindowManager.shared.currentMainWindow() != nil {
                WindowManager.shared.showMainWindow()
                logger.notice("🧭 Dock/app reopen presented the existing main window.")
                return false
            }

            WindowManager.shared.prepareForUserRequestedMainWindow()
            NotificationCenter.default.post(name: .showMainWindowRequested, object: nil)
            logger.notice("🧭 Dock/app reopen requested main window creation through SwiftUI.")
            return false
        }

        logger.notice("🧭 Dock/app reopen left to default handling.")
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // Stash URL when app cold-starts to avoid spawning a new window/tab
    var pendingOpenFileURL: URL?
    
    func application(_ application: NSApplication, open urls: [URL]) {
        logger.notice("🧭 Application received open-URLs request. urlCount=\(urls.count, privacy: .public); hasCurrentMainWindow=\((WindowManager.shared.currentMainWindow() != nil), privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(application.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)")

        guard let url = urls.first(where: { SupportedMedia.isSupported(url: $0) }) else {
            logger.notice("🧭 Open-URLs request ignored because no supported media URL was found.")
            return
        }
        
        if let menuBarManager {
            menuBarManager.activateForPresentedWindow(reason: "OpenMediaFile")
        } else {
            AppPresentationPolicy.activateForUserFacingWindow(reason: "OpenMediaFileWithoutMenuBarManager")
        }
        
        if WindowManager.shared.currentMainWindow() == nil {
            // Cold start: do NOT create a window here to avoid extra window/tab.
            // Defer to SwiftUI's main window scene and let ContentView process this later.
            pendingOpenFileURL = url
            WindowManager.shared.prepareForUserRequestedMainWindow()
            logger.notice("🧭 Stored pending media URL and requested SwiftUI main window. urlLastPath=\(url.lastPathComponent, privacy: .private(mask: .hash))")
            NotificationCenter.default.post(name: .showMainWindowRequested, object: nil)
        } else {
            // Running: focus current window and route in-place to Transcribe Audio
            logger.notice("🧭 Routing media URL to existing main window. urlLastPath=\(url.lastPathComponent, privacy: .private(mask: .hash))")
            WindowManager.shared.showMainWindow()
            NotificationCenter.default.post(name: .navigateToDestination, object: nil, userInfo: ["destination": "Transcribe Audio"])
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openFileForTranscription, object: nil, userInfo: ["url": url])
            }
        }
    }
}
