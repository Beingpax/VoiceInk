import Foundation
import NaturalLanguage
import OSLog

@MainActor
final class AutoLearnLocalReviewer {
    private let analyzer: any AutoLearnLocalTextAnalyzing
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AutoLearnLocalReview")

    init(analyzer: (any AutoLearnLocalTextAnalyzing)? = nil) {
        self.analyzer = analyzer ?? AutoLearnLocalTextAnalyzer()
    }

    func review(_ candidates: [AutoLearnReviewCandidate], knownTerms: Set<String>,
        batchID: UUID = UUID()) async throws -> AutoLearnReviewResult {
        var decisions: [AutoLearnReviewDecision] = []
        var approvals: [AutoLearnReviewDecision] = []
        for candidate in candidates {
            // Cocoa spelling stays on the main actor; yield between candidates
            // so a backlog does not block the settings UI or cancellation.
            await Task.yield()
            try Task.checkCancellation()
            let evaluation = evaluate(candidate, knownTerms: knownTerms)
            let decision = AutoLearnReviewDecision(candidateID: candidate.candidateID,
                learningAction: evaluation.pair == nil ? .rejectCorrection : .addReplacementOnly,
                incorrectTextToReplace: evaluation.pair?.source,
                correctedVocabularyTerm: evaluation.pair?.destination)
            if evaluation.needsApproval {
                approvals.append(decision)
            } else {
                decisions.append(decision)
            }
            logger.notice("Auto Learn local candidate batchID=\(batchID.uuidString, privacy: .public) candidateID=\(candidate.candidateID.uuidString, privacy: .public) reason=\(evaluation.reason, privacy: .public) needsApproval=\(evaluation.needsApproval, privacy: .public)")
        }
        return .init(reviewDecisions: decisions, unresolvedReviews: [], approvalDecisions: approvals)
    }

    private struct Evaluation {
        var pair: (source: String, destination: String)? = nil
        var needsApproval = false
        let reason: String
    }

    private func evaluate(_ candidate: AutoLearnReviewCandidate, knownTerms: Set<String>) -> Evaluation {
        let original = candidate.originalText.precomposedStringWithCanonicalMapping
        let corrected = candidate.correctedText.precomposedStringWithCanonicalMapping
        guard original.count <= 1_024, corrected.count <= 1_024,
            let edit = CorrectionDiffEngine.singleEdit(from: .init(original: original, corrected: corrected))
        else { return .init(reason: "ambiguousEdit") }
        let sourceEdit = (original as NSString).substring(with: edit.originalRange)
        let targetEdit = (corrected as NSString).substring(with: edit.correctedRange)
        guard validTerm(sourceEdit), validTerm(targetEdit), key(sourceEdit) != key(targetEdit)
        else { return .init(reason: "formatOrUnsafeCharacters") }
        guard let sourceAnalysis = analyzer.analyze(original, languageHint: candidate.languageCode),
            let targetAnalysis = analyzer.analyze(corrected, languageHint: candidate.languageCode),
            sourceAnalysis.language == targetAnalysis.language
        else { return .init(reason: "unsupportedOrUncertainLanguage") }

        let entities = expandedEntities(in: corrected, analysis: targetAnalysis)
        let name = entities.filter { contains($0.range, edit.correctedRange) }
            .max { $0.range.length < $1.range.length }
        // Do not turn the tail of a partly recognized name into a global rule.
        if name == nil, entities.contains(where: { intersects($0.range, edit.correctedRange) }) {
            return .init(reason: "partialEntity")
        }

        let knownRange = knownTerms.compactMap { term -> NSRange? in
            guard validTerm(term) else { return nil }
            let matches = literalWordRanges(of: term, in: corrected)
                .filter { contains($0, edit.correctedRange) }
            return matches.count == 1 ? matches[0] : nil
        }.max { $0.length < $1.length }
        let targetRange = [name?.range, knownRange].compactMap { $0 }
            .max { $0.length < $1.length } ?? edit.correctedRange
        guard let pair = alignedPair(targetRange: targetRange, edit: edit,
            original: original, corrected: corrected), validTerm(pair.source), validTerm(pair.destination),
            closeSpelling(sourceEdit, targetEdit)
        else { return .init(reason: "unrelatedOrUnalignedEdit") }

        let sourceTokens = sourceAnalysis.tokens.filter { intersects($0.range, edit.originalRange) }
        let targetTokens = targetAnalysis.tokens.filter { intersects($0.range, edit.correctedRange) }
        guard !sourceTokens.isEmpty, !targetTokens.isEmpty,
            sourceTokens.count <= 4, targetTokens.count <= 4
        else { return .init(reason: "broadRewrite") }
        let isName = name != nil
        let isKnown = knownTerms.contains { key($0) == key(pair.destination) }
        let sourceIsName = expandedEntities(in: original, analysis: sourceAnalysis)
            .contains { contains($0.range, edit.originalRange) }
        if sourceIsName, !isName, !isKnown {
            return .init(reason: "nameToOrdinaryWord")
        }
        if !isName, sourceTokens.count == 1, targetTokens.count == 1,
            let sourceLemma = sourceTokens[0].lemma, let targetLemma = targetTokens[0].lemma,
            key(sourceLemma) == key(targetLemma) {
            return .init(reason: "grammarOrInflection")
        }

        // Correct words, homophones, and other people's valid names are never
        // sufficient evidence for an automatic global replacement.
        let spelling = sourceTokens.map { analyzer.spelling(for: $0.text, language: sourceAnalysis.language) }
        guard spelling.allSatisfy({ $0 != nil }) else { return .init(reason: "spellingUnavailable") }
        let allSourceWordsMisspelled = spelling.allSatisfy { $0?.isMisspelled == true }
        let letterChange = letters(sourceEdit) != letters(targetEdit)

        if isKnown, allSourceWordsMisspelled, letterChange,
            pair.source.count >= 4, targetTokens.count == sourceTokens.count {
            return .init(pair: pair, reason: "misspellingOfApprovedTerm")
        }

        if isName {
            guard allSourceWordsMisspelled || sourceIsName else {
                return .init(reason: "validWordToName")
            }
            // NER also tags ordinary brands and public places. A spelling or
            // entity tag does not establish identity or pronunciation.
            return .init(pair: pair, needsApproval: true, reason: "nameNeedsApproval")
        }

        guard sourceTokens.count == 1, targetTokens.count == 1,
            sourceEdit.count >= 4, targetEdit.count >= 4, allSourceWordsMisspelled, letterChange,
            let targetSpelling = analyzer.spelling(for: targetEdit, language: targetAnalysis.language),
            !targetSpelling.isMisspelled,
            spelling[0]?.suggestions.contains(where: { key($0) == key(targetEdit) }) == true
        else { return .init(reason: "insufficientSpellingEvidence") }
        return .init(pair: pair, reason: "confirmedSpellingCorrection")
    }

    private func expandedEntities(in text: String, analysis: AutoLearnLocalTextAnalysis)
        -> [AutoLearnLocalTextAnalysis.Entity] {
        analysis.entities.compactMap { entity in
            guard entity.type == .personalName else { return entity }
            var range = entity.range
            // Apple's joined names can omit an unfamiliar middle name/surname.
            // Keep the visible capitalized name run together. Such inferred
            // boundaries are used for approval, never to establish identity.
            for token in analysis.tokens.reversed() where NSMaxRange(token.range) <= range.location {
                guard nameComponent(token), whitespaceBetween(NSMaxRange(token.range), range.location, in: text) else { break }
                range = NSRange(location: token.range.location, length: NSMaxRange(range) - token.range.location)
            }
            for token in analysis.tokens where token.range.location >= NSMaxRange(range) {
                guard nameComponent(token), whitespaceBetween(NSMaxRange(range), token.range.location, in: text) else { break }
                range.length = NSMaxRange(token.range) - range.location
            }
            return .init(range: range, type: entity.type)
        }
    }

    private func nameComponent(_ token: AutoLearnLocalTextAnalysis.Token) -> Bool {
        token.text.first?.isUppercase == true && validTerm(token.text)
            && (token.lexicalClass == .noun || token.lexicalClass == .otherWord)
    }

    private func whitespaceBetween(_ start: Int, _ end: Int, in text: String) -> Bool {
        guard start < end else { return false }
        return (text as NSString).substring(with: NSRange(location: start, length: end - start))
            .allSatisfy { $0.isWhitespace && !$0.isNewline }
    }

    private func alignedPair(targetRange: NSRange, edit: CorrectionDiffEngine.Edit,
        original: String, corrected: String) -> (source: String, destination: String)? {
        let prefixLength = edit.correctedRange.location - targetRange.location
        let suffixLength = NSMaxRange(targetRange) - NSMaxRange(edit.correctedRange)
        let sourceRange = NSRange(location: edit.originalRange.location - prefixLength,
            length: prefixLength + edit.originalRange.length + suffixLength)
        guard sourceRange.location >= 0, NSMaxRange(sourceRange) <= original.utf16.count,
            let originalRange = Range(sourceRange, in: original),
            let correctedRange = Range(targetRange, in: corrected)
        else { return nil }
        let old = original as NSString, new = corrected as NSString
        guard old.substring(with: NSRange(location: sourceRange.location, length: prefixLength))
            == new.substring(with: NSRange(location: targetRange.location, length: prefixLength)),
            old.substring(with: NSRange(location: NSMaxRange(edit.originalRange), length: suffixLength))
            == new.substring(with: NSRange(location: NSMaxRange(edit.correctedRange), length: suffixLength))
        else { return nil }
        return (String(original[originalRange]), String(corrected[correctedRange]))
    }

    private func literalWordRanges(of term: String, in text: String) -> [NSRange] {
        var matches: [NSRange] = []
        var search = text.startIndex..<text.endIndex
        while let range = text.range(of: term, options: [.caseInsensitive, .literal], range: search) {
            let startsWord = range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter
            let endsWord = range.upperBound == text.endIndex || !text[range.upperBound].isLetter
            if startsWord && endsWord { matches.append(NSRange(range, in: text)) }
            search = range.upperBound..<text.endIndex
        }
        return matches
    }

    private func validTerm(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 80 && text.split(separator: " ").count <= 6
            && text.contains(where: \.isLetter)
            && text.allSatisfy { $0.isLetter || $0 == " " || $0 == "'" || $0 == "’" || $0 == "-" }
    }

    private func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        outer.location <= inner.location && NSMaxRange(outer) >= NSMaxRange(inner)
    }

    private func intersects(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        NSIntersectionRange(lhs, rhs).length > 0
    }

    private func key(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
    }

    private func letters(_ value: String) -> String { key(value).filter(\.isLetter) }

    /// Typographical similarity is a necessary gate, not phonetic or semantic
    /// proof. Evaluate the edit itself so shared context cannot inflate it.
    private func closeSpelling(_ source: String, _ destination: String) -> Bool {
        let a = Array(key(source)), b = Array(key(destination))
        let length = max(a.count, b.count)
        guard min(a.count, b.count) >= 3, length <= 80 else { return false }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { table[i][0] = i }
        for j in 0...b.count { table[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                table[i][j] = min(table[i - 1][j] + 1, table[i][j - 1] + 1,
                    table[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    table[i][j] = min(table[i][j], table[i - 2][j - 2] + 1)
                }
            }
        }
        return table[a.count][b.count] <= max(1, length / 4)
    }
}
