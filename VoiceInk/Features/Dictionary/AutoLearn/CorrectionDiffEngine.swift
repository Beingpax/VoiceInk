import Foundation

enum CorrectionDiffEngine {
    private struct TextSegment: Equatable {
        let text: String
        let range: Range<String.Index>
        let isBoundary: Bool

        static func == (lhs: TextSegment, rhs: TextSegment) -> Bool {
            lhs.text == rhs.text
        }
    }

    private struct SegmentHunk {
        let originalRange: Range<Int>
        let correctedRange: Range<Int>
    }

    private static let trailingSentencePunctuation: Set<Character> = [
        ".", ",", "!", "?", ";", ":",
    ]
    private static let leadingWrappers: Set<Character> = [
        "\"", "“", "‘", "(", "[", "{",
    ]
    private static let structuralSeparators: Set<Character> = [
        ",", "!", "?", ";", ":", "…", "(", ")", "[", "]", "{", "}", "\"", "“", "”",
    ]

    static func candidates(from revision: AutoLearnRevision) -> [DetectedCorrectionCandidate] {
        let original = revision.original.precomposedStringWithCanonicalMapping
        let corrected = revision.corrected.precomposedStringWithCanonicalMapping
        guard original != corrected else { return [] }

        let originalSegments = segments(in: original)
        let correctedSegments = segments(in: corrected)
        guard originalSegments.count <= AutoLearnLimits.maximumDiffSegments,
            correctedSegments.count <= AutoLearnLimits.maximumDiffSegments
        else {
            return []
        }

        let hunks = segmentHunks(from: originalSegments, to: correctedSegments)
        var seen = Set<String>()
        var results: [DetectedCorrectionCandidate] = []

        for (hunkIndex, hunk) in hunks.enumerated() {
            guard !hunk.originalRange.isEmpty,
                !hunk.correctedRange.isEmpty,
                hunk.originalRange.count <= AutoLearnLimits.maximumCandidateSegments,
                hunk.correctedRange.count <= AutoLearnLimits.maximumCandidateSegments
            else {
                continue
            }

            let touchesLeadingBoundary = hunk.originalRange.lowerBound == 0
                || hunk.correctedRange.lowerBound == 0
            let touchesTrailingBoundary = hunk.originalRange.upperBound == originalSegments.count
                || hunk.correctedRange.upperBound == correctedSegments.count
            let hasLeadingAnchor = hunk.originalRange.lowerBound > 0
                && hunk.correctedRange.lowerBound > 0
            let hasTrailingAnchor = hunk.originalRange.upperBound < originalSegments.count
                && hunk.correctedRange.upperBound < correctedSegments.count
            let isWholeTextCorrection = hunk.originalRange == originalSegments.indices
                && hunk.correctedRange == correctedSegments.indices

            guard
                !(
                    revision.hasAmbiguousLeadingBoundary && touchesLeadingBoundary
                        && !hasTrailingAnchor && !isWholeTextCorrection
                ),
                !(
                    revision.hasAmbiguousTrailingBoundary && touchesTrailingBoundary
                        && !hasLeadingAnchor && !isWholeTextCorrection
                ),
                let source = fragment(
                    from: original,
                    segments: originalSegments,
                    segmentRange: hunk.originalRange
                ),
                let destination = fragment(
                    from: corrected,
                    segments: correctedSegments,
                    segmentRange: hunk.correctedRange
                ),
                let pair = cleanedPair(source: source, destination: destination)
            else {
                continue
            }

            let previousHunk = hunkIndex > 0 ? hunks[hunkIndex - 1] : nil
            let nextHunk = hunkIndex + 1 < hunks.count ? hunks[hunkIndex + 1] : nil
            let reviewOriginalRange = reviewRange(
                around: hunk.originalRange,
                lowerLimit: previousHunk?.originalRange.upperBound ?? originalSegments.startIndex,
                upperLimit: nextHunk?.originalRange.lowerBound ?? originalSegments.endIndex,
                segments: originalSegments
            )
            let reviewCorrectedRange = reviewRange(
                around: hunk.correctedRange,
                lowerLimit: previousHunk?.correctedRange.upperBound ?? correctedSegments.startIndex,
                upperLimit: nextHunk?.correctedRange.lowerBound ?? correctedSegments.endIndex,
                segments: correctedSegments
            )
            guard let originalTextContext = fragment(
                from: original,
                segments: originalSegments,
                segmentRange: reviewOriginalRange
            ),
                let correctedTextContext = fragment(
                    from: corrected,
                    segments: correctedSegments,
                    segmentRange: reviewCorrectedRange
                )
            else {
                continue
            }

            guard pair.source != pair.destination,
                !pair.source.contains(","),
                pair.source.count <= AutoLearnLimits.maximumCandidateCharacters,
                pair.destination.count <= AutoLearnLimits.maximumCandidateCharacters,
                isWithinUnspacedPrivacyLimit(pair.source, pair.destination),
                !containsControlCharacter(pair.source),
                !containsControlCharacter(pair.destination)
            else {
                continue
            }

            let deduplicationKey = pair.source + "\u{0}" + pair.destination
            guard seen.insert(deduplicationKey).inserted else { continue }

            results.append(
                DetectedCorrectionCandidate(
                    detectedOriginalText: pair.source,
                    userCorrectedText: pair.destination,
                    originalTextContext: originalTextContext,
                    correctedTextContext: correctedTextContext
                ))
        }

        return results
    }

    private static func segments(in text: String) -> [TextSegment] {
        var results: [TextSegment] = []
        var segmentStart: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                if let start = segmentStart {
                    let range = start..<index
                    results.append(
                        TextSegment(text: String(text[range]), range: range, isBoundary: false)
                    )
                    segmentStart = nil
                }
            } else if isStructuralSeparator(at: index, in: text) {
                if let start = segmentStart {
                    let range = start..<index
                    results.append(
                        TextSegment(text: String(text[range]), range: range, isBoundary: false)
                    )
                    segmentStart = nil
                }

                let end = text.index(after: index)
                let range = index..<end
                results.append(
                    TextSegment(text: String(text[range]), range: range, isBoundary: true)
                )
            } else if segmentStart == nil {
                segmentStart = index
            }
            index = text.index(after: index)
        }

        if let start = segmentStart {
            let range = start..<text.endIndex
            results.append(
                TextSegment(text: String(text[range]), range: range, isBoundary: false)
            )
        }
        return results
    }

    private static func isStructuralSeparator(
        at index: String.Index,
        in text: String
    ) -> Bool {
        let character = text[index]
        if structuralSeparators.contains(character) { return true }

        if character == "." {
            let next = text.index(after: index)
            return next == text.endIndex || text[next].isWhitespace
        }

        if character == "'" || character == "’" || character == "‘" {
            guard index > text.startIndex else { return true }
            let previous = text.index(before: index)
            let next = text.index(after: index)
            guard next < text.endIndex else { return true }
            return text[previous].isWhitespace || text[next].isWhitespace
        }

        return false
    }

    private static func segmentHunks(
        from original: [TextSegment],
        to corrected: [TextSegment]
    ) -> [SegmentHunk] {
        let difference = corrected.difference(from: original)
        let removedOffsets = Set(difference.removals.compactMap { change -> Int? in
            guard case let .remove(offset, _, _) = change else { return nil }
            return offset
        })
        let insertedOffsets = Set(difference.insertions.compactMap { change -> Int? in
            guard case let .insert(offset, _, _) = change else { return nil }
            return offset
        })

        var hunks: [SegmentHunk] = []
        var originalIndex = 0
        var correctedIndex = 0
        var hunkStart: (original: Int, corrected: Int)?

        func finishHunk() {
            guard let hunkStart else { return }
            hunks.append(
                SegmentHunk(
                    originalRange: hunkStart.original..<originalIndex,
                    correctedRange: hunkStart.corrected..<correctedIndex
                ))
        }

        while originalIndex < original.count || correctedIndex < corrected.count {
            let originalWasRemoved = originalIndex < original.count
                && removedOffsets.contains(originalIndex)
            let correctedWasInserted = correctedIndex < corrected.count
                && insertedOffsets.contains(correctedIndex)
            let isUnchangedSegment = originalIndex < original.count
                && correctedIndex < corrected.count
                && !originalWasRemoved
                && !correctedWasInserted
                && original[originalIndex] == corrected[correctedIndex]

            if isUnchangedSegment {
                finishHunk()
                hunkStart = nil
                originalIndex += 1
                correctedIndex += 1
                continue
            }

            if hunkStart == nil {
                hunkStart = (originalIndex, correctedIndex)
            }

            var advanced = false
            if originalWasRemoved {
                originalIndex += 1
                advanced = true
            }
            if correctedWasInserted {
                correctedIndex += 1
                advanced = true
            }

            if !advanced {
                if originalIndex < original.count { originalIndex += 1 }
                if correctedIndex < corrected.count { correctedIndex += 1 }
            }
        }

        finishHunk()
        return hunks
    }

    private static func fragment(
        from text: String,
        segments: [TextSegment],
        segmentRange: Range<Int>
    ) -> String? {
        guard let firstIndex = segmentRange.first,
            let lastIndex = segmentRange.last,
            segments.indices.contains(firstIndex),
            segments.indices.contains(lastIndex)
        else {
            return nil
        }

        let range = segments[firstIndex].range.lowerBound..<segments[lastIndex].range.upperBound
        let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func reviewRange(
        around range: Range<Int>,
        lowerLimit: Int,
        upperLimit: Int,
        segments: [TextSegment]
    ) -> Range<Int> {
        var lowerBound = range.lowerBound
        var upperBound = range.upperBound
        var leadingCount = 0
        var trailingCount = 0

        while lowerBound > lowerLimit,
            leadingCount < AutoLearnLimits.reviewContextSegmentsPerSide
        {
            let candidate = lowerBound - 1
            guard !segments[candidate].isBoundary else { break }
            lowerBound = candidate
            leadingCount += 1
        }

        while upperBound < upperLimit,
            trailingCount < AutoLearnLimits.reviewContextSegmentsPerSide
        {
            guard !segments[upperBound].isBoundary else { break }
            upperBound += 1
            trailingCount += 1
        }

        return lowerBound..<upperBound
    }

    private static func cleanedPair(
        source: String,
        destination: String
    ) -> (source: String, destination: String)? {
        let sourceCharacters = cleanedEdgeCharacters(Array(source))
        let destinationCharacters = cleanedEdgeCharacters(Array(destination))

        let cleanedSource = String(sourceCharacters).trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedDestination = String(destinationCharacters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedSource.isEmpty, !cleanedDestination.isEmpty else { return nil }
        return (cleanedSource, cleanedDestination)
    }

    private static func cleanedEdgeCharacters(_ characters: [Character]) -> [Character] {
        var result = characters
        while let first = result.first, leadingWrappers.contains(first) {
            result.removeFirst()
        }
        while let last = result.last, trailingSentencePunctuation.contains(last) {
            result.removeLast()
        }
        return result
    }

    private static func containsControlCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
        }
    }

    private static func isWithinUnspacedPrivacyLimit(
        _ source: String,
        _ destination: String
    ) -> Bool {
        guard !source.contains(where: { $0.isWhitespace }),
            !destination.contains(where: { $0.isWhitespace }),
            source.unicodeScalars.contains(where: { isCompactScriptScalar($0) })
                || destination.unicodeScalars.contains(where: { isCompactScriptScalar($0) })
        else {
            return true
        }

        return source.count <= AutoLearnLimits.maximumUnspacedCandidateCharacters
            && destination.count <= AutoLearnLimits.maximumUnspacedCandidateCharacters
    }

    private static func isCompactScriptScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0E00...0x0EFF, // Thai and Lao
            0x1000...0x109F, // Myanmar
            0x1780...0x17FF, // Khmer
            0x3040...0x30FF, // Hiragana and Katakana
            0x3400...0x4DBF, // CJK Extension A
            0x4E00...0x9FFF, // CJK Unified Ideographs
            0x20000...0x2FA1F: // Additional CJK ideographs
            return true
        default:
            return false
        }
    }
}
