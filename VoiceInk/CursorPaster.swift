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

    // "X – QWERTY ⌘" layouts remap to QWERTY when Command is held, so keystroke "v" resolves
    // the wrong key code. key code 9 (physical V) bypasses layout translation for those layouts.
    private static func makeScript(_ source: String) -> NSAppleScript? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return script
    }

    private static let pasteScriptKeystroke = makeScript("tell application \"System Events\" to keystroke \"v\" using command down")
    private static let pasteScriptKeyCode   = makeScript("tell application \"System Events\" to key code 9 using command down")

    private static var layoutSwitchesToQWERTYOnCommand: Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let nameRef = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return false }
        return (Unmanaged<CFString>.fromOpaque(nameRef).takeUnretainedValue() as String).hasSuffix("⌘")
    }

    private static func pasteUsingAppleScript() {
        let script = layoutSwitchesToQWERTYOnCommand ? pasteScriptKeyCode : pasteScriptKeystroke
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error = error {
            logger.error("AppleScript paste failed: \(error, privacy: .public)")
        }
    }

    // MARK: - CGEvent paste

    /// Paste from the clipboard using CGEvent, temporarily switching to a
    /// QWERTY-compatible input source when needed so that virtual key 0x09 is
    /// reliably interpreted as "V" for Cmd+V regardless of active layout
    /// (Dvorak, Colemak, etc.). QWERTY users are unaffected — the switch is
    /// skipped when the current layout is already QWERTY-compatible.
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
        let qwertySource = switchToQWERTYInputSource()
        logger.notice("Pasting: inputSource=\(currentID, privacy: .public), switched=\(qwertySource != nil)")

        // If we switched input sources, wait 30 ms for the system to apply it
        // before posting the CGEvents. Use asyncAfter so the main thread is not blocked.
        let eventDelay: TimeInterval = qwertySource != nil ? 0.03 : 0.0
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

            if let qwertySource {
                // Restore the original input source after a short delay so the
                // posted events are processed under ABC/US first. Only restore
                // if the source is still the QWERTY one we switched to — if the
                // user changed layouts in the meantime, leave their choice alone.
                let qwertyID = sourceID(for: qwertySource)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let nowSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                       sourceID(for: nowSource) == qwertyID {
                        TISSelectInputSource(currentSource)
                        logger.notice("Restored input source to \(currentID, privacy: .public)")
                    } else {
                        logger.notice("Input source changed during paste — skipping restore")
                    }
                }
            }
        }
    }

    /// Try to switch to ABC or US QWERTY. Returns the source switched to, or
    /// nil if the active layout is already QWERTY-compatible.
    private static func switchToQWERTYInputSource() -> TISInputSource? {
        guard let currentSourceRef = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        if let currentID = sourceID(for: currentSourceRef), isQWERTY(currentID) {
            return nil // already QWERTY, nothing to do
        }

        let criteria = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        guard let list = TISCreateInputSourceList(criteria, false)?.takeRetainedValue() as? [TISInputSource] else {
            logger.error("Failed to list input sources")
            return nil
        }

        for targetID in ["com.apple.keylayout.ABC", "com.apple.keylayout.US"] {
            if let match = list.first(where: { sourceID(for: $0) == targetID }) {
                let status = TISSelectInputSource(match)
                if status == noErr {
                    logger.notice("Switched input source to \(targetID, privacy: .public)")
                    return match
                } else {
                    logger.error("TISSelectInputSource failed with status \(status)")
                }
            }
        }

        logger.error("No QWERTY input source found to switch to")
        return nil
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
