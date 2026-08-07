import ApplicationServices
import Foundation
import SelectedTextKit
import os

@MainActor
final class SelectedTextService {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SelectedTextService")
    // SelectedTextKit types are not Sendable; access stays on the main actor.
    nonisolated(unsafe) private static let textManager = SelectedTextManager.shared
    nonisolated(unsafe) private static let selectedTextStrategies: [TextStrategy] = [
        .accessibility,
        .menuAction,
        .appleScript,
    ]

    static func fetchSelectedText() async -> String? {
        guard AXIsProcessTrusted() else {
            logger.debug("Accessibility is not trusted; selected text capture skipped")
            return nil
        }

        do {
            // SelectedTextKit's types are not Sendable; the call is serialised by this service.
            nonisolated(unsafe) let manager = textManager
            nonisolated(unsafe) let strategies = selectedTextStrategies
            return normalized(try await manager.getSelectedText(strategies: strategies))
        } catch {
            logger.debug("SelectedTextKit failed to capture selected text: \(error, privacy: .public)")
            return nil
        }
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
