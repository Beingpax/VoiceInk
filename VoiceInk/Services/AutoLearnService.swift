import Foundation
import SwiftData
import AppKit
import os

/// Monitors the focused text field after paste and auto-learns word corrections
/// when the user edits the transcription in-place.
@MainActor
class AutoLearnService {
    static let shared = AutoLearnService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AutoLearn")

    /// How long to wait after paste before taking the first snapshot (seconds)
    private let initialDelay: TimeInterval = 0.5
    /// How long to monitor the field for corrections (seconds)
    private let monitorDuration: TimeInterval = 10.0
    /// Poll interval while monitoring (seconds)
    private let pollInterval: TimeInterval = 1.5
    /// Minimum word length to consider as a correction (avoid noise)
    private let minimumWordLength = 3

    private var monitorTask: Task<Void, Never>?

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "AutoLearnFromCorrections")
    }

    private init() {}

    /// Start monitoring the focused field for corrections after a paste.
    /// - Parameters:
    ///   - pastedText: The text that was just pasted into the field.
    ///   - modelContext: SwiftData context for persisting learned replacements.
    func startMonitoring(pastedText: String, modelContext: ModelContext) {
        guard isEnabled else { return }
        guard !pastedText.isEmpty else { return }

        // Cancel any previous monitor
        monitorTask?.cancel()

        monitorTask = Task { [weak self] in
            guard let self else { return }

            // Wait for paste to land
            try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            if Task.isCancelled { return }

            // Take baseline from the field
            guard let baseline = self.readFocusedFieldValue() else {
                logger.debug("AutoLearn: Cannot read focused field, skipping")
                return
            }

            // The baseline should contain our pasted text (possibly with surrounding text)
            guard baseline.contains(pastedText.trimmingCharacters(in: .whitespaces)) ||
                  self.hasSignificantOverlap(baseline: baseline, pasted: pastedText) else {
                logger.debug("AutoLearn: Baseline doesn't match pasted text, skipping")
                return
            }

            let pastedWords = self.tokenize(pastedText)
            let startTime = Date()

            while Date().timeIntervalSince(startTime) < monitorDuration {
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                if Task.isCancelled { return }

                guard let currentValue = self.readFocusedFieldValue() else { continue }

                // If field is now empty or completely different, user moved on
                if currentValue.isEmpty { break }

                let corrections = self.detectCorrections(
                    pastedWords: pastedWords,
                    originalFull: baseline,
                    currentFull: currentValue
                )

                if !corrections.isEmpty {
                    self.learnCorrections(corrections, modelContext: modelContext)
                    break // One round of corrections is enough
                }
            }

            logger.debug("AutoLearn: Monitoring ended")
        }
    }

    /// Cancel any active monitoring (e.g., when a new transcription starts)
    func cancelMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - Private

    private func readFocusedFieldValue() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard result == .success, let element = focusedElement else { return nil }

        var value: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXValueAttribute as CFString,
            &value
        )
        guard valueResult == .success, let stringValue = value as? String else { return nil }
        return stringValue
    }

    private func hasSignificantOverlap(baseline: String, pasted: String) -> Bool {
        let baseWords = Set(tokenize(baseline))
        let pastedWords = Set(tokenize(pasted))
        guard !pastedWords.isEmpty else { return false }
        let overlap = baseWords.intersection(pastedWords)
        return Double(overlap.count) / Double(pastedWords.count) > 0.5
    }

    private func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    /// Detect word-level corrections by comparing the pasted region in old vs new field values.
    private func detectCorrections(
        pastedWords: [String],
        originalFull: String,
        currentFull: String
    ) -> [(original: String, correction: String)] {
        let currentWords = tokenize(currentFull)
        let originalWords = tokenize(originalFull)

        // If lengths differ significantly, user is still typing or did major edit — skip
        guard abs(currentWords.count - originalWords.count) <= 2 else { return [] }

        var corrections: [(original: String, correction: String)] = []

        // Simple aligned diff: find words that changed at the same position
        let minCount = min(originalWords.count, currentWords.count)
        for i in 0..<minCount {
            let orig = originalWords[i]
            let curr = currentWords[i]

            guard orig != curr else { continue }

            // Only learn if the original word was in our pasted text
            let origLower = orig.lowercased()
            let strippedOrig = orig.trimmingCharacters(in: .punctuationCharacters)
            guard pastedWords.contains(where: {
                $0.lowercased() == origLower ||
                $0.trimmingCharacters(in: .punctuationCharacters).lowercased() == strippedOrig.lowercased()
            }) else { continue }

            // Skip if it's just punctuation or case change
            let strippedCurr = curr.trimmingCharacters(in: .punctuationCharacters)
            guard strippedOrig.lowercased() != strippedCurr.lowercased() else { continue }

            // Skip very short words (high false-positive rate)
            guard strippedOrig.count >= minimumWordLength else { continue }
            guard strippedCurr.count >= minimumWordLength else { continue }

            // Skip if edit distance is too large (probably not a correction of same word)
            guard self.isReasonableCorrection(from: strippedOrig, to: strippedCurr) else { continue }

            corrections.append((original: strippedOrig, correction: strippedCurr))
        }

        return corrections
    }

    /// Checks if the correction is a plausible fix (not a completely different word).
    /// Uses a simple length-ratio + prefix heuristic.
    private func isReasonableCorrection(from original: String, to correction: String) -> Bool {
        let maxLen = max(original.count, correction.count)
        let minLen = min(original.count, correction.count)

        // Length ratio check: words shouldn't differ by more than 50% in length
        guard Double(minLen) / Double(maxLen) > 0.5 else { return false }

        // At least 2 characters in common at start or end (likely same word, different spelling)
        let prefixMatch = original.lowercased().commonPrefix(with: correction.lowercased()).count
        let suffixMatch = String(original.lowercased().reversed())
            .commonPrefix(with: String(correction.lowercased().reversed())).count

        return prefixMatch >= 2 || suffixMatch >= 2
    }

    private func learnCorrections(
        _ corrections: [(original: String, correction: String)],
        modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<WordReplacement>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []

        for correction in corrections {
            // Check if this replacement already exists
            let alreadyExists = existing.contains { entry in
                let tokens = entry.originalText
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                return tokens.contains(correction.original.lowercased())
            }

            guard !alreadyExists else {
                logger.debug("AutoLearn: '\(correction.original)' → '\(correction.correction)' already exists")
                continue
            }

            // Add the learned replacement
            let entry = WordReplacement(
                originalText: correction.original,
                replacementText: correction.correction
            )
            modelContext.insert(entry)
            logger.notice("AutoLearn: Learned '\(correction.original, privacy: .public)' → '\(correction.correction, privacy: .public)'")
        }

        do {
            try modelContext.save()
            WordReplacementService.shared.invalidateCache()

            if !corrections.isEmpty {
                NotificationManager.shared.showNotification(
                    title: "Learned \(corrections.count) correction\(corrections.count == 1 ? "" : "s")",
                    type: .success
                )
            }
        } catch {
            logger.error("AutoLearn: Failed to save corrections: \(error.localizedDescription, privacy: .public)")
        }
    }
}
