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
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility not trusted — cannot paste")
            return
        }

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
    }

    // MARK: - Paste then Auto Send

    /// Pastes text, then uses AX to detect when the paste has landed before sending the auto-send key.
    ///
    /// Strategy: snapshot the focused field's AXValue before pasting, then poll until it changes.
    /// This works for any text length and doesn't depend on matching specific content.
    /// For apps where AXValue isn't readable (Electron, web), falls back to a short fixed delay.
    static func pasteAndAutoSend(_ text: String, autoSendKey: AutoSendKey) {
        let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
        let fullText = text + (appendSpace ? " " : "")

        guard autoSendKey.isEnabled else {
            pasteAtCursor(fullText)
            return
        }

        // Snapshot the field value BEFORE pasting
        let baselineValue = getFocusedElementValue()
        let canReadField = baselineValue != nil

        pasteAtCursor(fullText)

        Task.detached {
            if canReadField {
                // Strategy A: AX-based — poll until field value changes from baseline
                let maxWait: TimeInterval = 3.0
                let pollInterval: UInt64 = 50_000_000 // 50ms
                let startTime = Date()

                // Wait for paste keystroke to fire (pasteAtCursor has internal 50ms delay)
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

                while Date().timeIntervalSince(startTime) < maxWait {
                    let currentValue = await Self.getFocusedElementValue()
                    if currentValue != baselineValue {
                        // Field changed — paste landed
                        await MainActor.run { performAutoSend(autoSendKey) }
                        return
                    }
                    try? await Task.sleep(nanoseconds: pollInterval)
                }

                // Timeout — send anyway
                logger.warning("Auto-send: AX poll timed out, sending anyway")
                await MainActor.run { performAutoSend(autoSendKey) }
            } else {
                // Strategy B: fixed delay for apps where AXValue isn't readable
                // 300ms after paste keystroke (50ms internal + 250ms buffer)
                try? await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run { performAutoSend(autoSendKey) }
            }
        }
    }

    // MARK: - Accessibility Helpers

    /// Reads the AXValue of the currently focused UI element. Returns nil if not readable.
    private static func getFocusedElementValue() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, let element = focusedElement else { return nil }

        var value: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXValueAttribute as CFString, &value)

        guard valueResult == .success, let stringValue = value as? String else { return nil }
        return stringValue
    }

    // MARK: - Auto Send Keys

    static func performAutoSend(_ key: AutoSendKey) {
        guard key.isEnabled else { return }
        guard AXIsProcessTrusted() else { return }

        let source = CGEventSource(stateID: .privateState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)

        switch key {
        case .none: return
        case .enter: break
        case .shiftEnter:
            enterDown?.flags = .maskShift
            enterUp?.flags   = .maskShift
        case .commandEnter:
            enterDown?.flags = .maskCommand
            enterUp?.flags   = .maskCommand
        }

        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
    }
}
