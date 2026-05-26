import Foundation
import NaturalLanguage

struct WhisperTextFormatter {
    static func format(_ text: String) -> String {
        let TARGET_WORD_COUNT = 50
        let MAX_SENTENCES_PER_CHUNK = 4
        let MIN_WORDS_FOR_SIGNIFICANT_SENTENCE = 4

        var finalFormattedText = ""
        
        // Attempt to detect the language of the input text
        let detectedLanguage = NLLanguageRecognizer.dominantLanguage(for: text)
        let tokenizerLanguage = detectedLanguage ?? .english // Fallback to English if detection fails
        
        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = text
        sentenceTokenizer.setLanguage(tokenizerLanguage)

        var allSentencesFromInput = [String]()
        sentenceTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { sentenceRange, _ in
            let rawSentence = String(text[sentenceRange])
            allSentencesFromInput.append(rawSentence.trimmingCharacters(in: .whitespacesAndNewlines))
            return true
        }

        guard !allSentencesFromInput.isEmpty else {
            return ""
        }

        var processedSentenceGlobalIndex = 0

        while processedSentenceGlobalIndex < allSentencesFromInput.count {
            var currentChunkTentativeSentences = [String]()
            var currentChunkWordCount = 0
            var currentChunkSignificantSentenceCount = 0

            // Build a tentative chunk based on TARGET_WORD_COUNT
            for i in processedSentenceGlobalIndex..<allSentencesFromInput.count {
                let sentence = allSentencesFromInput[i]
                
                let wordTokenizer = NLTokenizer(unit: .word)
                wordTokenizer.string = sentence
                wordTokenizer.setLanguage(tokenizerLanguage)
                var wordsInSentence = 0
                wordTokenizer.enumerateTokens(in: sentence.startIndex..<sentence.endIndex) { _, _ in
                    wordsInSentence += 1
                    return true
                }
                
                currentChunkTentativeSentences.append(sentence)
                currentChunkWordCount += wordsInSentence
                
                if wordsInSentence >= MIN_WORDS_FOR_SIGNIFICANT_SENTENCE {
                    currentChunkSignificantSentenceCount += 1
                }
                
                if currentChunkWordCount >= TARGET_WORD_COUNT {
                    break // Word target met for this tentative chunk
                }
            }
            
            // Now, apply MAX_SENTENCES_PER_CHUNK rule based on significant sentences
            var sentencesForThisFinalChunk = [String]()
            if currentChunkSignificantSentenceCount > MAX_SENTENCES_PER_CHUNK {
                var significantSentencesCountedInTrim = 0
                for sentenceInTentativeChunk in currentChunkTentativeSentences {
                    sentencesForThisFinalChunk.append(sentenceInTentativeChunk)
                    
                    // Re-check if this sentence was significant to count towards the cap
                    let wordTokenizerForTrimCheck = NLTokenizer(unit: .word)
                    wordTokenizerForTrimCheck.string = sentenceInTentativeChunk
                    wordTokenizerForTrimCheck.setLanguage(tokenizerLanguage)
                    var wordsInCurrentSentenceForTrim = 0
                    wordTokenizerForTrimCheck.enumerateTokens(in: sentenceInTentativeChunk.startIndex..<sentenceInTentativeChunk.endIndex) { _, _ in
                        wordsInCurrentSentenceForTrim += 1
                        return true
                    }

                    if wordsInCurrentSentenceForTrim >= MIN_WORDS_FOR_SIGNIFICANT_SENTENCE {
                        significantSentencesCountedInTrim += 1
                        if significantSentencesCountedInTrim >= MAX_SENTENCES_PER_CHUNK {
                            break // Reached the cap of significant sentences for this chunk
                        }
                    }
                }
            } else {
                sentencesForThisFinalChunk = currentChunkTentativeSentences
            }

            if !sentencesForThisFinalChunk.isEmpty {
                let segmentStringToAppend = sentencesForThisFinalChunk.joined(separator: " ")
                
                if !finalFormattedText.isEmpty {
                    finalFormattedText += "\n\n"
                }
                finalFormattedText += segmentStringToAppend
                
                processedSentenceGlobalIndex += sentencesForThisFinalChunk.count
            } else {
                // Safeguard: if no sentences ended up in the final chunk (e.g. all input was processed)
                // or if currentChunkTentativeSentences was empty (should be caught by outer loop condition)
                // This ensures we don't loop infinitely if something unexpected happens.
                if processedSentenceGlobalIndex >= allSentencesFromInput.count && currentChunkTentativeSentences.isEmpty {
                     break // All input processed
                } else if sentencesForThisFinalChunk.isEmpty && !currentChunkTentativeSentences.isEmpty {
                    // This implies currentChunkTentativeSentences had items but trimming resulted in zero items for final chunk
                    // which is unlikely with the logic, but as a safety, advance by what was considered.
                    processedSentenceGlobalIndex += currentChunkTentativeSentences.count 
                } else if sentencesForThisFinalChunk.isEmpty && currentChunkTentativeSentences.isEmpty && processedSentenceGlobalIndex < allSentencesFromInput.count {
                     // No sentences in tentative, means loop above didn't run, implies processedSentenceGlobalIndex needs to catch up or something is wrong
                    processedSentenceGlobalIndex = allSentencesFromInput.count // Mark as processed to exit
                    break;
                }
                 else if sentencesForThisFinalChunk.isEmpty { // General catch-all if empty for other reasons
                    break
                }
            }
        }
        
        return finalFormattedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 