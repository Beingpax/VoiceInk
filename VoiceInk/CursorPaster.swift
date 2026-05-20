import Foundation
import AppKit
import Carbon
import os

private let logger = Logger(subsystem: "com.VoiceInk", category: "CursorPaster")

enum PasteMethod: String, CaseIterable {
    case cgEvent      = "cgEvent"
    case appleScript  = "appleScript"
    case directTyping = "directTyping"

    static var current: PasteMethod {
        let raw = UserDefaults.standard.string(forKey: "pasteMethod") ?? "cgEvent"
        return PasteMethod(rawValue: raw) ?? .cgEvent
    }

    var displayName: String {
        switch self {
        case .cgEvent:      return "Standard (CGEvent)"
        case .appleScript:  return "AppleScript"
        case .directTyping: return "Direct Typing (Remote Desktop)"
        }
    }
}

class CursorPaster {
    private typealias ClipboardItemSnapshot = [(NSPasteboard.PasteboardType, Data)]
    private typealias ClipboardSnapshot = [ClipboardItemSnapshot]

    static func pasteAtCursor(_ text: String) {
        Task {
            await MainActor.run {
                startPasteAtCursor(text)
            }.value
        }
    }

    @MainActor
    @discardableResult
    static func startPasteAtCursor(_ text: String) -> Task<Void, Never> {
        if PasteMethod.current == .directTyping {
            return Task { @MainActor in
                await typeTextDirectly(text)
            }
        }

        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")
        let savedContents = shouldRestoreClipboard ? snapshotClipboard(from: pasteboard) : []

        _ = ClipboardManager.setClipboard(text, transient: shouldRestoreClipboard)
        postPasteCommand()

        if shouldRestoreClipboard {
            scheduleClipboardRestore(savedContents, on: pasteboard)
        }

        return Task { @MainActor in }
    }

    @MainActor
    static func pasteAtCursorAndWaitUntilPosted(_ text: String) async {
        await startPasteAtCursor(text).value
    }

    private static func snapshotClipboard(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                if let data = item.data(forType: type) {
                    return (type, data)
                }
                return nil
            }
        }
    }

    private static func postPasteCommand() {
        switch PasteMethod.current {
        case .appleScript:  pasteUsingAppleScript()
        case .cgEvent, .directTyping: pasteFromClipboard()
        }
    }

    private static func scheduleClipboardRestore(_ savedContents: ClipboardSnapshot, on pasteboard: NSPasteboard) {
        let restoreDelay = UserDefaults.standard.double(forKey: "clipboardRestoreDelay")
        let delay = max(restoreDelay, 0.25)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            pasteboard.clearContents()
            if !savedContents.isEmpty {
                pasteboard.writeObjects(pasteboardItems(from: savedContents))
            }
        }
    }

    private static func pasteboardItems(from snapshot: ClipboardSnapshot) -> [NSPasteboardItem] {
        snapshot.map { itemSnapshot in
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot {
                item.setData(data, forType: type)
            }
            return item
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

    // MARK: - Direct Typing (for Remote Desktop / virtual machine sessions)

    // Types text character-by-character via CGEvent instead of using clipboard paste.
    // Remote desktop clients forward individual keystrokes to the remote machine, so
    // this bypasses the Mac↔Windows clipboard sync problem entirely.
    @MainActor
    private static func typeTextDirectly(_ text: String) async {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility not trusted — cannot type text directly")
            return
        }

        let source = CGEventSource(stateID: .privateState)
        // Give the recorder UI time to dismiss and hand focus back before the
        // first character. Some apps/remote-desktop clients drop the first event
        // if typing starts while focus is still settling.
        try? await Task.sleep(nanoseconds: 100_000_000)

        // 5 ms between key-pairs: enough for RD clients to queue and forward each
        // keystroke without dropping characters, fast enough for normal usage.
        let interKeyDelay: UInt64 = 5_000_000

        for scalar in text.unicodeScalars {
            // Represent each Unicode scalar as a UTF-16 code unit sequence so that
            // characters outside the BMP (e.g. emoji) are encoded as surrogate pairs.
            var utf16Units = Array(String(scalar).utf16)

            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            keyDown?.keyboardSetUnicodeString(stringLength: utf16Units.count, unicodeString: &utf16Units)
            keyDown?.post(tap: .cghidEventTap)

            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyUp?.keyboardSetUnicodeString(stringLength: utf16Units.count, unicodeString: &utf16Units)
            keyUp?.post(tap: .cghidEventTap)

            try? await Task.sleep(nanoseconds: interKeyDelay)
        }

        logger.notice("Direct-typed \(text.unicodeScalars.count) characters")
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
