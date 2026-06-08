import Foundation
import ApplicationServices
import os
import SelectedTextKit

@MainActor
final class SelectedTextService {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SelectedTextService")
    private static let textManager = SelectedTextManager.shared
    private static let selectedTextStrategies: [TextStrategy] = [
        .accessibility,
        .menuAction,
        .appleScript
    ]

    static func fetchSelectedText() async -> String? {
        guard AXIsProcessTrusted() else {
            logger.debug("Accessibility is not trusted; selected text capture skipped")
            return nil
        }

        do {
            return normalized(try await textManager.getSelectedText(strategies: selectedTextStrategies))
        } catch {
            logger.debug("SelectedTextKit failed to capture selected text: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
