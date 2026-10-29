import AppKit
import ApplicationServices
import Carbon
import Foundation
import os

@MainActor
final class SelectedTextService {
    private static let capture = SelectedTextCapture(
        environment: .live,
        pasteboard: SystemSelectionPasteboard(.general)
    )

    static func captureClipboardText() -> String? {
        capture.captureClipboardText()
    }

    static func fetchSelectedText(isEnabled: Bool) async -> String? {
        guard isEnabled else { return nil }
        return await capture.fetchSelectedText()
    }
}

enum SelectedTextReading: Sendable {
    case text(String), empty, unavailable
}

/// System access is supplied separately so regression tests never send keys or
/// access the user's clipboard. Production and tests run the same capture logic.
@MainActor
struct SelectedTextCaptureEnvironment {
    var hasAccessibilityPermission: () -> Bool
    var frontmostProcessID: () -> pid_t?
    var currentProcessID: pid_t
    var readSelection: (pid_t) async -> SelectedTextReading
    var postCopy: (pid_t) -> Bool
    var uptime: () -> TimeInterval
    var waitForClipboardChange: () async -> Void
    var copyWait: TimeInterval = 0.5
    var findMenuCopy: (pid_t) async -> (@MainActor () -> Bool)? = { _ in nil }

    static var live: Self {
        Self(
            hasAccessibilityPermission: { AXIsProcessTrusted() },
            frontmostProcessID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            currentProcessID: ProcessInfo.processInfo.processIdentifier,
            readSelection: { pid in
                await Task.detached(priority: .userInitiated) {
                    SelectionAccessibility.read(processID: pid)
                }.value
            },
            postCopy: { pid in
                guard let events = SelectionCopyShortcut.makeEvents() else { return false }
                for event in events { event.postToPid(pid) }
                return true
            },
            uptime: { ProcessInfo.processInfo.systemUptime },
            waitForClipboardChange: { try? await Task.sleep(for: .milliseconds(10)) },
            findMenuCopy: { pid in
                guard let menuCopy = await Task.detached(priority: .userInitiated, operation: {
                    SelectionMenuCopy.find(processID: pid)
                }).value else { return nil }
                return { menuCopy.press() }
            }
        )
    }
}

@MainActor
protocol SelectionPasteboard: AnyObject {
    var changeCount: Int { get }
    func capture() -> ClipboardSnapshot?
    func readText() -> String?
    func markTransient(ifUnchangedSince changeCount: Int) -> ClipboardWriteResult
    func restore(_ snapshot: ClipboardSnapshot, ifUnchangedSince changeCount: Int) -> ClipboardWriteResult
}

enum ClipboardWriteResult {
    case complete(changeCount: Int), failed(changeCount: Int), changed
}

@MainActor
final class SelectedTextCapture {
    private static let selectedTextWordLimit = 2_500
    private let environment: SelectedTextCaptureEnvironment
    private let pasteboard: any SelectionPasteboard
    private var copyInProgress = false
    private var unrestoredCopyChangeCount: Int?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SelectedTextService")

    init(environment: SelectedTextCaptureEnvironment, pasteboard: any SelectionPasteboard) {
        self.environment = environment
        self.pasteboard = pasteboard
    }

    /// Snapshot at recording start; the final mode decides whether to use it later.
    func captureClipboardText() -> String? {
        guard !copyInProgress else { return nil }
        // A failed restore can leave our selected text on the pasteboard.
        // Keep excluding it until the clipboard changes independently.
        if let count = unrestoredCopyChangeCount, pasteboard.changeCount == count { return nil }
        unrestoredCopyChangeCount = nil
        return Self.normalized(pasteboard.readText())
    }

    func fetchSelectedText() async -> String? {
        let cancellation = OSAllocatedUnfairLock(initialState: false)
        return await withTaskCancellationHandler {
            guard !Task.isCancelled, environment.hasAccessibilityPermission(),
                let pid = environment.frontmostProcessID(), pid > 0,
                pid != environment.currentProcessID else { return nil }
            let reading = await environment.readSelection(pid)
            guard !cancellation.withLock({ $0 }), environment.frontmostProcessID() == pid else { return nil }
            switch reading {
            case .text(let text): return Self.normalizedSelection(text)
            // A known empty selection must not become a Copy-current-line command
            // in editors that support copying without a selection.
            case .empty: return nil
            case .unavailable: break
            }

            // Serialize temporary clipboard operations, without queueing a Copy
            // that could run after the user has moved to another selection.
            guard !copyInProgress else { return nil }
            copyInProgress = true
            defer { copyInProgress = false }
            let menuCopy = await environment.findMenuCopy(pid)
            guard !cancellation.withLock({ $0 }), environment.frontmostProcessID() == pid else { return nil }
            let initialCount = pasteboard.changeCount
            guard let saved = pasteboard.capture(), pasteboard.changeCount == initialCount else { return nil }

            // Cancellation stops an operation that has not posted yet. Once posted,
            // the independent task must finish its best-effort clipboard cleanup.
            let operation = Task { @MainActor in
                guard !cancellation.withLock({ $0 }), environment.frontmostProcessID() == pid,
                    pasteboard.changeCount == initialCount else { return nil as String? }
                let menuCopyDispatched = menuCopy?() ?? false
                if !menuCopyDispatched {
                    guard !cancellation.withLock({ $0 }), environment.frontmostProcessID() == pid,
                        pasteboard.changeCount == initialCount else { return nil }
                    guard environment.postCopy(pid) else { return nil }
                }
                let deadline = environment.uptime() + environment.copyWait
                while pasteboard.changeCount == initialCount, environment.uptime() < deadline {
                    await environment.waitForClipboardChange()
                }
                let copiedCount = pasteboard.changeCount
                // Several ownership changes cannot be safely attributed to our Copy.
                // Abstain rather than overwrite a potentially newer user copy.
                guard copiedCount == initialCount + 1 else { return nil }
                var cleanupCount = copiedCount
                // Install cleanup before marking or reading, including failed reads,
                // cancellation and focus loss. Never adopt an unrelated change count.
                defer {
                    switch pasteboard.restore(saved, ifUnchangedSince: cleanupCount) {
                    case .complete, .changed:
                        unrestoredCopyChangeCount = nil
                    case .failed(let count):
                        unrestoredCopyChangeCount = count
                        logger.error("Unable to restore the previous clipboard contents")
                    }
                }
                switch pasteboard.markTransient(ifUnchangedSince: copiedCount) {
                case .complete(let count): cleanupCount = count
                case .failed(let count):
                    cleanupCount = count
                    return nil
                case .changed: return nil
                }
                let text = pasteboard.readText()
                // macOS has no atomic compare-and-restore operation; this check
                // reduces races, but cannot eliminate concurrent clipboard writes.
                guard pasteboard.changeCount == cleanupCount else { return nil }
                guard !cancellation.withLock({ $0 }), environment.frontmostProcessID() == pid else { return nil }
                return Self.normalizedSelection(text)
            }
            let text = await operation.value
            guard !cancellation.withLock({ $0 }), environment.frontmostProcessID() == pid else { return nil }
            return text
        } onCancel: {
            cancellation.withLock { $0 = true }
        }
    }

    /// Limit both accessibility and Copy captures before storing selected-text context.
    /// Words are whitespace-separated; preserve the original formatting within the limit.
    private static func normalizedSelection(_ text: String?) -> String? {
        guard let text = normalized(text) else { return nil }
        let words = text.split(maxSplits: selectedTextWordLimit, whereSeparator: \.isWhitespace)
        guard words.count > selectedTextWordLimit else { return text }
        return String(text[..<words[selectedTextWordLimit - 1].endIndex])
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// An immutable accessibility reference, discovered off the main actor and only
/// pressed on the main actor after capture rechecks focus and cancellation.
struct SelectionMenuCopy: @unchecked Sendable {
    private let element: AXUIElement
    private static let lookupWait: TimeInterval = 0.1
    private static let messagingWait: Float = 0.02

    static func find(processID: pid_t) -> Self? {
        let lookup = Lookup(deadline: ProcessInfo.processInfo.systemUptime + lookupWait)
        let app = AXUIElementCreateApplication(processID)
        guard let menuBar = lookup.element(kAXMenuBarAttribute, from: app),
            let edit = lookup.children(of: menuBar).first(where: {
                lookup.attribute(kAXTitleAttribute, from: $0) as? String == "Edit"
            })
        else { return nil }

        // Follow Edit > Copy directly. Localized or custom menus keep using the
        // layout-aware shortcut rather than searching the entire menu tree.
        for menu in lookup.children(of: edit) {
            for item in lookup.children(of: menu) {
                guard lookup.attribute(kAXTitleAttribute, from: item) as? String == "Copy",
                    lookup.attribute(kAXRoleAttribute, from: item) as? String == kAXMenuItemRole,
                    lookup.attribute(kAXEnabledAttribute, from: item) as? Bool == true,
                    ProcessInfo.processInfo.systemUptime < lookup.deadline
                else { continue }
                return Self(element: item)
            }
        }
        return nil
    }

    @MainActor
    func press() -> Bool {
        guard AXUIElementSetMessagingTimeout(element, Self.messagingWait) == .success else { return false }
        switch AXUIElementPerformAction(element, kAXPressAction as CFString) {
        case .success, .cannotComplete:
            // cannotComplete can leave Copy pending in the target app. Wait for
            // its clipboard write without posting a second Copy via Cmd+C.
            return true
        default:
            return false
        }
    }

    private struct Lookup {
        let deadline: TimeInterval

        func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0,
                AXUIElementSetMessagingTimeout(element, min(Float(remaining), SelectionMenuCopy.messagingWait)) == .success
            else { return nil }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }

        func element(_ name: String, from parent: AXUIElement) -> AXUIElement? {
            guard let value = attribute(name, from: parent), CFGetTypeID(value) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeDowncast(value, to: AXUIElement.self)
        }

        func children(of element: AXUIElement) -> [AXUIElement] {
            guard let children = attribute(kAXChildrenAttribute, from: element) as? [AXUIElement] else { return [] }
            return Array(children.prefix(128))
        }
    }
}

/// Creates Cmd+C events without posting them.
enum SelectionCopyShortcut {
    static func makeEvents() -> [CGEvent]? {
        let sources = [
            TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
        ]
        let keyCode = sources.compactMap { $0 }.lazy.compactMap { source -> CGKeyCode? in
            guard let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
            let layoutData = Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue()
            return copyKeyCode(layoutData: layoutData, keyboardType: UInt32(LMGetKbdType()))
        }.first
        guard let keyCode else { return nil }
        let source = CGEventSource(stateID: .privateState)
        guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else { return nil }
        commandDown.flags = .maskCommand
        down.flags = .maskCommand
        up.flags = .maskCommand
        commandUp.flags = []
        return [commandDown, down, up, commandUp]
    }

    static func copyKeyCode(layoutData: CFData, keyboardType: UInt32) -> CGKeyCode? {
        guard CFDataGetLength(layoutData) >= MemoryLayout<UCKeyboardLayout>.size,
            let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        return bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            for keyCode in UInt16(0)..<128 {
                var deadKeyState: UInt32 = 0
                var characters = [UniChar](repeating: 0, count: 4)
                var length = 0
                // Honor layouts such as Dvorak–QWERTY ⌘ that remap under Command.
                let status = UCKeyTranslate(
                    layout, keyCode, UInt16(kUCKeyActionDown), UInt32(cmdKey >> 8), keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                    characters.count, &length, &characters
                )
                if status == noErr, length == 1, characters[0] == 0x63 || characters[0] == 0x43 {
                    return keyCode
                }
            }
            return nil
        }
    }
}

@MainActor
final class SystemSelectionPasteboard: SelectionPasteboard {
    private let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard) { self.pasteboard = pasteboard }
    var changeCount: Int { pasteboard.changeCount }
    func capture() -> ClipboardSnapshot? { ClipboardSnapshot.capture(pasteboard) }
    func readText() -> String? { pasteboard.string(forType: .string) }
    func markTransient(ifUnchangedSince count: Int) -> ClipboardWriteResult {
        guard pasteboard.changeCount == count else { return .changed }
        // The target app owns the initial Copy write. These advisory markers can
        // only be added afterward; they cannot revoke an earlier history/sync read.
        let types = ["org.nspasteboard.TransientType", "org.nspasteboard.ConcealedType", "org.nspasteboard.AutoGeneratedType"]
            .map { NSPasteboard.PasteboardType($0) }
        let markedCount = pasteboard.addTypes(types, owner: nil)
        guard markedCount > 0 else {
            // AppKit can refuse addTypes for contents owned by another app
            // (returning -1). Markers are advisory: read and restore the Copy
            // result without them, but only while its change count is unchanged.
            return pasteboard.changeCount == count ? .complete(changeCount: count) : .changed
        }
        for type in types {
            guard pasteboard.changeCount == markedCount else { return .changed }
            guard pasteboard.setData(Data(), forType: type) else {
                return pasteboard.changeCount == markedCount ? .failed(changeCount: markedCount) : .changed
            }
        }
        return pasteboard.changeCount == markedCount ? .complete(changeCount: markedCount) : .changed
    }

    func restore(_ snapshot: ClipboardSnapshot, ifUnchangedSince count: Int) -> ClipboardWriteResult {
        snapshot.restore(to: pasteboard, ifUnchangedSince: count)
    }
}

@MainActor
protocol ClipboardRestorationTarget {
    var changeCount: Int { get }
    func clearContents() -> Int
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: ClipboardRestorationTarget {}

@MainActor
struct ClipboardSnapshot {
    let items: [[(NSPasteboard.PasteboardType, Data)]]

    static func capture(_ pasteboard: NSPasteboard) -> ClipboardSnapshot? {
        let items = pasteboard.pasteboardItems
        // Missing item data is not the same as an empty clipboard.
        guard items != nil || pasteboard.types?.isEmpty != false else { return nil }
        var saved: [[(NSPasteboard.PasteboardType, Data)]] = []
        for item in items ?? [] {
            var representations: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                representations.append((type, data))
            }
            guard !representations.isEmpty else { return nil }
            saved.append(representations)
        }
        return ClipboardSnapshot(items: saved)
    }

    func restore(to pasteboard: any ClipboardRestorationTarget, ifUnchangedSince count: Int) -> ClipboardWriteResult {
        var ownedCount = count
        for _ in 0..<3 {
            // Items become bound to a pasteboard on write. Recreate them for retries,
            // and finish all fallible item preparation before clearing any contents.
            guard let restored = makeItems() else { return .failed(changeCount: ownedCount) }
            guard pasteboard.changeCount == ownedCount else { return .changed }
            ownedCount = pasteboard.clearContents()
            guard pasteboard.changeCount == ownedCount else { return .changed }
            if restored.isEmpty || pasteboard.writeObjects(restored) {
                return pasteboard.changeCount == ownedCount ? .complete(changeCount: ownedCount) : .changed
            }
            // Only retry while the count returned by our own clear still matches.
            // A fresh count sampled after a failure could belong to a user copy.
            guard pasteboard.changeCount == ownedCount else { return .changed }
        }
        return .failed(changeCount: ownedCount)
    }

    private func makeItems() -> [NSPasteboardItem]? {
        var restored: [NSPasteboardItem] = []
        for representations in items {
            let item = NSPasteboardItem()
            for (type, data) in representations {
                guard item.setData(data, forType: type) else { return nil }
            }
            restored.append(item)
        }
        return restored
    }
}

private enum SelectionAccessibility {
    private static let timeout: Float = 0.1

    static func read(processID: pid_t) -> SelectedTextReading {
        let app = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let element = elementAttribute(kAXFocusedUIElementAttribute as CFString, from: app) else { return .unavailable }
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
            let text = value as? String {
            if !text.isEmpty { return .text(text) }
        }
        value = nil
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &value) == .success,
            let range = value {
            var text: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, range, &text) == .success,
                let selected = text as? String {
                if !selected.isEmpty { return .text(selected) }
            }
        }
        value = nil
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 {
                if range.length == 0 { return .empty }
                else if let rangeValue = AXValueCreate(.cfRange, &range) {
                    var text: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &text) == .success,
                        let selected = text as? String, !selected.isEmpty { return .text(selected) }
                }
            }
        }
        // Some apps return empty strings even for a nonempty selection. Only
        // an explicit zero-length range above can safely suppress Copy fallback.
        return .unavailable
    }

    private static func elementAttribute(_ name: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

}
