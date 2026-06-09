import Foundation
import AppKit
import Carbon
import os

class CursorPaster {
    private typealias ClipboardItemSnapshot = [(NSPasteboard.PasteboardType, Data)]
    private typealias ClipboardSnapshot = [ClipboardItemSnapshot]
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CursorPaster")

    enum PasteResult: Equatable {
        case commandPosted
        case commandNotPosted

        var didPostPasteCommand: Bool {
            self == .commandPosted
        }
    }

    private static let prePasteDelay: TimeInterval = 0.10
    private static let pasteShortcutEventDelay: TimeInterval = 0.01
    private static let minimumClipboardRestoreDelay: TimeInterval = 0.25

    static func pasteAtCursor(_ text: String) {
        Task {
            let pasteTask = await MainActor.run {
                startPasteAtCursor(text)
            }
            _ = await pasteTask.value
        }
    }

    @MainActor
    @discardableResult
    static func startPasteAtCursor(_ text: String) -> Task<PasteResult, Never> {
        Task { @MainActor in
            if PasteMethod.current() == .directTyping {
                return await typeTextDirectly(text)
            }
            return await performPasteSession(text)
        }
    }

    @MainActor
    static func pasteAtCursorAndWaitUntilPosted(_ text: String) async -> PasteResult {
        await startPasteAtCursor(text).value
    }

    @MainActor
    private static func performPasteSession(_ text: String) async -> PasteResult {
        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")
        let savedContents = shouldRestoreClipboard ? snapshotClipboard(from: pasteboard) : []
        let sessionID = UUID().uuidString

        guard ClipboardManager.setClipboard(
            text,
            transient: shouldRestoreClipboard,
            sessionID: shouldRestoreClipboard ? sessionID : nil
        ) else {
            logger.error("Failed to prepare clipboard for paste")
            return .commandNotPosted
        }

        await wait(prePasteDelay)

        let pasteResult = await postPasteCommand()
        if shouldRestoreClipboard {
            scheduleClipboardRestore(
                savedContents,
                expectedText: text,
                sessionID: sessionID,
                on: pasteboard
            )
        }

        return pasteResult
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

    @MainActor
    private static func postPasteCommand() async -> PasteResult {
        if PasteMethod.current() == .appleScript {
            return pasteUsingAppleScript() ? .commandPosted : .commandNotPosted
        } else {
            return await pasteFromClipboard()
        }
    }

    private static func scheduleClipboardRestore(
        _ savedContents: ClipboardSnapshot,
        expectedText: String,
        sessionID: String,
        on pasteboard: NSPasteboard
    ) {
        let delay = max(
            UserDefaults.standard.double(forKey: "clipboardRestoreDelay"),
            minimumClipboardRestoreDelay
        )

        Task { @MainActor in
            await wait(delay)
            guard pasteboardStillOwnedByPasteSession(pasteboard, expectedText: expectedText, sessionID: sessionID) else {
                return
            }
            pasteboard.clearContents()
            if !savedContents.isEmpty {
                pasteboard.writeObjects(pasteboardItems(from: savedContents))
            }
        }
    }

    private static func pasteboardStillOwnedByPasteSession(
        _ pasteboard: NSPasteboard,
        expectedText: String,
        sessionID: String
    ) -> Bool {
        pasteboard.string(forType: .string) == expectedText &&
            pasteboard.string(forType: ClipboardManager.pasteSessionType) == sessionID
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

    @MainActor
    private static var layoutSwitchesToQWERTYOnCommand: Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let nameRef = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return false }
        return (Unmanaged<CFString>.fromOpaque(nameRef).takeUnretainedValue() as String).hasSuffix("⌘")
    }

    @MainActor
    private static func pasteUsingAppleScript() -> Bool {
        guard let script = layoutSwitchesToQWERTYOnCommand ? pasteScriptKeyCode : pasteScriptKeystroke else {
            logger.error("AppleScript paste script is unavailable")
            return false
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            logger.error("AppleScript paste failed: \(String(describing: error), privacy: .public)")
        }
        return error == nil
    }

    // MARK: - CGEvent paste

    // Posts Cmd+V via CGEvent without modifying the active input source.
    @MainActor
    private static func pasteFromClipboard() async -> PasteResult {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility permission is required to paste with simulated key events")
            return .commandNotPosted
        }

        let source = CGEventSource(stateID: .privateState)

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            logger.error("Failed to create Cmd+V keyboard events")
            return .commandNotPosted
        }

        cmdDown.flags = .maskCommand
        vDown.flags   = .maskCommand
        vUp.flags     = .maskCommand

        cmdDown.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        vDown.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        vUp.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        cmdUp.post(tap: .cghidEventTap)

        return .commandPosted
    }

    private static func wait(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    // MARK: - Direct Typing (for Remote Desktop / virtual machine sessions)

    // A character that can be produced by pressing one key, optionally with Shift.
    private struct KeyStroke {
        let keyCode: CGKeyCode
        let shift: Bool
    }

    private static let directTypingInterKeyDelay: UInt64 = 5_000_000

    // Remote-desktop clients (e.g. Microsoft Remote Desktop) ignore the Unicode
    // payload attached via keyboardSetUnicodeString and instead forward the
    // virtual key code / scancode to the guest OS. Posting every character with
    // virtualKey 0 therefore typed the physical 'A' key for every character on
    // the remote side. To type correctly we resolve each character to its real
    // virtual key code (plus Shift) for the active keyboard layout and post those
    // hardware-style events. Characters that can't be produced that way fall back
    // to Unicode injection, which still works for local apps.
    @MainActor
    private static func typeTextDirectly(_ text: String) async -> PasteResult {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility permission is required to type text directly")
            return .commandNotPosted
        }

        guard let source = CGEventSource(stateID: .privateState) else {
            logger.error("Failed to create event source for direct typing")
            return .commandNotPosted
        }

        // Give the recorder UI time to dismiss and hand focus back before the
        // first character. Some apps/remote-desktop clients drop the first event
        // if typing starts while focus is still settling.
        await wait(prePasteDelay)

        let keyStrokeMap = buildKeyStrokeMap()

        for character in text {
            if let keyStroke = keyStroke(for: character, in: keyStrokeMap) {
                postKeyStroke(keyStroke, source: source)
            } else {
                // Emoji, accented dead-key characters, etc. that aren't reachable
                // with a single key on the current layout. Best-effort: works for
                // local apps, may be dropped by remote-desktop sessions.
                postUnicodeCharacter(character, source: source)
            }

            try? await Task.sleep(nanoseconds: directTypingInterKeyDelay)
        }

        return .commandPosted
    }

    private static func keyStroke(for character: Character, in map: [Character: KeyStroke]) -> KeyStroke? {
        switch character {
        case "\n", "\r":
            // Use Shift+Return rather than a bare Return. A plain Return is
            // treated as "send" by many chat apps (Slack, Teams, Messages),
            // which would submit the message at an embedded line break. Shift+
            // Return is the near-universal "insert a line break, don't submit"
            // convention and still inserts a newline in editors. Intentional
            // submission is handled separately by the Auto Send feature.
            return KeyStroke(keyCode: CGKeyCode(kVK_Return), shift: true)
        case "\t":
            return KeyStroke(keyCode: CGKeyCode(kVK_Tab), shift: false)
        default:
            return map[character]
        }
    }

    @MainActor
    private static func postKeyStroke(_ keyStroke: KeyStroke, source: CGEventSource?) {
        let flags: CGEventFlags = keyStroke.shift ? .maskShift : []

        // Press Shift as a real key so the remote session updates its modifier
        // state; merely setting the flag on the character event is not enough.
        if keyStroke.shift {
            let shiftDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Shift), keyDown: true)
            shiftDown?.flags = .maskShift
            shiftDown?.post(tap: .cghidEventTap)
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyStroke.keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyStroke.keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.post(tap: .cghidEventTap)

        // Always release Shift if it was pressed so it never sticks on the remote side.
        if keyStroke.shift {
            let shiftUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)
            shiftUp?.flags = []
            shiftUp?.post(tap: .cghidEventTap)
        }
    }

    @MainActor
    private static func postUnicodeCharacter(_ character: Character, source: CGEventSource?) {
        var utf16Units = Array(String(character).utf16)
        guard !utf16Units.isEmpty,
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return
        }

        keyDown.keyboardSetUnicodeString(stringLength: utf16Units.count, unicodeString: &utf16Units)
        keyDown.post(tap: .cghidEventTap)
        keyUp.keyboardSetUnicodeString(stringLength: utf16Units.count, unicodeString: &utf16Units)
        keyUp.post(tap: .cghidEventTap)
    }

    // Builds a character -> key code map for the active keyboard layout. Only the
    // unmodified and Shift variants are considered: Option/AltGr characters are
    // intentionally excluded because remote-desktop clients map Option to the
    // Windows Alt key, which can open menus or produce the wrong character.
    @MainActor
    private static func buildKeyStrokeMap() -> [Character: KeyStroke] {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            logger.error("Direct typing could not read the current keyboard layout")
            return [:]
        }

        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        guard let layoutBytes = CFDataGetBytePtr(layoutData) else {
            return [:]
        }

        let keyboardType = UInt32(LMGetKbdType())
        // modifierKeyState for UCKeyTranslate is the Carbon modifier mask shifted
        // right by 8, so Shift (0x0200) becomes 0x02.
        let modifierVariants: [(state: UInt32, shift: Bool)] = [
            (0x00, false),
            (0x02, true)
        ]

        var map: [Character: KeyStroke] = [:]

        for keyCode in 0..<UInt16(128) {
            for variant in modifierVariants {
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0

                let status = layoutBytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { keyboardLayout in
                    UCKeyTranslate(
                        keyboardLayout,
                        keyCode,
                        UInt16(kUCKeyActionDown),
                        variant.state,
                        keyboardType,
                        UInt32(kUCKeyTranslateNoDeadKeysMask),
                        &deadKeyState,
                        chars.count,
                        &length,
                        &chars
                    )
                }

                guard status == noErr, length > 0 else { continue }

                let produced = String(utf16CodeUnits: chars, count: length)
                guard produced.count == 1, let character = produced.first,
                      !character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    continue
                }

                if map[character] == nil {
                    map[character] = KeyStroke(keyCode: CGKeyCode(keyCode), shift: variant.shift)
                }
            }
        }

        return map
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
