import Foundation
import NaturalLanguage

struct TranscriptBundle: Equatable {
    let srt: String
    let vtt: String
}

struct TranscriptBuilder {
    static func makeTranscript(for text: String, duration: TimeInterval) -> TranscriptBundle? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, duration > 0 else { return nil }

        let sentences = sentenceSegments(from: trimmed)
        guard !sentences.isEmpty else { return nil }

        let totalWordCount = sentences.reduce(0) { $0 + wordCount(in: $1) }
        guard totalWordCount > 0 else { return nil }

        let minimumSegmentDuration: TimeInterval = 0.7
        var entries: [(index: Int, text: String, start: TimeInterval, end: TimeInterval)] = []

        let perWordDuration = max(duration / Double(totalWordCount), 0.1)
        var cursor: TimeInterval = 0

        for (index, sentence) in sentences.enumerated() {
            let words = max(wordCount(in: sentence), 1)
            var segmentDuration = perWordDuration * Double(words)
            segmentDuration = max(segmentDuration, minimumSegmentDuration)

            var end = cursor + segmentDuration
            if index == sentences.count - 1 {
                end = duration
            } else if end > duration {
                end = duration
            }

            if end <= cursor {
                end = min(duration, cursor + minimumSegmentDuration)
            }

            let clippedEnd = min(end, duration)
            entries.append((index + 1, sentence.trimmingCharacters(in: .whitespacesAndNewlines), cursor, clippedEnd))
            cursor = clippedEnd
        }

        // Adjust final entry to exactly match the duration
        if let last = entries.last, last.end < duration {
            entries[entries.count - 1].end = duration
        }

        let srt = buildSRT(entries: entries)
        let vtt = buildVTT(entries: entries)
        return TranscriptBundle(srt: srt, vtt: vtt)
    }

    private static func sentenceSegments(from text: String) -> [String] {
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
            sentences = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        if sentences.isEmpty {
            sentences = [text]
        }

        return sentences
    }

    private static func wordCount(in sentence: String) -> Int {
        let words = sentence.split { $0.isWhitespace || $0.isNewline }
        return words.count
    }

    private static func buildSRT(entries: [(index: Int, text: String, start: TimeInterval, end: TimeInterval)]) -> String {
        entries.map { entry in
            "\(entry.index)\n\(format(time: entry.start, style: .srt)) --> \(format(time: entry.end, style: .srt))\n\(entry.text)\n"
        }.joined(separator: "\n")
    }

    private static func buildVTT(entries: [(index: Int, text: String, start: TimeInterval, end: TimeInterval)]) -> String {
        var lines = ["WEBVTT", ""]
        lines.append(contentsOf: entries.map { entry in
            "\(format(time: entry.start, style: .vtt)) --> \(format(time: entry.end, style: .vtt))\n\(entry.text)\n"
        })
        return lines.joined(separator: "\n")
    }

    private enum TimeFormatStyle {
        case srt
        case vtt
    }

    private static func format(time: TimeInterval, style: TimeFormatStyle) -> String {
        let totalMilliseconds = Int((time * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1000
        let milliseconds = totalMilliseconds % 1000

        switch style {
        case .srt:
            return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
        case .vtt:
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
        }
    }
}
