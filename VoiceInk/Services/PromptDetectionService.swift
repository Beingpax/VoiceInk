import Foundation

final class PromptDetectionService {
    struct Detection {
        let prompt: CustomPrompt
        let processedText: String
    }

    func detectPrompt(in text: String, prompts: [CustomPrompt]) -> Detection? {
        for candidate in triggerCandidates(from: prompts) {
            if let processedText = detectAndStripTriggerWord(from: text, triggerWord: candidate.triggerWord) {
                return Detection(prompt: candidate.prompt, processedText: processedText)
            }
        }

        return nil
    }

    private struct TriggerCandidate {
        let prompt: CustomPrompt
        let triggerWord: String
        let promptIndex: Int
        let triggerIndex: Int
    }

    private func triggerCandidates(from prompts: [CustomPrompt]) -> [TriggerCandidate] {
        prompts.enumerated()
            .flatMap { promptIndex, prompt in
                prompt.triggerWords.enumerated().compactMap { triggerIndex, triggerWord -> TriggerCandidate? in
                    let trimmed = triggerWord.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }
                    return TriggerCandidate(
                        prompt: prompt,
                        triggerWord: trimmed,
                        promptIndex: promptIndex,
                        triggerIndex: triggerIndex
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.triggerWord.count != rhs.triggerWord.count {
                    return lhs.triggerWord.count > rhs.triggerWord.count
                }
                if lhs.promptIndex != rhs.promptIndex {
                    return lhs.promptIndex < rhs.promptIndex
                }
                return lhs.triggerIndex < rhs.triggerIndex
            }
    }

    private func detectAndStripTriggerWord(from text: String, triggerWord: String) -> String? {
        if let afterTrailing = stripTrailingTriggerWord(from: text, triggerWord: triggerWord) {
            if let afterBoth = stripLeadingTriggerWord(from: afterTrailing, triggerWord: triggerWord) {
                return afterBoth
            }
            return afterTrailing
        }

        if let afterLeading = stripLeadingTriggerWord(from: text, triggerWord: triggerWord) {
            if let afterBoth = stripTrailingTriggerWord(from: afterLeading, triggerWord: triggerWord) {
                return afterBoth
            }
            return afterLeading
        }

        return nil
    }

    private func stripLeadingTriggerWord(from text: String, triggerWord: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTrigger = triggerWord.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let triggerRange = trimmedText.range(of: trimmedTrigger, options: [.caseInsensitive]),
              triggerRange.lowerBound == trimmedText.startIndex else {
            return nil
        }

        let triggerEndIndex = triggerRange.upperBound

        if triggerEndIndex < trimmedText.endIndex {
            let charAfterTrigger = trimmedText[triggerEndIndex]
            if charAfterTrigger.isLetter || charAfterTrigger.isNumber {
                return nil
            }
        }

        if triggerEndIndex >= trimmedText.endIndex {
            return ""
        }

        var remainingText = String(trimmedText[triggerEndIndex...])
        remainingText = remainingText.replacingOccurrences(
            of: "^[,\\.!\\?;:\\s]+",
            with: "",
            options: .regularExpression
        )
        remainingText = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !remainingText.isEmpty {
            remainingText = remainingText.prefix(1).uppercased() + remainingText.dropFirst()
        }

        return remainingText
    }

    private func stripTrailingTriggerWord(from text: String, triggerWord: String) -> String? {
        var trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTrigger = triggerWord.trimmingCharacters(in: .whitespacesAndNewlines)

        let punctuationSet = CharacterSet(charactersIn: ",.!?;:")
        while let scalar = trimmedText.unicodeScalars.last, punctuationSet.contains(scalar) {
            trimmedText.removeLast()
        }

        guard let triggerRange = trimmedText.range(of: trimmedTrigger, options: [.caseInsensitive, .backwards]),
              triggerRange.upperBound == trimmedText.endIndex else {
            return nil
        }

        let triggerStartIndex = triggerRange.lowerBound
        if triggerStartIndex > trimmedText.startIndex {
            let charBeforeTrigger = trimmedText[trimmedText.index(before: triggerStartIndex)]
            if charBeforeTrigger.isLetter || charBeforeTrigger.isNumber {
                return nil
            }
        }

        var remainingText = String(trimmedText[..<triggerStartIndex])
        remainingText = remainingText.replacingOccurrences(
            of: "[,\\.!\\?;:\\s]+$",
            with: "",
            options: .regularExpression
        )
        remainingText = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !remainingText.isEmpty {
            remainingText = remainingText.prefix(1).uppercased() + remainingText.dropFirst()
        }

        return remainingText
    }
}
