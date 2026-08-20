import Foundation
import NaturalLanguage

enum CorrectionDiffEngine {
    private struct WordToken {
        let text: String
        let range: Range<String.Index>
    }

    private struct TokenHunk {
        let originalRange: Range<Int>
        let correctedRange: Range<Int>
    }

    private struct CommonRun {
        let originalRange: Range<Int>
        let correctedRange: Range<Int>
    }

    static func candidates(from revision: AutoLearnRevision) -> [LearnedReplacementCandidate] {
        guard revision.original != revision.corrected else { return [] }

        let originalTokens = tokens(in: revision.original)
        let correctedTokens = tokens(in: revision.corrected)
        guard originalTokens.count <= AutoLearnLimits.maximumDiffTokens,
            correctedTokens.count <= AutoLearnLimits.maximumDiffTokens
        else {
            return []
        }

        var hunks: [TokenHunk] = []
        collectHunks(
            originalTokens: originalTokens,
            correctedTokens: correctedTokens,
            originalRange: 0..<originalTokens.count,
            correctedRange: 0..<correctedTokens.count,
            depth: 0,
            into: &hunks
        )

        var seen = Set<String>()
        var results: [LearnedReplacementCandidate] = []

        for hunk in hunks {
            guard !hunk.originalRange.isEmpty, !hunk.correctedRange.isEmpty,
                hunk.originalRange.count <= AutoLearnLimits.maximumCandidateTokens,
                hunk.correctedRange.count <= AutoLearnLimits.maximumCandidateTokens
            else {
                continue
            }

            let touchesLeadingBoundary = hunk.originalRange.lowerBound == 0
                || hunk.correctedRange.lowerBound == 0
            let touchesTrailingBoundary = hunk.originalRange.upperBound == originalTokens.count
                || hunk.correctedRange.upperBound == correctedTokens.count
            guard !(revision.hasAmbiguousLeadingBoundary && touchesLeadingBoundary),
                !(revision.hasAmbiguousTrailingBoundary && touchesTrailingBoundary),
                let source = fragment(
                    from: revision.original,
                    tokens: originalTokens,
                    tokenRange: hunk.originalRange
                ),
                let destination = fragment(
                    from: revision.corrected,
                    tokens: correctedTokens,
                    tokenRange: hunk.correctedRange
                )
            else {
                continue
            }

            guard source != destination,
                !source.contains(","),
                source.count <= AutoLearnLimits.maximumCandidateCharacters,
                destination.count <= AutoLearnLimits.maximumCandidateCharacters,
                !containsControlCharacter(source),
                !containsControlCharacter(destination)
            else {
                continue
            }

            let deduplicationKey =
                source.precomposedStringWithCanonicalMapping + "\u{0}"
                + destination.precomposedStringWithCanonicalMapping
            guard seen.insert(deduplicationKey).inserted else { continue }

            results.append(LearnedReplacementCandidate(source: source, destination: destination))
        }

        return results
    }

    private static func tokens(in text: String) -> [WordToken] {
        guard !text.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).map { range in
            WordToken(text: String(text[range]), range: range)
        }
    }

    private static func collectHunks(
        originalTokens: [WordToken],
        correctedTokens: [WordToken],
        originalRange: Range<Int>,
        correctedRange: Range<Int>,
        depth: Int,
        into hunks: inout [TokenHunk]
    ) {
        var originalStart = originalRange.lowerBound
        var correctedStart = correctedRange.lowerBound
        var originalEnd = originalRange.upperBound
        var correctedEnd = correctedRange.upperBound

        while originalStart < originalEnd,
            correctedStart < correctedEnd,
            originalTokens[originalStart].text == correctedTokens[correctedStart].text
        {
            originalStart += 1
            correctedStart += 1
        }

        while originalStart < originalEnd,
            correctedStart < correctedEnd,
            originalTokens[originalEnd - 1].text == correctedTokens[correctedEnd - 1].text
        {
            originalEnd -= 1
            correctedEnd -= 1
        }

        let trimmedOriginalRange = originalStart..<originalEnd
        let trimmedCorrectedRange = correctedStart..<correctedEnd
        guard !trimmedOriginalRange.isEmpty || !trimmedCorrectedRange.isEmpty else { return }

        guard !trimmedOriginalRange.isEmpty, !trimmedCorrectedRange.isEmpty, depth < 64 else {
            hunks.append(
                TokenHunk(originalRange: trimmedOriginalRange, correctedRange: trimmedCorrectedRange))
            return
        }

        let comparisonWork = trimmedOriginalRange.count * trimmedCorrectedRange.count
        guard comparisonWork <= 1_000_000,
            let commonRun = longestCommonRun(
                originalTokens: originalTokens,
                correctedTokens: correctedTokens,
                originalRange: trimmedOriginalRange,
                correctedRange: trimmedCorrectedRange
            )
        else {
            hunks.append(
                TokenHunk(originalRange: trimmedOriginalRange, correctedRange: trimmedCorrectedRange))
            return
        }

        collectHunks(
            originalTokens: originalTokens,
            correctedTokens: correctedTokens,
            originalRange: trimmedOriginalRange.lowerBound..<commonRun.originalRange.lowerBound,
            correctedRange: trimmedCorrectedRange.lowerBound..<commonRun.correctedRange.lowerBound,
            depth: depth + 1,
            into: &hunks
        )
        collectHunks(
            originalTokens: originalTokens,
            correctedTokens: correctedTokens,
            originalRange: commonRun.originalRange.upperBound..<trimmedOriginalRange.upperBound,
            correctedRange: commonRun.correctedRange.upperBound..<trimmedCorrectedRange.upperBound,
            depth: depth + 1,
            into: &hunks
        )
    }

    private static func longestCommonRun(
        originalTokens: [WordToken],
        correctedTokens: [WordToken],
        originalRange: Range<Int>,
        correctedRange: Range<Int>
    ) -> CommonRun? {
        var previous = Array(repeating: 0, count: correctedRange.count + 1)
        var bestLength = 0
        var bestOriginalEnd = originalRange.lowerBound
        var bestCorrectedEnd = correctedRange.lowerBound

        for originalOffset in 0..<originalRange.count {
            var current = Array(repeating: 0, count: correctedRange.count + 1)
            let originalIndex = originalRange.lowerBound + originalOffset

            for correctedOffset in 0..<correctedRange.count {
                let correctedIndex = correctedRange.lowerBound + correctedOffset
                guard originalTokens[originalIndex].text == correctedTokens[correctedIndex].text else { continue }

                let length = previous[correctedOffset] + 1
                current[correctedOffset + 1] = length
                if length > bestLength {
                    bestLength = length
                    bestOriginalEnd = originalIndex + 1
                    bestCorrectedEnd = correctedIndex + 1
                }
            }

            previous = current
        }

        guard bestLength > 0 else { return nil }
        return CommonRun(
            originalRange: (bestOriginalEnd - bestLength)..<bestOriginalEnd,
            correctedRange: (bestCorrectedEnd - bestLength)..<bestCorrectedEnd
        )
    }

    private static func fragment(
        from text: String,
        tokens: [WordToken],
        tokenRange: Range<Int>
    ) -> String? {
        guard let firstIndex = tokenRange.first,
            let lastIndex = tokenRange.last,
            tokens.indices.contains(firstIndex),
            tokens.indices.contains(lastIndex)
        else {
            return nil
        }

        let range = tokens[firstIndex].range.lowerBound..<tokens[lastIndex].range.upperBound
        let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func containsControlCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
        }
    }
}
