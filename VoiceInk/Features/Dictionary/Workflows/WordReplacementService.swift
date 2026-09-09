import Foundation
import SwiftData
import os

@MainActor
final class WordReplacementService {
    static let shared = WordReplacementService()

    private struct RuleRecord: Equatable {
        let id: UUID
        let originalText: String
        let replacementText: String
        let dateAdded: Date
    }

    private struct PreparedRule {
        let original: String
        let replacement: String
        let regex: NSRegularExpression?
    }

    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "WordReplacementService"
    )
    private var cachedRecords: [RuleRecord]?
    private var cachedRules: [PreparedRule] = []

    private init() {}

    func applyReplacements(to text: String, using context: ModelContext) -> String {
        let descriptor = FetchDescriptor<WordReplacement>(
            predicate: #Predicate { $0.isEnabled }
        )

        let replacements: [WordReplacement]
        do {
            replacements = try context.fetch(descriptor)
        } catch {
            logger.error("Could not load enabled word replacements: \(error, privacy: .public)")
            return text
        }

        guard !replacements.isEmpty else {
            logger.debug("Word replacement skipped: no enabled rules")
            return text
        }

        logger.debug(
            "Starting word replacement selection with \(replacements.count, privacy: .public) enabled rule(s)"
        )

        var modifiedText = text

        let rules = preparedRules(from: replacements)

        logger.debug(
            "Prepared \(rules.count, privacy: .public) unique replacement variant(s)"
        )

        var matchedRuleCount = 0
        for rule in rules {
            let original = rule.original
            let replacementText = rule.replacement

            if let regex = rule.regex {
                let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                let matchCount = regex.numberOfMatches(in: modifiedText, options: [], range: range)
                guard matchCount > 0 else { continue }

                logger.debug(
                    "Applying boundary-aware word replacement \(original, privacy: .private) -> \(replacementText, privacy: .private), matches=\(matchCount, privacy: .public)"
                )
                let literalReplacement = NSRegularExpression.escapedTemplate(for: replacementText)
                modifiedText = regex.stringByReplacingMatches(
                    in: modifiedText,
                    options: [],
                    range: range,
                    withTemplate: literalReplacement
                )
                matchedRuleCount += 1
            } else {
                let replacedText = modifiedText.replacingOccurrences(
                    of: original, with: replacementText, options: .caseInsensitive)
                guard replacedText != modifiedText else { continue }

                logger.debug(
                    "Applying substring word replacement \(original, privacy: .private) -> \(replacementText, privacy: .private)"
                )
                modifiedText = replacedText
                matchedRuleCount += 1
            }
        }

        logger.debug(
            "Finished word replacement: \(matchedRuleCount, privacy: .public) rule(s) matched; output changed=\(modifiedText != text, privacy: .public)"
        )

        return modifiedText
    }

    private func preparedRules(from replacements: [WordReplacement]) -> [PreparedRule] {
        let records = replacements
            .map {
                RuleRecord(
                    id: $0.id,
                    originalText: $0.originalText,
                    replacementText: $0.replacementText,
                    dateAdded: $0.dateAdded
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        if cachedRecords == records {
            return cachedRules
        }

        let sortedRules = records
            .flatMap { record in
                WordReplacementVariants.parse(record.originalText).map {
                    (
                        original: $0,
                        replacement: record.replacementText,
                        dateAdded: record.dateAdded,
                        id: record.id.uuidString
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
        let rules = sortedRules.filter { rule in
            let wasSelected = seenSources.insert(
                WordReplacementVariants.key(for: rule.original)
            ).inserted
            if !wasSelected {
                logger.debug(
                    "Skipping duplicate word replacement variant \(rule.original, privacy: .private); an earlier longest-first rule already owns this trigger"
                )
            }
            return wasSelected
        }

        let prepared = rules.compactMap { rule -> PreparedRule? in
            guard usesWordBoundaries(for: rule.original) else {
                return PreparedRule(original: rule.original, replacement: rule.replacement, regex: nil)
            }

            // Lookarounds instead of \b so punctuation acts as a word boundary.
            // Word chars are Unicode letters/marks/digits (not just ASCII) so triggers
            // cannot match inside a larger word.
            do {
                let escaped = NSRegularExpression.escapedPattern(for: rule.original)
                let wordChar = "[[\\p{L}\\p{M}\\p{N}]-[\\p{scx=Han}\\p{scx=Hiragana}\\p{scx=Katakana}\\p{scx=Hangul}\\p{scx=Thai}]]"
                let pattern = "(?<!\(wordChar))\(escaped)(?!\(wordChar))"
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                return PreparedRule(original: rule.original, replacement: rule.replacement, regex: regex)
            } catch {
                logger.error(
                    "Could not build matcher for word replacement \(rule.original, privacy: .private): \(error, privacy: .public)"
                )
                return nil
            }
        }

        cachedRecords = records
        cachedRules = prepared
        logger.debug("Rebuilt cached word replacement plan with \(prepared.count, privacy: .public) rule(s)")
        return prepared
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
