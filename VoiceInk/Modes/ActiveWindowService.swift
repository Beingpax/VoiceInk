import Foundation
import AppKit
import os

class ActiveWindowService: ObservableObject {
    static let shared = ActiveWindowService()
    @Published var currentApplication: NSRunningApplication?
    private let browserURLService = BrowserURLService.shared

    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "browser.detection"
    )

    private init() {}
    
    func applyConfiguration(modeId: UUID? = nil) async {
        if let modeId = modeId,
           let config = ModeManager.shared.getConfiguration(with: modeId) {
            await MainActor.run {
                ModeManager.shared.setActiveConfiguration(config)
            }
            return
        }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmostApp.bundleIdentifier else {
            return
        }

        await MainActor.run {
            currentApplication = frontmostApp
        }

        var configToApply: ModeConfig?

        if let browserType = BrowserType.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            do {
                let currentURL = try await browserURLService.getCurrentURL(from: browserType)
                if let config = ModeManager.shared.getConfigurationForURL(currentURL) {
                    configToApply = config
                }
            } catch {
                logger.error("❌ Failed to get URL from \(browserType.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if configToApply == nil {
            configToApply = ModeManager.shared.getConfigurationForApp(bundleIdentifier)
        }

        if configToApply == nil {
            configToApply = ModeManager.shared.getDefaultConfiguration()
        }

        if let config = configToApply {
            await MainActor.run {
                ModeManager.shared.setActiveConfiguration(config)
            }
        }
    }
} 
