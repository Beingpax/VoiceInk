import Foundation

enum FinalSnapshotDiffEngine {
    static func revision(from snapshot: AutoLearnFieldSnapshot) -> AutoLearnRevision? {
        let baseline = snapshot.baselineFieldText as NSString

        guard isValid(snapshot.pastedRange, inUTF16Length: baseline.length),
            !textIsExactlyEqual(snapshot.baselineFieldText, snapshot.finalFieldText)
        else {
            return nil
        }

        let baselinePastedText = baseline.substring(with: snapshot.pastedRange)
        guard textIsExactlyEqual(baselinePastedText, snapshot.originalPastedText) else {
            return nil
        }

        let beforeRange = NSRange(location: 0, length: snapshot.pastedRange.location)
        let afterLocation = NSMaxRange(snapshot.pastedRange)
        let afterRange = NSRange(
            location: afterLocation,
            length: baseline.length - afterLocation
        )
        let beforeText = baseline.substring(with: beforeRange)
        let afterText = baseline.substring(with: afterRange)

        guard let correctedText = correctedPastedText(
            in: snapshot.finalFieldText,
            beforeText: beforeText,
            afterText: afterText
        ) else { return nil }
        let normalizedOriginalText = AutoLearnTextNormalizer.accessibilityComparable(
            snapshot.originalPastedText
        )
        let normalizedCorrectedText = AutoLearnTextNormalizer.accessibilityComparable(
            correctedText
        )
        guard !textIsExactlyEqual(normalizedOriginalText, normalizedCorrectedText) else {
            return nil
        }

        return AutoLearnRevision(
            original: normalizedOriginalText,
            corrected: normalizedCorrectedText
        )
    }

    private static func correctedPastedText(
        in finalText: String,
        beforeText: String,
        afterText: String
    ) -> String? {
        let leftBoundary: String.Index
        if beforeText.isEmpty {
            leftBoundary = finalText.startIndex
        } else {
            let anchor = String(beforeText.suffix(16))
            guard let range = uniqueRange(of: anchor, in: finalText) else { return nil }
            leftBoundary = range.upperBound
        }

        let rightBoundary: String.Index
        if afterText.isEmpty {
            rightBoundary = finalText.endIndex
        } else {
            let anchor = String(afterText.prefix(16))
            guard let range = uniqueRange(of: anchor, in: finalText),
                range.lowerBound >= leftBoundary
            else { return nil }
            rightBoundary = range.lowerBound
        }

        return String(finalText[leftBoundary..<rightBoundary])
    }

    private static func uniqueRange(of value: String, in text: String) -> Range<String.Index>? {
        guard !value.isEmpty,
            let firstRange = text.range(of: value, options: .literal)
        else { return nil }

        let nextSearchStart = text.index(after: firstRange.lowerBound)
        guard nextSearchStart >= text.endIndex
            || text.range(
                of: value,
                options: .literal,
                range: nextSearchStart..<text.endIndex
            ) == nil
        else { return nil }

        return firstRange
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
