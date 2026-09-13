import Foundation

enum FinalSnapshotDiffEngine {
    static func revision(from snapshot: AutoLearnFieldSnapshot) -> AutoLearnRevision? {
        let baseline = snapshot.baselineFieldText as NSString
        let final = snapshot.finalFieldText as NSString

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

        guard final.length >= beforeRange.length + afterRange.length else {
            return nil
        }

        let finalBeforeText = final.substring(with: beforeRange)
        let finalAfterRange = NSRange(
            location: final.length - afterRange.length,
            length: afterRange.length
        )
        let finalAfterText = final.substring(with: finalAfterRange)

        // Only the pasted region may change. Any edit to surrounding field text
        // makes the capture ambiguous and must not produce a learned correction.
        guard textIsExactlyEqual(beforeText, finalBeforeText),
            textIsExactlyEqual(afterText, finalAfterText)
        else {
            return nil
        }

        let correctedRange = NSRange(
            location: beforeRange.length,
            length: final.length - beforeRange.length - afterRange.length
        )
        let correctedText = final.substring(with: correctedRange)
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
