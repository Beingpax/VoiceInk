import Foundation
import os

class PromptDetectionService {
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "promptdetection"
    )
    
    struct PromptDetectionResult {
        let shouldEnableAI: Bool
        let selectedPromptId: UUID?
        let processedText: String
        let detectedTriggerWord: String?
        let originalEnhancementState: Bool
        let originalPromptId: UUID?
    }
    
    @MainActor
    func analyzeText(_ text: String, with enhancementService: AIEnhancementService) -> PromptDetectionResult {
        let originalEnhancementState = enhancementService.isEnhancementEnabled
        let originalPromptId = enhancementService.selectedPromptId

		for prompt in enhancementService.allPrompts {
            if !prompt.triggerWords.isEmpty {
				if let (detectedWord, processedText) = detectAndStripTriggerWord(from: text, triggerWords: prompt.triggerWords) {
                    return PromptDetectionResult(
                        shouldEnableAI: true,
                        selectedPromptId: prompt.id,
                        processedText: processedText,
                        detectedTriggerWord: detectedWord,
                        originalEnhancementState: originalEnhancementState,
                        originalPromptId: originalPromptId
                    )
                }
            }
        }

        return PromptDetectionResult(
            shouldEnableAI: false,
            selectedPromptId: nil,
            processedText: text,
            detectedTriggerWord: nil,
            originalEnhancementState: originalEnhancementState,
            originalPromptId: originalPromptId
        )
    }
    
    func applyDetectionResult(_ result: PromptDetectionResult, to enhancementService: AIEnhancementService) async {
        await MainActor.run {
            if result.shouldEnableAI {
                if !enhancementService.isEnhancementEnabled {
                    enhancementService.isEnhancementEnabled = true
                }
                if let promptId = result.selectedPromptId {
                    enhancementService.selectedPromptId = promptId
                }
            }
        }
        
        if result.shouldEnableAI {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    
    func restoreOriginalSettings(_ result: PromptDetectionResult, to enhancementService: AIEnhancementService) async {
        if result.shouldEnableAI {
            await MainActor.run {
                if enhancementService.isEnhancementEnabled != result.originalEnhancementState {
                    enhancementService.isEnhancementEnabled = result.originalEnhancementState
                }
                if let originalId = result.originalPromptId, enhancementService.selectedPromptId != originalId {
                    enhancementService.selectedPromptId = originalId
                }
            }
        }
    }
    
	private func stripLeadingTriggerWord(from text: String, triggerWord: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerText = trimmedText.lowercased()
        let lowerTrigger = triggerWord.lowercased()
        
        guard lowerText.hasPrefix(lowerTrigger) else { return nil }
        
        let triggerEndIndex = trimmedText.index(trimmedText.startIndex, offsetBy: triggerWord.count)
        
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

        let punctuationSet = CharacterSet(charactersIn: ",.!?;:")
        while let scalar = trimmedText.unicodeScalars.last, punctuationSet.contains(scalar) {
            trimmedText.removeLast()
        }

        let lowerText = trimmedText.lowercased()
        let lowerTrigger = triggerWord.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard lowerText.hasSuffix(lowerTrigger) else { return nil }

        let triggerStartIndex = trimmedText.index(trimmedText.endIndex, offsetBy: -triggerWord.count)
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
    
	private func detectAndStripTriggerWord(from text: String, triggerWords: [String]) -> (String, String)? {
        let trimmedWords = triggerWords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // Sort by length (longest first) to match the most specific trigger word
        let sortedTriggerWords = trimmedWords.sorted { $0.count > $1.count }
        
		for triggerWord in sortedTriggerWords {
			if let afterTrailing = stripTrailingTriggerWord(from: text, triggerWord: triggerWord) {
				if let afterBoth = stripLeadingTriggerWord(from: afterTrailing, triggerWord: triggerWord) {
					return (triggerWord, afterBoth)
				}
				return (triggerWord, afterTrailing)
			}
		}
		
		for triggerWord in sortedTriggerWords {
			if let afterLeading = stripLeadingTriggerWord(from: text, triggerWord: triggerWord) {
				if let afterBoth = stripTrailingTriggerWord(from: afterLeading, triggerWord: triggerWord) {
					return (triggerWord, afterBoth)
				}
				return (triggerWord, afterLeading)
			}
		}
		return nil
    }
}
