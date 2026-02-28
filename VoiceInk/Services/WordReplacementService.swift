import Foundation
import SwiftData

class WordReplacementService {
    static let shared = WordReplacementService()

    private var cachedRegexes: [String: NSRegularExpression] = [:]

    private init() {}

    func invalidateCache() {
        cachedRegexes.removeAll()
    }

    func applyReplacements(to text: String, using context: ModelContext) -> String {
        let descriptor = FetchDescriptor<WordReplacement>(
            predicate: #Predicate { $0.isEnabled }
        )

        guard let replacements = try? context.fetch(descriptor), !replacements.isEmpty else {
            return text // No replacements to apply
        }

        var modifiedText = text

        // Apply replacements (case-insensitive)
        for replacement in replacements {
            let originalGroup = replacement.originalText
            let replacementText = replacement.replacementText

            // Split comma-separated originals at apply time only
            let variants = originalGroup
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for original in variants {
                let usesBoundaries = usesWordBoundaries(for: original)

                if usesBoundaries {
                    let regex = cachedRegex(for: original)
                    if let regex {
                        let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                        modifiedText = regex.stringByReplacingMatches(
                            in: modifiedText,
                            options: [],
                            range: range,
                            withTemplate: replacementText
                        )
                    }
                } else {
                    // Fallback substring replace for non-spaced scripts
                    modifiedText = modifiedText.replacingOccurrences(of: original, with: replacementText, options: .caseInsensitive)
                }
            }
        }

        return modifiedText
    }

    private func cachedRegex(for original: String) -> NSRegularExpression? {
        if let cached = cachedRegexes[original] {
            return cached
        }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: original))\\b"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        if let regex {
            cachedRegexes[original] = regex
        }
        return regex
    }

    private func usesWordBoundaries(for text: String) -> Bool {
        // Returns false for languages without spaces (CJK, Thai), true for spaced languages
        let nonSpacedScripts: [ClosedRange<UInt32>] = [
            0x3040...0x309F, // Hiragana
            0x30A0...0x30FF, // Katakana
            0x4E00...0x9FFF, // CJK Unified Ideographs
            0xAC00...0xD7AF, // Hangul Syllables
            0x0E00...0x0E7F, // Thai
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
