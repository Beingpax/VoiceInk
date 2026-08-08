import Foundation
import SwiftData

@MainActor
class WordReplacementService {
    static let shared = WordReplacementService()

    private init() {}

    /// Terms applied by the most recent call, so the result peek can confirm the dictionary did
    /// something. Replacements ran on every transcript with no feedback at all, which left people
    /// adding entries and never learning whether they worked.
    private(set) var lastAppliedTerms: [String] = []

    /// How many replacements fired on the most recent call. Distinct from `lastAppliedTerms.count`
    /// only in intent: this is the figure the dashboard aggregates to answer whether the dictionary
    /// is earning its keep.
    var lastAppliedCount: Int { lastAppliedTerms.count }

    func applyReplacements(to text: String, using context: ModelContext) -> String {
        lastAppliedTerms = []
        let descriptor = FetchDescriptor<WordReplacement>(
            predicate: #Predicate { $0.isEnabled }
        )

        guard let replacements = try? context.fetch(descriptor), !replacements.isEmpty else {
            return text  // No replacements to apply
        }

        var modifiedText = text

        // Longest-first so specific triggers match before shorter overlapping ones
        let sortedReplacements = replacements.sorted {
            $0.originalText.count > $1.originalText.count
        }

        // Apply replacements (case-insensitive)
        for replacement in sortedReplacements {
            let originalGroup = replacement.originalText
            let replacementText = replacement.replacementText

            let variants =
                originalGroup
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted { $0.count > $1.count }

            for original in variants {
                let usesBoundaries = usesWordBoundaries(for: original)

                if usesBoundaries {
                    // Lookarounds instead of \b so punctuation acts as a word boundary.
                    // Word chars are Unicode letters/marks/digits (not just ASCII) so triggers
                    // can't match inside words like "vergrößern"; non-spaced scripts are exempt
                    // so Latin triggers flush against CJK/Thai still match (mirrors usesWordBoundaries).
                    let escaped = NSRegularExpression.escapedPattern(for: original)
                    // scx (Script_Extensions) so shared marks like the prolonged sound mark
                    // U+30FC (Script=Common, scx=Hira Kana) stay exempt too.
                    let wordChar = "[[\\p{L}\\p{M}\\p{N}]-[\\p{scx=Han}\\p{scx=Hiragana}\\p{scx=Katakana}\\p{scx=Hangul}\\p{scx=Thai}]]"
                    let pattern = "(?<!\(wordChar))\(escaped)(?!\(wordChar))"
                    if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                        let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                        let matchCount = regex.numberOfMatches(
                            in: modifiedText, options: [], range: range)
                        modifiedText = regex.stringByReplacingMatches(
                            in: modifiedText,
                            options: [],
                            range: range,
                            withTemplate: replacementText
                        )
                        if matchCount > 0 {
                            lastAppliedTerms.append(replacementText)
                        }
                    }
                } else {
                    // Fallback substring replace for non-spaced scripts
                    let before = modifiedText
                    modifiedText = modifiedText.replacingOccurrences(
                        of: original, with: replacementText, options: .caseInsensitive)
                    if before != modifiedText {
                        lastAppliedTerms.append(replacementText)
                    }
                }
            }
        }

        // The same term can match through several variants; report it once.
        var seen = Set<String>()
        lastAppliedTerms = lastAppliedTerms.filter { seen.insert($0).inserted }

        return modifiedText
    }

    private func usesWordBoundaries(for text: String) -> Bool {
        // Returns false for languages without spaces (CJK, Thai), true for spaced languages
        let nonSpacedScripts: [ClosedRange<UInt32>] = [
            0x3040...0x309F,  // Hiragana
            0x30A0...0x30FF,  // Katakana
            0x4E00...0x9FFF,  // CJK Unified Ideographs
            0xAC00...0xD7AF,  // Hangul Syllables
            0x0E00...0x0E7F,  // Thai
        ]

        for scalar in text.unicodeScalars {
            for range in nonSpacedScripts {
                if range.contains(scalar.value) {
                    return false
                }
            }
        }

        return true
    }
}
