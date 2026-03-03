import Foundation
import AppKit
import Carbon
import os

private let logger = Logger(subsystem: "com.VoiceInk", category: "CursorPaster")

class CursorPaster {

    static func pasteAtCursor(_ text: String) {
        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")

        var savedContents: [(NSPasteboard.PasteboardType, Data)] = []

        if shouldRestoreClipboard {
            let currentItems = pasteboard.pasteboardItems ?? []

            for item in currentItems {
                for type in item.types {
                    if let data = item.data(forType: type) {
                        savedContents.append((type, data))
                    }
                }
            }
        }

        ClipboardManager.setClipboard(text, transient: shouldRestoreClipboard)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if UserDefaults.standard.bool(forKey: "useAppleScriptPaste") {
                pasteUsingAppleScript()
            } else {
                pasteFromClipboard()
            }
        }

        if shouldRestoreClipboard {
            let restoreDelay = UserDefaults.standard.double(forKey: "clipboardRestoreDelay")
            let delay = max(restoreDelay, 0.25)

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if !savedContents.isEmpty {
                    pasteboard.clearContents()
                    for (type, data) in savedContents {
                        pasteboard.setData(data, forType: type)
                    }
                }
            }
        }
    }

    // MARK: - AppleScript paste

    // Pre-compiled AppleScript for pasting. Compiled once on first use to avoid per-paste overhead.
    private static let pasteScript: NSAppleScript? = {
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return script
    }()

    // Paste via AppleScript. Works with custom keyboard layouts (e.g. Neo2) where CGEvent-based paste fails.
    private static func pasteUsingAppleScript() {
        var error: NSDictionary?
        pasteScript?.executeAndReturnError(&error)
        if let error = error {
            logger.error("AppleScript paste failed: \(error, privacy: .public)")
        }
    }

    // MARK: - CGEvent paste

    // Paste via CGEvent, temporarily switching to a QWERTY input source so virtual key 0x09 maps to "V".
    private static func pasteFromClipboard() {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility not trusted — cannot paste")
            return
        }

        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            logger.error("TISCopyCurrentKeyboardInputSource returned nil")
            return
        }
        let currentID = sourceID(for: currentSource) ?? "unknown"
        let switched = switchToQWERTYInputSource()
        logger.notice("Pasting: inputSource=\(currentID, privacy: .public), switched=\(switched)")

        // If we switched input sources, wait 30 ms for the system to apply it
        // before posting the CGEvents.
        let eventDelay: TimeInterval = switched ? 0.03 : 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + eventDelay) {
            let source = CGEventSource(stateID: .privateState)

            let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
            let vDown   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            let vUp     = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            let cmdUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

            cmdDown?.flags = .maskCommand
            vDown?.flags   = .maskCommand
            vUp?.flags     = .maskCommand

            cmdDown?.post(tap: .cghidEventTap)
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
            cmdUp?.post(tap: .cghidEventTap)

            logger.notice("CGEvents posted for Cmd+V")

            if switched {
                // Restore the original input source after a short delay so the
                // posted events are processed under ABC/US first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    TISSelectInputSource(currentSource)
                    logger.notice("Restored input source to \(currentID, privacy: .public)")
                }
            }
        }
    }

    // Try to switch to ABC or US QWERTY. Returns true if the switch was made.
    private static func switchToQWERTYInputSource() -> Bool {
        guard let currentSourceRef = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return false }
        if let currentID = sourceID(for: currentSourceRef), isQWERTY(currentID) {
            return false // already QWERTY, nothing to do
        }

        let criteria = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        guard let list = TISCreateInputSourceList(criteria, false)?.takeRetainedValue() as? [TISInputSource] else {
            logger.error("Failed to list input sources")
            return false
        }

        // Prefer ABC, then US.
        let preferred = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]
        for targetID in preferred {
            if let match = list.first(where: { sourceID(for: $0) == targetID }) {
                let status = TISSelectInputSource(match)
                if status == noErr {
                    logger.notice("Switched input source to \(targetID, privacy: .public)")
                    return true
                } else {
                    logger.error("TISSelectInputSource failed with status \(status, privacy: .public)")
                }
            }
        }

        logger.error("No QWERTY input source found to switch to")
        return false
    }

    private static func sourceID(for source: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func isQWERTY(_ id: String) -> Bool {
        let qwertyIDs: Set<String> = [
            "com.apple.keylayout.ABC",
            "com.apple.keylayout.US",
            "com.apple.keylayout.USInternational-PC",
            "com.apple.keylayout.British",
            "com.apple.keylayout.Australian",
            "com.apple.keylayout.Canadian",
        ]
        return qwertyIDs.contains(id)
    }

    // MARK: - Enter key

    // Simulate pressing the Return/Enter key.
    static func pressEnter() {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .privateState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
    }
}
