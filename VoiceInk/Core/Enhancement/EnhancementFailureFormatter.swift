import Foundation

enum EnhancementFailureFormatter {
    static func description(for error: Error) -> String {
        if let localizedDescription = (error as? LocalizedError)?.errorDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !localizedDescription.isEmpty
        {
            return localizedDescription
        }

        let fallbackDescription = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallbackDescription.isEmpty {
            return fallbackDescription
        }

        return String(localized: "AI enhancement failed to process the text.")
    }

    static func message(for error: Error) -> String {
        message(description: description(for: error))
    }

    static func message(description: String) -> String {
        String(format: String(localized: "Enhancement failed: %@"), description)
    }

    static func reEnhancementMessage(description: String) -> String {
        String(format: String(localized: "Re-enhancement failed: %@"), description)
    }

    static func transcriptionSavedMessage(description: String) -> String {
        String(format: String(localized: "Transcription saved, but enhancement failed: %@"), description)
    }
}
