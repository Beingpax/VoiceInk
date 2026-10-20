import AppKit
import Carbon
import Foundation
import os

class CursorPaster {
    private typealias ClipboardItemSnapshot = [(NSPasteboard.PasteboardType, Data)]
    private typealias ClipboardSnapshot = [ClipboardItemSnapshot]
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CursorPaster")

    enum PasteResult: Equatable {
        case commandPosted
        case commandNotPosted
        case commandPartiallyPosted

        var didPostPasteCommand: Bool {
            self == .commandPosted
        }
    }

    struct PasteOutcome {
        let result: PasteResult
        let autoLearnGeneration: UInt64?
    }

    private static let prePasteDelay: TimeInterval = 0.20
    private static let pasteShortcutEventDelay: TimeInterval = 0.01
    private static let minimumClipboardRestoreDelay: TimeInterval = 0.25

    @MainActor
    private static var pasteQueueTask: Task<Void, Never>?

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
    static func startPasteAtCursor(_ text: String) -> Task<PasteOutcome, Never> {
        let requestedAt = ProcessInfo.processInfo.systemUptime
        let previousPasteTask = pasteQueueTask
        let sessionTask = Task { @MainActor in
            await previousPasteTask?.value
            return await performPasteSession(text, requestedAt: requestedAt)
        }

        pasteQueueTask = Task { @MainActor in
            let session = await sessionTask.value
            await session.clipboardRestoreTask?.value
        }

        return Task { @MainActor in
            let session = await sessionTask.value
            return session.outcome
        }
    }

    @MainActor
    private static func performPasteSession(_ text: String, requestedAt: TimeInterval) async -> (
        outcome: PasteOutcome, clipboardRestoreTask: Task<Void, Never>?
    ) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let queueWaitMs = elapsedMilliseconds(since: requestedAt)
        let sessionID = UUID().uuidString
        let method = PasteMethod.current()
        let textToDeliver = method == .directTyping ? DirectTextTyper.normalizedText(text) : text
        let pasteboard: NSPasteboard? = method.usesClipboard ? NSPasteboard.general : nil
        let shouldRestoreClipboard = pasteboard != nil
            && UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")
        let savedContents: ClipboardSnapshot
        if let pasteboard {
            savedContents = shouldRestoreClipboard ? snapshotClipboard(from: pasteboard) : []

            guard
                ClipboardManager.setClipboard(
                    textToDeliver,
                    transient: shouldRestoreClipboard,
                    sessionID: shouldRestoreClipboard ? sessionID : nil
                )
            else {
                logger.error("Failed to prepare clipboard for paste id=\(sessionID, privacy: .public)")
                return (PasteOutcome(result: .commandNotPosted, autoLearnGeneration: nil), nil)
            }

            await wait(prePasteDelay)
        } else {
            savedContents = []
        }

        let application = NSWorkspace.shared.frontmostApplication
        let appIdentifier = application?.bundleIdentifier ?? "unknown"
        let focusDiagnostics = PasteFocusDiagnostics(sessionID: sessionID)
        focusDiagnostics.captureAroundPaste(processID: application?.processIdentifier, appIdentifier: appIdentifier)
        let pasteResult = await deliverText(textToDeliver, method: method, sessionID: sessionID)
        focusDiagnostics.captureAfterPaste(
            commandPosted: pasteResult.didPostPasteCommand,
            commandProcessID: application?.processIdentifier
        )
        logger.notice(
            "Paste id=\(sessionID, privacy: .public) app=\(appIdentifier, privacy: .public) method=\(method.rawValue, privacy: .public) commandPosted=\(pasteResult.didPostPasteCommand, privacy: .public) queueMs=\(queueWaitMs, privacy: .public) elapsedMs=\(elapsedMilliseconds(since: startedAt), privacy: .public)"
        )
        let autoLearnGeneration: UInt64?
        if AutoLearnSettings.isEnabled {
            autoLearnGeneration = await AutoLearnService.shared.pasteDidFinish(
                text: textToDeliver,
                processID: application?.processIdentifier,
                commandPosted: pasteResult.didPostPasteCommand
            )
        } else {
            autoLearnGeneration = nil
        }
        let clipboardRestoreTask: Task<Void, Never>?
        if shouldRestoreClipboard, let pasteboard {
            clipboardRestoreTask = scheduleClipboardRestore(
                savedContents,
                expectedText: textToDeliver,
                sessionID: sessionID,
                on: pasteboard
            )
        } else {
            clipboardRestoreTask = nil
        }

        return (
            PasteOutcome(result: pasteResult, autoLearnGeneration: autoLearnGeneration),
            clipboardRestoreTask
        )
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
    private static func deliverText(_ text: String, method: PasteMethod, sessionID: String) async -> PasteResult {
        switch method {
        case .appleScript:
            return pasteUsingAppleScript(sessionID: sessionID) ? .commandPosted : .commandNotPosted
        case .standard:
            return await pasteFromClipboard(sessionID: sessionID)
        case .directTyping:
            // Never retry partial typing: a retry could duplicate text.
            let result: PasteResult
            switch await DirectTextTyper.type(text) {
            case .posted: result = .commandPosted
            case .notPosted: result = .commandNotPosted
            case .partiallyPosted: result = .commandPartiallyPosted
            }
            return result
        }
    }

    @MainActor
    private static func scheduleClipboardRestore(
        _ savedContents: ClipboardSnapshot,
        expectedText: String,
        sessionID: String,
        on pasteboard: NSPasteboard
    ) -> Task<Void, Never> {
        let delay = min(
            max(
                UserDefaults.standard.double(forKey: "clipboardRestoreDelay"),
                minimumClipboardRestoreDelay
            ),
            5.0
        )
        return Task { @MainActor in
            await wait(delay)
            guard pasteboardStillOwnedByPasteSession(pasteboard, expectedText: expectedText, sessionID: sessionID)
            else {
                logger.notice("Clipboard restore skipped: clipboard changed id=\(sessionID, privacy: .public)")
                return
            }
            pasteboard.clearContents()
            if !savedContents.isEmpty, !pasteboard.writeObjects(pasteboardItems(from: savedContents)) {
                logger.error("Clipboard restore failed id=\(sessionID, privacy: .public)")
                return
            }
            logger.notice("Clipboard restored id=\(sessionID, privacy: .public)")
        }
    }

    private static func pasteboardStillOwnedByPasteSession(
        _ pasteboard: NSPasteboard,
        expectedText: String,
        sessionID: String
    ) -> Bool {
        pasteboard.string(forType: .string) == expectedText
            && pasteboard.string(forType: ClipboardManager.pasteSessionType) == sessionID
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

    private static let pasteScriptKeystroke = makeScript(
        "tell application \"System Events\" to keystroke \"v\" using command down")
    private static let pasteScriptKeyCode = makeScript(
        "tell application \"System Events\" to key code 9 using command down")

    @MainActor
    private static var layoutSwitchesToQWERTYOnCommand: Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let nameRef = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return false }
        return (Unmanaged<CFString>.fromOpaque(nameRef).takeUnretainedValue() as String).hasSuffix("⌘")
    }

    @MainActor
    private static func pasteUsingAppleScript(sessionID: String) -> Bool {
        guard let script = layoutSwitchesToQWERTYOnCommand ? pasteScriptKeyCode : pasteScriptKeystroke else {
            logger.error("AppleScript paste script is unavailable id=\(sessionID, privacy: .public)")
            return false
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            logger.error("AppleScript paste failed id=\(sessionID, privacy: .public): \(String(describing: error), privacy: .public)")
        }
        return error == nil
    }

    // MARK: - CGEvent paste

    // Posts Cmd+V via CGEvent without modifying the active input source.
    @MainActor
    private static func pasteFromClipboard(sessionID: String) async -> PasteResult {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility permission is required to paste with simulated key events id=\(sessionID, privacy: .public)")
            return .commandNotPosted
        }

        let source = CGEventSource(stateID: .privateState)

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        else {
            logger.error("Failed to create Cmd+V keyboard events id=\(sessionID, privacy: .public)")
            return .commandNotPosted
        }

        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        cmdUp.flags = []

        cmdDown.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        vDown.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        vUp.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        cmdUp.post(tap: .cghidEventTap)

        return .commandPosted
    }

    private static func elapsedMilliseconds(since start: TimeInterval) -> Int {
        Int((ProcessInfo.processInfo.systemUptime - start) * 1_000)
    }

    private static func wait(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    // MARK: - Send Key

    static func performSendKey(_ key: FinishAndSendKey) {
        guard key.isEnabled else { return }
        guard AXIsProcessTrusted() else { return }

        let source = CGEventSource(stateID: .privateState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)

        switch key {
        case .none: return
        case .enter: break
        case .shiftEnter:
            enterDown?.flags = .maskShift
            enterUp?.flags = .maskShift
        case .commandEnter:
            enterDown?.flags = .maskCommand
            enterUp?.flags = .maskCommand
        }

        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
    }
}
