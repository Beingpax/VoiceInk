import Foundation
import SwiftData

class WordReplacementService {
    static let shared = WordReplacementService()

    private init() {}

    func applyReplacements(to text: String, using context: ModelContext) -> String {
        let descriptor = FetchDescriptor<WordReplacement>(
            predicate: #Predicate { $0.isEnabled }
        )

        guard let replacements = try? context.fetch(descriptor), !replacements.isEmpty else {
            return text  // No replacements to apply
        }

        var modifiedText = text

        let sortedRules = replacements
            .flatMap { replacement in
                WordReplacementVariants.parse(replacement.originalText).map {
                    (
                        original: $0,
                        replacement: replacement.replacementText,
                        dateAdded: replacement.dateAdded,
                        id: replacement.id.uuidString
                    )
                }
            }
            .sorted {
                if $0.original.count != $1.original.count {
                    return $0.original.count > $1.original.count
                }
                let leftKey = WordReplacementVariants.key(for: $0.original)
                let rightKey = WordReplacementVariants.key(for: $1.original)
                if leftKey != rightKey {
                    return leftKey < rightKey
                }
                if $0.dateAdded != $1.dateAdded {
                    return $0.dateAdded < $1.dateAdded
                }
                return $0.id < $1.id
            }

        var seenSources = Set<String>()
        let rules = sortedRules.filter {
            seenSources.insert(WordReplacementVariants.key(for: $0.original)).inserted
        }

        // Apply individual variants longest-first so appending a grouped variant never changes precedence.
        for rule in rules {
            let original = rule.original
            let replacementText = rule.replacement
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
                    let literalReplacement = NSRegularExpression.escapedTemplate(for: replacementText)
                    modifiedText = regex.stringByReplacingMatches(
                        in: modifiedText,
                        options: [],
                        range: range,
                        withTemplate: literalReplacement
                    )
                }
            } else {
                // Fallback substring replace for non-spaced scripts
                modifiedText = modifiedText.replacingOccurrences(
                    of: original, with: replacementText, options: .caseInsensitive)
            }
        }

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
