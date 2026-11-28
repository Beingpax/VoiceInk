import AppKit
import ApplicationServices
import CoreGraphics

/// The macOS permission VoiceInk needs for its shortcuts and for pasting into other apps.
///
/// macOS 26 and earlier call it Accessibility, and macOS 27.0 to 27.2 call it Device Control
/// and Data Access. macOS 27.3 calls it System & App Protection Override and lets people limit
/// it to chosen apps. A limited grant still passes `AXIsProcessTrusted()`, but macOS drops the
/// keyboard events VoiceInk posts and its shortcut tap receives nothing, so on 27.3 and later
/// only full access counts as granted.
enum ControlPermission {
    enum Status: Equatable {
        case granted
        /// macOS 27.3 and later: the "Choose Apps" option instead of Override System Protections.
        case chosenAppsOnly
        case notGranted
    }

    static var status: Status {
        _ = trustedAtFirstCheck
        guard AXIsProcessTrusted() else { return .notGranted }
        guard usesProtectionOverride else { return .granted }
        // CGPreflightPostEventAccess() keeps the answer from its first call, so a grant made
        // while VoiceInk runs only shows up in the per-app check, which macOS answers each time.
        return isTrustedForAllApps || CGPreflightPostEventAccess() ? .granted : .chosenAppsOnly
    }

    /// macOS 27.3's per-app trust check: true only for Override System Protections, not Choose Apps.
    /// `kAXTrustedCheckOptionTargetBundleIdentifier` and `kAXTrustedCheckTargetAllApplications`
    /// aren't in the 27.2 SDK, so their values are used directly.
    private static var isTrustedForAllApps: Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionTargetBundleIdentifier": "*"] as CFDictionary)
    }

    private static let trustedAtFirstCheck = AXIsProcessTrusted()

    /// The permission changed while VoiceInk was running but still doesn't read as full access.
    /// Some of macOS's answers only refresh at launch, so a restart applies the change.
    static var mayNeedRestart: Bool {
        usesProtectionOverride && status != .granted && AXIsProcessTrusted() != trustedAtFirstCheck
    }

    static var isGranted: Bool {
        status == .granted
    }

    /// macOS 27.3 and later, where System Settings lists the permission as
    /// System & App Protection Override and no longer prompts for it.
    static var usesProtectionOverride: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 27, minorVersion: 3, patchVersion: 0))
    }

    /// The name System Settings shows for this permission on the running macOS.
    static var settingsName: String {
        if usesProtectionOverride {
            return String(localized: "System & App Protection Override")
        }
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
        {
            return String(localized: "Device Control and Data Access")
        }
        return String(localized: "Accessibility")
    }

    /// Step-by-step help for adding VoiceInk on macOS 27.3 and later, where macOS shows no prompt.
    struct SetupHelp {
        let title: String
        let steps: [String]
        let note: String
        /// Shown when VoiceInk was added with Choose Apps.
        let chosenAppsFix: String?
    }

    static var setupHelp: SetupHelp? {
        guard usesProtectionOverride else { return nil }
        return SetupHelp(
            title: String(localized: "How to allow VoiceInk"),
            steps: [
                String(localized: "Click Open Settings."),
                String(localized: "Scroll down, click +, and select VoiceInk."),
                String(localized: "Choose Override System Protections, not Choose Apps."),
                String(
                    localized:
                        "Click each OK, then Allow System & App Protection Override, and confirm with your password."),
            ],
            note: String(
                localized: "This is the same permission VoiceInk used before. macOS now shows it differently."),
            chosenAppsFix: status == .chosenAppsOnly
                ? String(
                    localized:
                        "Added with Choose Apps? Click ⓘ next to VoiceInk and turn on Control Your Entire Mac and All Apps."
                )
                : nil
        )
    }

    /// A short line under the permission row, or nil when nothing needs saying.
    static var statusNote: String? {
        status == .chosenAppsOnly ? String(localized: "VoiceInk needs full access to work properly.") : nil
    }

    /// Opens the right System Settings pane. The same link opens Accessibility,
    /// Device Control and Data Access, or System & App Protection Override.
    static func openSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Asks macOS to prompt, then opens System Settings. On macOS 27.3 the request shows no
    /// prompt and doesn't add VoiceInk to the list, so people add it with + themselves.
    static func requestAccess() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        AXIsProcessTrustedWithOptions(options)
        openSettings()
    }

    /// For diagnostics and system info.
    static var diagnosticValue: String {
        switch status {
        case .granted: return "granted"
        case .chosenAppsOnly: return "chosen-apps-only"
        case .notGranted: return "not-granted"
        }
    }
}
