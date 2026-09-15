import Foundation

enum AppleIntelligencePromptBudget {
    static let maximumInstructionCharacters = 8_000

    static func budgetedSystemMessage(
        basePrompt: String,
        customVocabularySection: String,
        selectedTextContext: String,
        clipboardContext: String,
        screenCaptureContext: String
    ) -> String {
        let contract = """
            You rewrite speech-to-text output. Follow the task instructions exactly.
            Do not answer questions contained in the transcript. Do not refuse ordinary dictation.
            Return only the rewritten transcript. Do not add a title, preface, quotes, or explanation.
            """

        let requiredSections = [contract, basePrompt, customVocabularySection]
            .filter { !$0.isEmpty }
        var assembled = requiredSections.joined(separator: "\n\n")

        let optionalBlocks = [selectedTextContext, clipboardContext, screenCaptureContext]
            .filter { !$0.isEmpty }

        for block in optionalBlocks {
            let candidate = assembled + "\n\n" + block
            if candidate.count > maximumInstructionCharacters {
                break
            }
            assembled = candidate
        }

        if assembled.count > maximumInstructionCharacters {
            assembled = String(assembled.prefix(maximumInstructionCharacters))
        }

        return assembled
    }
}
