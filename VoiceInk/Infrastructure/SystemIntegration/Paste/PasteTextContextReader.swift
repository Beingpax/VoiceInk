import ApplicationServices
import Foundation

/// AX work stays off the main thread. Each request owns its web-accessibility state.
final class PasteTextContextReader: @unchecked Sendable {
    struct Snapshot: @unchecked Sendable {
        let target: AXUIElement
        let selection: NSRange
        let context: SmartPunctuation.Context
    }

    private let queue = DispatchQueue(label: "com.prakashjoshipax.voiceink.paste-context", qos: .userInitiated)

    func read(processID: pid_t) async -> Snapshot? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard AXIsProcessTrusted(), processID != ProcessInfo.processInfo.processIdentifier else {
                    continuation.resume(returning: nil)
                    return
                }
                let reader = AccessibilityTextReader(messagingTimeout: 0.03, fieldMessagingTimeout: 0.03, readBudget: 0.25)
                let app = AXUIElementCreateApplication(processID)
                defer { reader.restoreWebAccessibility(processID: processID, appElement: app) }
                let readings = reader.focusedReadings(processID: processID, includeSystemFocus: false)
                let snapshots = readings.compactMap { reading -> Snapshot? in
                    guard let selection = reading.selection,
                        let context = SmartPunctuation.Context(text: reading.fieldText, selection: selection)
                    else { return nil }
                    return Snapshot(target: reading.targetElement, selection: selection, context: context)
                }
                guard let first = snapshots.first,
                    snapshots.allSatisfy({ Self.matches(first, $0) }) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: first)
            }
        }
    }

    static func matches(_ original: Snapshot, _ current: Snapshot?) -> Bool {
        guard let current else { return false }
        return CFEqual(original.target, current.target)
            && original.selection == current.selection && original.context == current.context
    }
}
