import Foundation

enum EstimatedTokenCounter {
    static func count(in text: String?) -> Int? {
        let characterCount = sanitizedCharacterCount(in: text)
        guard characterCount > 0 else { return nil }
        return max(1, (characterCount + 3) / 4)
    }

    static func count(in messages: [String?]) -> Int? {
        let characterCount = messages.reduce(0) { total, message in
            total + sanitizedCharacterCount(in: message)
        }

        guard characterCount > 0 else { return nil }
        return max(1, (characterCount + 3) / 4)
    }

    private static func sanitizedCharacterCount(in text: String?) -> Int {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.count
    }
}

struct EnhancementTokenEstimate: Equatable, Sendable {
    let tokenCount: Int

    static func estimate(from transcription: Transcription) -> EnhancementTokenEstimate? {
        guard hasEnhancementEvidence(transcription) else { return nil }

        if let tokenCount = EstimatedTokenCounter.count(
            in: [
                transcription.aiRequestSystemMessage,
                transcription.aiRequestUserMessage,
                transcription.enhancedText,
            ]
        ) {
            return EnhancementTokenEstimate(tokenCount: tokenCount)
        }

        guard let fallbackTokenCount = EstimatedTokenCounter.count(in: transcription.text) else {
            return nil
        }

        return EnhancementTokenEstimate(tokenCount: fallbackTokenCount)
    }

    private static func hasEnhancementEvidence(_ transcription: Transcription) -> Bool {
        if let modelName = transcription.aiEnhancementModelName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !modelName.isEmpty
        {
            return true
        }

        if let enhancementDuration = transcription.enhancementDuration,
            enhancementDuration > 0
        {
            return true
        }

        return false
    }
}
