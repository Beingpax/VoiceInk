import AppKit
import ApplicationServices

/// Sends text, rather than keyboard-layout-dependent shortcuts. Posting events
/// does not establish that the receiving editor accepted them.
@MainActor
enum DirectTextTyper {
    enum Result {
        case posted
        case notPosted
        case partiallyPosted
    }

    // Several macOS injectors use this conservative limit for compatibility
    // with receivers that truncate longer Unicode event payloads.
    private static let chunkSize = 20
    private static let interChunkDelayNanoseconds: UInt64 = 10_000_000

    static func normalizedText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    static func type(_ text: String) async -> Result {
        guard AXIsProcessTrusted(), let chunks = unicodeChunks(for: text), !chunks.isEmpty,
            let source = CGEventSource(stateID: .privateState)
        else { return .notPosted }

        var postedChunks = 0
        for chunk in chunks {
            guard !Task.isCancelled,
                let down = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: false)
            else { return postedChunks == 0 ? .notPosted : .partiallyPosted }

            // Request a line break rather than a new paragraph in rich editors.
            // This is still a Unicode payload on the neutral key, not Return.
            down.flags = chunk == [0x0D] ? .maskShift : []
            up.flags = []
            chunk.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            // Let macOS route input to the current keyboard recipient, including
            // nonactivating panels whose app is not reported as frontmost.
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            postedChunks += 1

            // Pace every chunk so receiving editors have time to process text
            // insertion, including short transcripts.
            if postedChunks < chunks.count {
                do {
                    try await Task.sleep(nanoseconds: interChunkDelayNanoseconds)
                } catch {
                    return .partiallyPosted
                }
            }
        }
        return .posted
    }

    private static func unicodeChunks(for text: String) -> [[UniChar]]? {
        var chunks: [[UniChar]] = []
        var buffer: [UniChar] = []
        buffer.reserveCapacity(chunkSize)

        for scalar in normalizedText(text).unicodeScalars {
            let value = scalar.value
            // Do not turn arbitrary control characters into editor commands.
            if (value < 0x20 || (0x7F...0x9F).contains(value)), value != 0x09, value != 0x0A {
                return nil
            }

            if value == 0x0A || value == 0x09 {
                if !buffer.isEmpty {
                    chunks.append(buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
                // A multi-character payload starting with LF/Tab can be dropped
                // by macOS. Send controls separately. Unicode CR inserts a line
                // break without generating a physical Return/Tab shortcut.
                chunks.append([value == 0x0A ? 0x0D : 0x09])
                continue
            }

            // A scalar contributes one or two UTF-16 units; never divide its
            // surrogate pair between events. Combining marks are preserved.
            let units = Array(String(scalar).utf16)
            if buffer.count + units.count > chunkSize {
                chunks.append(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
            buffer.append(contentsOf: units)
        }
        if !buffer.isEmpty { chunks.append(buffer) }
        return chunks
    }
}
