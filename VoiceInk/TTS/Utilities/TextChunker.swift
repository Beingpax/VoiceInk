import Foundation
import NaturalLanguage

struct TextChunker {
    static func chunk(text: String, limit: Int) -> [String] {
        guard text.count > limit else { return [text] }

        var chunks: [String] = []
        var current = ""

        let paragraphs = splitParagraphs(in: text)
        for paragraph in paragraphs {
            if paragraph.count > limit {
                let sentenceChunks = chunkSentences(in: paragraph, limit: limit)
                for sentenceChunk in sentenceChunks {
                    append(sentenceChunk, to: &chunks, current: &current, limit: limit, separator: " ")
                }
            } else {
                append(paragraph, to: &chunks, current: &current, limit: limit, separator: "\n\n")
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private static func splitParagraphs(in text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func chunkSentences(in paragraph: String, limit: Int) -> [String] {
        let sentences = tokenizeSentences(paragraph)
        var chunks: [String] = []
        var current = ""

        for sentence in sentences {
            if sentence.count > limit {
                let wordChunks = chunkWords(in: sentence, limit: limit)
                for wordChunk in wordChunks {
                    append(wordChunk, to: &chunks, current: &current, limit: limit, separator: " ")
                }
            } else {
                append(sentence, to: &chunks, current: &current, limit: limit, separator: " ")
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private static func chunkWords(in sentence: String, limit: Int) -> [String] {
        let words = sentence.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        var chunks: [String] = []
        var current = ""

        for word in words {
            if word.count >= limit {
                chunks.append(word)
                continue
            }
            append(word, to: &chunks, current: &current, limit: limit, separator: " ")
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private static func append(_ fragment: String,
                               to chunks: inout [String],
                               current: inout String,
                               limit: Int,
                               separator: String) {
        let trimmedFragment = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFragment.isEmpty else { return }

        if current.isEmpty {
            current = trimmedFragment
        } else if current.count + separator.count + trimmedFragment.count <= limit {
            current += separator + trimmedFragment
        } else {
            chunks.append(current)
            current = trimmedFragment
        }
    }

    private static func tokenizeSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        if sentences.isEmpty {
            sentences = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        if sentences.isEmpty {
            sentences = [text]
        }

        return sentences
    }
}
