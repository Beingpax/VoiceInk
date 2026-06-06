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
    private static let minimumClipboardRestoreDelay: TimeInterval = 0.15

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
            await performPasteSession(text)
        }
    }

    @MainActor
    static func pasteAtCursorAndWaitUntilPosted(_ text: String) async -> PasteResult {
        await startPasteAtCursor(text).value
    }

    @MainActor
    private static func performPasteSession(_ text: String) async -> PasteResult {
        if PasteMethod.current() == .directTyping {
            await typeTextDirectly(text)
            return .commandPosted
        }

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

        // Deep IDE/Cursor Output Routing Integration
        if let rawRoute = UserDefaults.standard.string(forKey: "IDERoutingMode"),
           let route = IDERoutingMode(rawValue: rawRoute),
           route != .activeApp {
            logger.notice("Routing output to IDE: \(route.displayName, privacy: .public)")
            if let bundleID = route.bundleIdentifier,
               let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                app.activate(options: [.activateIgnoringOtherApps])
                await wait(0.12)
            } else if let appName = route.appName {
                if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName?.localizedCaseInsensitiveContains(appName) == true }) {
                    app.activate(options: [.activateIgnoringOtherApps])
                    await wait(0.12)
                }
            }
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

    // MARK: - Paste then Auto Send

    /// Pastes text, then uses AX to detect when the paste has landed before sending the auto-send key.
    ///
    /// Strategy: snapshot the focused field's AXValue before pasting, then poll until it changes.
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
                    let currentValue = Self.getFocusedElementValue()
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

        guard result == .success,
              let element = focusedElement as? AXUIElement else { return nil }

        var value: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)

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
