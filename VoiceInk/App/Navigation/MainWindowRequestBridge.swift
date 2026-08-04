import AppKit
import OSLog
import SwiftUI

struct MainWindowRequestBridge: View {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MenuBarWindowFlow")

    @Environment(\.openWindow) private var openWindow
    let menuBarManager: MenuBarManager

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .showMainWindowRequested)) { _ in
                let existingWindow = WindowManager.shared.currentMainWindow()
                logger.notice(
                    "🧭 SwiftUI main-window request bridge received request. hasExistingMainWindow=\((existingWindow != nil), privacy: .public); menuBarOnly=\(self.menuBarManager.isMenuBarOnly, privacy: .public); activationPolicy=\(WindowDiagnostics.activationPolicyDescription(NSApplication.shared.activationPolicy()), privacy: .public); snapshot=\(WindowDiagnostics.windowSnapshot(), privacy: .public)"
                )

                if existingWindow == nil {
                    menuBarManager.activateForPresentedWindow(reason: "SwiftUIBridgeCreateMainWindow")
                    WindowManager.shared.prepareForUserRequestedMainWindow()
                    openWindow(id: AppWindowID.main)
                    logger.notice("🧭 SwiftUI bridge requested main window creation via openWindow.")
                } else {
                    menuBarManager.activateForPresentedWindow(reason: "SwiftUIBridgePresentMainWindow")
                    openWindow(id: AppWindowID.main)
                    WindowManager.shared.showMainWindow()
                    logger.notice("🧭 SwiftUI bridge requested existing main window presentation.")
                }
            }
    }
}
