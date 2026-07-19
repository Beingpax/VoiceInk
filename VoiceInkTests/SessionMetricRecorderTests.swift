import Foundation
import SwiftData
import Testing

@testable import VoiceInk

// No prior coverage existed for this file before the PostHog wiring added a
// TelemetryService.captureSessionMetric call inside recordRecorderSession — this establishes
// the baseline these edits are checked against, per the test-protected-editing rule in CLAUDE.md.
struct SessionMetricRecorderTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Transcription.self, SessionMetric.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func fetchMetrics(in context: ModelContext) throws -> [SessionMetric] {
        try context.fetch(FetchDescriptor<SessionMetric>())
    }

    @Test func skipsTranscriptionsThatAreNotCompleted() throws {
        let context = try makeContext()
        let transcription = Transcription(text: "hello world", duration: 2, transcriptionStatus: .pending)
        context.insert(transcription)

        let inserted = try SessionMetricRecorder.recordRecorderSession(
            transcription: transcription, model: nil, in: context)

        #expect(inserted == false)
        #expect(try fetchMetrics(in: context).isEmpty)
    }

    @Test func recordsAMetricForACompletedTranscription() throws {
        let context = try makeContext()
        let transcription = Transcription(
            text: "hello world from Indian English",
            duration: 4.0,
            transcriptionModelName: "Whisper Large v3",
            transcriptionDuration: 2.0,
            transcriptionStatus: .completed
        )
        context.insert(transcription)

        let inserted = try SessionMetricRecorder.recordRecorderSession(
            transcription: transcription, model: nil, in: context)

        #expect(inserted == true)
        let metrics = try fetchMetrics(in: context)
        #expect(metrics.count == 1)
        let metric = try #require(metrics.first)
        #expect(metric.transcriptionId == transcription.id)
        #expect(metric.wordCount == 5)
        #expect(metric.audioDuration == 4.0)
        #expect(metric.transcriptionModelName == "Whisper Large v3")
        #expect(metric.speedFactor == 2.0)  // 4.0s audio / 2.0s transcription
    }

    @Test func doesNotRecordTheSameTranscriptionTwice() throws {
        let context = try makeContext()
        let transcription = Transcription(text: "hello", duration: 1.0, transcriptionStatus: .completed)
        context.insert(transcription)

        let firstInsert = try SessionMetricRecorder.recordRecorderSession(
            transcription: transcription, model: nil, in: context)
        let secondInsert = try SessionMetricRecorder.recordRecorderSession(
            transcription: transcription, model: nil, in: context)

        #expect(firstInsert == true)
        #expect(secondInsert == false)
        #expect(try fetchMetrics(in: context).count == 1)
    }

    @Test func countsEnhancedTextInsteadOfRawTextWhenEnhancementCompleted() throws {
        let context = try makeContext()
        let transcription = Transcription(
            text: "hi",
            duration: 1.0,
            enhancedText: "hello there, how are you doing today",
            enhancementDuration: 0.5,
            transcriptionStatus: .completed
        )
        context.insert(transcription)

        _ = try SessionMetricRecorder.recordRecorderSession(transcription: transcription, model: nil, in: context)

        let metric = try #require(try fetchMetrics(in: context).first)
        #expect(metric.wordCount == 7)
    }
}
