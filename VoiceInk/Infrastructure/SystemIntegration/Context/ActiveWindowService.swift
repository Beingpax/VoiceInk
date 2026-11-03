import AppKit
import ApplicationServices
import Foundation
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

    @MainActor
    @discardableResult
    func beginApplyingConfiguration(
        modeId: UUID? = nil,
        shouldApply: @escaping @MainActor () -> Bool = { true }
    ) -> Task<Void, Never> {
        let diagnosticID = UUID().uuidString
        guard shouldApply() else {
            logger.notice("Mode detection id=\(diagnosticID, privacy: .public) result=skipped-inactive-request")
            return Task {}
        }

        if let modeId = modeId,
            let config = ModeManager.shared.getConfiguration(with: modeId)
        {
            ModeManager.shared.setActiveConfiguration(config)
            logger.notice("Mode detection id=\(diagnosticID, privacy: .public) result=explicit-mode mode=\(config.id.uuidString, privacy: .public) name=\(config.name, privacy: .private)")
            return Task {}
        }
        if let modeId {
            logger.notice("Mode detection id=\(diagnosticID, privacy: .public) requestedMode=\(modeId.uuidString, privacy: .public) result=missing-explicit-mode continuing=automatic-detection")
        }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
            let bundleIdentifier = frontmostApp.bundleIdentifier
        else {
            logger.notice("Mode detection id=\(diagnosticID, privacy: .public) result=no-frontmost-app-or-bundle-id")
            return Task {}
        }

        currentApplication = frontmostApp
        let processID = frontmostApp.processIdentifier
        logger.notice(
            "Mode detection id=\(diagnosticID, privacy: .public) app=\(bundleIdentifier, privacy: .public) name=\(frontmostApp.localizedName ?? "unknown", privacy: .private) pid=\(processID, privacy: .public)"
        )
        // Window metadata is diagnostic only and must not delay recording or prompt for permissions.
        DispatchQueue.global(qos: .utility).async {
            Self.logFocusedWindow(processID: processID, diagnosticID: diagnosticID)
        }
        ModeManager.shared.logTriggerRules(diagnosticID: diagnosticID)

        let appConfig = ModeManager.shared.getConfigurationForApp(bundleIdentifier, diagnosticID: diagnosticID)
        let quickConfig = appConfig ?? ModeManager.shared.getDefaultConfiguration()
        if let quickConfig {
            ModeManager.shared.setActiveConfiguration(quickConfig)
        }
        let source = appConfig != nil ? "app-rule" : (quickConfig != nil ? "default-mode" : "existing-effective-mode")
        let effectiveMode = ModeManager.shared.currentEffectiveConfiguration?.id.uuidString ?? "none"
        logger.notice("Mode detection id=\(diagnosticID, privacy: .public) stage=fallback source=\(source, privacy: .public) mode=\(effectiveMode, privacy: .public)")

        guard let browserType = BrowserType.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            logger.notice("Mode detection id=\(diagnosticID, privacy: .public) result=website-check-skipped reason=app-not-a-supported-browser")
            return Task {}
        }
        logger.notice("Mode detection id=\(diagnosticID, privacy: .public) stage=reading-browser-url browser=\(browserType.displayName, privacy: .public)")

        return Task { [weak self] in
            guard let self else { return }

            do {
                let currentURL = try await self.browserURLService.getCurrentURL(from: browserType)
                await MainActor.run {
                    guard shouldApply() else {
                        self.logger.notice("Mode detection id=\(diagnosticID, privacy: .public) result=discarded-browser-result reason=inactive-request")
                        return
                    }
                    self.logger.notice("Mode detection id=\(diagnosticID, privacy: .public) stage=browser-url-read url=\(currentURL, privacy: .private)")
                    guard let config = ModeManager.shared.getConfigurationForURL(currentURL, diagnosticID: diagnosticID) else {
                        let retainedMode = ModeManager.shared.currentEffectiveConfiguration?.id.uuidString ?? "none"
                        self.logger.notice("Mode detection id=\(diagnosticID, privacy: .public) result=no-website-match retainedMode=\(retainedMode, privacy: .public)")
                        return
                    }
                    ModeManager.shared.setActiveConfiguration(config)
                    self.logger.notice("Mode detection id=\(diagnosticID, privacy: .public) result=website-match mode=\(config.id.uuidString, privacy: .public) name=\(config.name, privacy: .private)")
                }
            } catch is CancellationError {
                self.logger.notice("Mode detection id=\(diagnosticID, privacy: .public) result=cancelled-browser-read")
            } catch {
                let reason = (error as? BrowserURLError).map { String(describing: $0) } ?? "unexpected-error"
                self.logger.error(
                    "Mode detection id=\(diagnosticID, privacy: .public) result=browser-url-failed browser=\(browserType.displayName, privacy: .public) reason=\(reason, privacy: .public) detail=\(String(describing: error), privacy: .private) fallback-retained=true")
            }
        }
    }

    /// Observed asynchronously after detection starts; it is not used to select a mode.
    private static func logFocusedWindow(processID: pid_t, diagnosticID: String) {
        let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "browser.detection")
        guard AXIsProcessTrusted() else {
            logger.notice("Mode window id=\(diagnosticID, privacy: .public) pid=\(processID, privacy: .public) result=unavailable reason=accessibility-not-trusted")
            return
        }
        let app = AXUIElementCreateApplication(processID)
        guard AXUIElementSetMessagingTimeout(app, 0.02) == .success else {
            logger.notice("Mode window id=\(diagnosticID, privacy: .public) result=unavailable reason=cannot-set-app-timeout")
            return
        }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            logger.notice("Mode window id=\(diagnosticID, privacy: .public) result=unavailable reason=focused-window-query axError=\(error.rawValue, privacy: .public)")
            return
        }
        let window = unsafeBitCast(value, to: AXUIElement.self)
        guard AXUIElementSetMessagingTimeout(window, 0.02) == .success else {
            logger.notice("Mode window id=\(diagnosticID, privacy: .public) result=unavailable reason=cannot-set-window-timeout")
            return
        }
        var title: CFTypeRef?
        let titleError = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
        logger.notice(
            "Mode window id=\(diagnosticID, privacy: .public) pid=\(processID, privacy: .public) result=focused-window-observed title=\((title as? String) ?? "unavailable", privacy: .private) titleAXError=\(titleError.rawValue, privacy: .public) timing=after-detection-start"
        )
    }

    func applyConfiguration(modeId: UUID? = nil) async {
        let task = await MainActor.run {
            beginApplyingConfiguration(modeId: modeId)
        }
        await task.value
    }
}
