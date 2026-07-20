import Foundation
import SwiftData
import Testing

@testable import VoiceInk

struct EnhancementImpactServiceTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Transcription.self, GoldenEvalEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @discardableResult
    private func addVerifiedRecording(
        text: String, enhancedText: String?, groundTruth: String, in context: ModelContext
    ) -> Transcription {
        let transcription = Transcription(text: text, duration: 1.0, enhancedText: enhancedText)
        context.insert(transcription)
        context.insert(
            GoldenEvalEntry(transcriptionId: transcription.id, groundTruthText: groundTruth, split: .eval))
        return transcription
    }

    @Test func recordingsWithoutEnhancedTextAreExcluded() throws {
        let context = try makeContext()
        addVerifiedRecording(text: "hello world", enhancedText: nil, groundTruth: "hello world", in: context)

        let report = try EnhancementImpactService.computeReport(in: context)

        #expect(report.entries.isEmpty)
    }

    @Test func enhancementThatMatchesGroundTruthExactlyHasZeroWERAfter() throws {
        let context = try makeContext()
        addVerifiedRecording(
            text: "hello wrold", enhancedText: "Hello world.", groundTruth: "Hello world.", in: context)

        let report = try EnhancementImpactService.computeReport(in: context)

        #expect(report.entries.count == 1)
        #expect(report.entries[0].werAfter == 0)
        #expect(report.entries[0].werBefore > 0)
        #expect(report.entries[0].werDelta > 0)  // improvement
    }

    @Test func enhancementThatIntroducesAnErrorIsARegression() throws {
        let context = try makeContext()
        // Original already matches ground truth; enhancement wrongly "corrects" it.
        addVerifiedRecording(
            text: "call John at five", enhancedText: "Call Jon at five", groundTruth: "call John at five",
            in: context)

        let report = try EnhancementImpactService.computeReport(in: context)

        #expect(report.entries.count == 1)
        #expect(report.entries[0].werBefore == 0)
        #expect(report.entries[0].werAfter > 0)
        #expect(report.entries[0].werDelta < 0)  // regression
        #expect(report.regressedCount == 1)
        #expect(report.improvedCount == 0)
    }

    @Test func identicalOriginalAndEnhancedIsUnchanged() throws {
        let context = try makeContext()
        addVerifiedRecording(
            text: "same text here", enhancedText: "same text here", groundTruth: "same text here", in: context)

        let report = try EnhancementImpactService.computeReport(in: context)

        #expect(report.entries[0].werDelta == 0)
        #expect(report.unchangedCount == 1)
    }

    @Test func aggregatesAcrossMultipleVerifiedRecordings() throws {
        let context = try makeContext()
        // Improves: "wrold" -> "world" matches ground truth.
        addVerifiedRecording(text: "hello wrold", enhancedText: "hello world", groundTruth: "hello world", in: context)
        // Regresses: correct original gets wrongly "fixed."
        addVerifiedRecording(
            text: "call John now", enhancedText: "Call Jon now", groundTruth: "call John now", in: context)
        // Unchanged: enhancement is a no-op.
        addVerifiedRecording(text: "same text", enhancedText: "same text", groundTruth: "same text", in: context)

        let report = try EnhancementImpactService.computeReport(in: context)

        #expect(report.entries.count == 3)
        #expect(report.improvedCount == 1)
        #expect(report.regressedCount == 1)
        #expect(report.unchangedCount == 1)
    }

    @Test func worstRegressionsAreSortedMostNegativeFirst() throws {
        let context = try makeContext()
        // Mild regression: 1 wrong word out of 4.
        addVerifiedRecording(
            text: "one two three four", enhancedText: "one two three FIVE",
            groundTruth: "one two three four", in: context)
        // Severe regression: everything wrong.
        addVerifiedRecording(
            text: "a b c", enhancedText: "x y z", groundTruth: "a b c", in: context)

        let report = try EnhancementImpactService.computeReport(in: context)

        #expect(report.regressedCount == 2)
        #expect(report.worstRegressions.count == 2)
        // Severe regression (werDelta closer to -1) should sort first.
        #expect(report.worstRegressions[0].werDelta <= report.worstRegressions[1].werDelta)
    }

    @Test func unverifiedRecordingsAreExcludedEvenWithEnhancedText() throws {
        let context = try makeContext()
        let transcription = Transcription(text: "hello world", duration: 1.0, enhancedText: "Hello world.")
        context.insert(transcription)
        // No GoldenEvalEntry inserted for this one — not verified, shouldn't be in the report.

        let report = try EnhancementImpactService.computeReport(in: context)

        #expect(report.entries.isEmpty)
    }

    // MARK: - Backfill (verified recordings dictated before enhancement was enabled)

    @Test func missingEnhancedTextListsOnlyVerifiedRecordingsWithoutEnhancement() throws {
        let context = try makeContext()
        let needsBackfill = addVerifiedRecording(
            text: "raw only", enhancedText: nil, groundTruth: "raw only", in: context)
        addVerifiedRecording(
            text: "already done", enhancedText: "Already done.", groundTruth: "already done", in: context)
        context.insert(Transcription(text: "unverified", duration: 1.0))

        let missing = try EnhancementImpactService.verifiedRecordingsMissingEnhancedText(in: context)

        #expect(missing.map(\.id) == [needsBackfill.id])
    }

    @Test func emptyStringEnhancedTextCountsAsMissing() throws {
        let context = try makeContext()
        addVerifiedRecording(text: "raw", enhancedText: "", groundTruth: "raw", in: context)

        let missing = try EnhancementImpactService.verifiedRecordingsMissingEnhancedText(in: context)

        #expect(missing.count == 1)
    }

    @MainActor
    @Test func backfillWritesEnhancedTextAndModelName() async throws {
        let context = try makeContext()
        let transcription = addVerifiedRecording(
            text: "helo world", enhancedText: nil, groundTruth: "hello world", in: context)

        let outcome = await EnhancementImpactService.backfillEnhancedText(
            for: [transcription],
            in: context,
            modelName: "on-device",
            enhance: { _ in "hello world" }
        )

        #expect(outcome.enhancedCount == 1)
        #expect(outcome.failedCount == 0)
        #expect(transcription.enhancedText == "hello world")
        #expect(transcription.aiEnhancementModelName == "on-device")
    }

    @MainActor
    @Test func backfillFailureSkipsRecordingAndContinues() async throws {
        let context = try makeContext()
        let failing = addVerifiedRecording(text: "fails", enhancedText: nil, groundTruth: "fails", in: context)
        let succeeding = addVerifiedRecording(text: "works", enhancedText: nil, groundTruth: "works", in: context)

        struct FakeError: Error {}
        let outcome = await EnhancementImpactService.backfillEnhancedText(
            for: [failing, succeeding],
            in: context,
            modelName: "on-device",
            enhance: { text in
                if text == "fails" { throw FakeError() }
                return "Works."
            }
        )

        #expect(outcome.enhancedCount == 1)
        #expect(outcome.failedCount == 1)
        #expect(failing.enhancedText == nil)
        #expect(succeeding.enhancedText == "Works.")
    }

    @MainActor
    @Test func backfillTreatsEmptyEnhancementResultAsFailure() async throws {
        let context = try makeContext()
        let transcription = addVerifiedRecording(text: "raw", enhancedText: nil, groundTruth: "raw", in: context)

        let outcome = await EnhancementImpactService.backfillEnhancedText(
            for: [transcription],
            in: context,
            modelName: nil,
            enhance: { _ in "" }
        )

        #expect(outcome.enhancedCount == 0)
        #expect(outcome.failedCount == 1)
        #expect(transcription.enhancedText == nil)
    }

    @MainActor
    @Test func backfilledRecordingsBecomeScoreableInTheReport() async throws {
        let context = try makeContext()
        let transcription = addVerifiedRecording(
            text: "helo wrold", enhancedText: nil, groundTruth: "hello world", in: context)

        #expect(try EnhancementImpactService.computeReport(in: context).entries.isEmpty)

        _ = await EnhancementImpactService.backfillEnhancedText(
            for: [transcription],
            in: context,
            modelName: "on-device",
            enhance: { _ in "hello world" }
        )

        let report = try EnhancementImpactService.computeReport(in: context)
        #expect(report.entries.count == 1)
        #expect(report.entries[0].werAfter == 0)
        #expect(report.improvedCount == 1)
    }
}
