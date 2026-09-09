import Foundation

enum FinalSnapshotDiffEngine {
    static func revision(from snapshot: AutoLearnFieldSnapshot) -> AutoLearnRevision? {
        guard isValid(snapshot.pastedRange, inUTF16Length: snapshot.baselineFieldText.utf16.count),
            !textIsExactlyEqual(snapshot.baselineFieldText, snapshot.finalFieldText)
        else {
            return nil
        }

        let baselinePastedText = (snapshot.baselineFieldText as NSString).substring(with: snapshot.pastedRange)
        guard textIsExactlyEqual(baselinePastedText, snapshot.originalPastedText) else {
            return nil
        }

        let baselineScalars = Array(snapshot.baselineFieldText.unicodeScalars)
        let finalScalars = Array(snapshot.finalFieldText.unicodeScalars)
        let baselineOffsets = utf16Offsets(for: baselineScalars)
        let finalOffsets = utf16Offsets(for: finalScalars)

        guard let pastedStart = baselineOffsets.firstIndex(of: snapshot.pastedRange.location),
            let pastedEnd = baselineOffsets.firstIndex(of: NSMaxRange(snapshot.pastedRange))
        else {
            return nil
        }

        let commonPrefixCount = commonPrefixCount(baselineScalars, finalScalars)
        let commonSuffix = commonSuffixBounds(
            baselineScalars,
            finalScalars,
            commonPrefixCount: commonPrefixCount
        )
        let leadingBoundary = finalLeadingBoundary(
            pastedStart: pastedStart,
            commonPrefixCount: commonPrefixCount,
            baseline: baselineScalars,
            final: finalScalars
        )
        let trailingBoundary = finalTrailingBoundary(
            pastedEnd: pastedEnd,
            baselineCount: baselineScalars.count,
            finalCount: finalScalars.count,
            baselineSuffixStart: commonSuffix.baselineStart,
            finalSuffixStart: commonSuffix.finalStart,
            baseline: baselineScalars,
            final: finalScalars
        )

        guard leadingBoundary.index <= trailingBoundary.index,
            finalOffsets.indices.contains(leadingBoundary.index),
            finalOffsets.indices.contains(trailingBoundary.index)
        else {
            return nil
        }

        let correctedRange = NSRange(
            location: finalOffsets[leadingBoundary.index],
            length: finalOffsets[trailingBoundary.index] - finalOffsets[leadingBoundary.index]
        )
        guard isValid(correctedRange, inUTF16Length: snapshot.finalFieldText.utf16.count) else {
            return nil
        }

        let correctedText = (snapshot.finalFieldText as NSString).substring(with: correctedRange)
        guard !textIsExactlyEqual(snapshot.originalPastedText, correctedText) else { return nil }

        return AutoLearnRevision(
            original: snapshot.originalPastedText,
            corrected: correctedText,
            hasAmbiguousLeadingBoundary: leadingBoundary.isAmbiguous,
            hasAmbiguousTrailingBoundary: trailingBoundary.isAmbiguous
        )
    }

    private struct Boundary {
        let index: Int
        let isAmbiguous: Bool
    }

    private static let maximumAnchorScalars = 64
    private static let minimumAnchorScalars = 16

    private static func commonPrefixCount(
        _ baseline: [Unicode.Scalar],
        _ final: [Unicode.Scalar]
    ) -> Int {
        var count = 0
        while count < baseline.count,
            count < final.count,
            baseline[count] == final[count]
        {
            count += 1
        }
        return count
    }

    private static func commonSuffixBounds(
        _ baseline: [Unicode.Scalar],
        _ final: [Unicode.Scalar],
        commonPrefixCount: Int
    ) -> (baselineStart: Int, finalStart: Int) {
        var baselineEnd = baseline.count
        var finalEnd = final.count
        while baselineEnd > commonPrefixCount,
            finalEnd > commonPrefixCount,
            baseline[baselineEnd - 1] == final[finalEnd - 1]
        {
            baselineEnd -= 1
            finalEnd -= 1
        }
        return (baselineEnd, finalEnd)
    }

    private static func finalLeadingBoundary(
        pastedStart: Int,
        commonPrefixCount: Int,
        baseline: [Unicode.Scalar],
        final: [Unicode.Scalar]
    ) -> Boundary {
        guard pastedStart > 0 else {
            return Boundary(index: 0, isAmbiguous: true)
        }

        if commonPrefixCount >= pastedStart {
            return Boundary(index: pastedStart, isAmbiguous: false)
        }

        let anchorStart = max(0, pastedStart - maximumAnchorScalars)
        let anchor = Array(baseline[anchorStart..<pastedStart])
        if anchor.count >= minimumAnchorScalars,
            let occurrence = uniqueOccurrence(of: anchor, in: final)
        {
            return Boundary(index: occurrence.upperBound, isAmbiguous: false)
        }

        return Boundary(index: commonPrefixCount, isAmbiguous: true)
    }

    private static func finalTrailingBoundary(
        pastedEnd: Int,
        baselineCount: Int,
        finalCount: Int,
        baselineSuffixStart: Int,
        finalSuffixStart: Int,
        baseline: [Unicode.Scalar],
        final: [Unicode.Scalar]
    ) -> Boundary {
        guard pastedEnd < baselineCount else {
            return Boundary(index: finalCount, isAmbiguous: true)
        }

        if pastedEnd >= baselineSuffixStart {
            let mappedIndex = finalSuffixStart + (pastedEnd - baselineSuffixStart)
            return Boundary(index: mappedIndex, isAmbiguous: false)
        }

        let anchorEnd = min(baselineCount, pastedEnd + maximumAnchorScalars)
        let anchor = Array(baseline[pastedEnd..<anchorEnd])
        if anchor.count >= minimumAnchorScalars,
            let occurrence = uniqueOccurrence(of: anchor, in: final)
        {
            return Boundary(index: occurrence.lowerBound, isAmbiguous: false)
        }

        return Boundary(index: finalSuffixStart, isAmbiguous: true)
    }

    private static func uniqueOccurrence(
        of needle: [Unicode.Scalar],
        in haystack: [Unicode.Scalar]
    ) -> Range<Int>? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }

        var match: Range<Int>?
        for start in 0...(haystack.count - needle.count) {
            let range = start..<(start + needle.count)
            guard haystack[range].elementsEqual(needle) else { continue }
            guard match == nil else { return nil }
            match = range
        }
        return match
    }

    private static func utf16Offsets(for scalars: [Unicode.Scalar]) -> [Int] {
        var offsets: [Int] = []
        offsets.reserveCapacity(scalars.count + 1)

        var currentOffset = 0
        offsets.append(currentOffset)
        for scalar in scalars {
            currentOffset += scalar.value > 0xFFFF ? 2 : 1
            offsets.append(currentOffset)
        }
        return offsets
    }

    private static func textIsExactlyEqual(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf16.elementsEqual(rhs.utf16)
    }

    private static func isValid(_ range: NSRange, inUTF16Length length: Int) -> Bool {
        range.location != NSNotFound
            && range.location >= 0
            && range.length >= 0
            && range.location <= length
            && range.length <= length - range.location
    }
}
