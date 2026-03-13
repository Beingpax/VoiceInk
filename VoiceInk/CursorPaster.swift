import Foundation
import AppKit
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

        // Only restore the clipboard after pasting if we can actually paste.
        // When accessibility isn't granted, paste will fail silently — in that
        // case, keep the transcribed text on the clipboard so the user can
        // manually Cmd+V instead of having it wiped by the restore timer.
        let canPaste = AXIsProcessTrusted()
        let effectiveRestore = shouldRestoreClipboard && canPaste

        let useAppleScript = UserDefaults.standard.bool(forKey: "useAppleScriptPaste")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if useAppleScript {
                pasteUsingAppleScript()
            } else {
                pasteFromClipboard()
            }
        }

        if effectiveRestore {
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

    // Pre-compiled once on first use to avoid per-paste overhead.
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

    // Posts Cmd+V via CGEvent without modifying the active input source.
    private static func pasteFromClipboard() {
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

        // If accessibility isn't granted, CGEvent paste may fail silently.
        // Try AppleScript as a fallback — it uses a different permission model
        // (Automation) that may succeed where CGEvent doesn't.
        if !AXIsProcessTrusted() {
            pasteUsingAppleScript()
        }
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
