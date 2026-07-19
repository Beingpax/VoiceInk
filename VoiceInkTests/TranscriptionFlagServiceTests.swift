import Foundation
import SwiftData
import Testing

@testable import VoiceInk

struct TranscriptionFlagServiceTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Transcription.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test func flaggingAnUnflaggedTranscriptionSucceeds() throws {
        let context = try makeContext()
        let transcription = Transcription(text: "hello", duration: 1.0)
        context.insert(transcription)

        let didChange = try TranscriptionFlagService.setFlagged(true, on: transcription, in: context)

        #expect(didChange == true)
        #expect(transcription.flagged == true)
    }

    @Test func flaggingAnAlreadyFlaggedTranscriptionIsANoOp() throws {
        let context = try makeContext()
        let transcription = Transcription(text: "hello", duration: 1.0, flagged: true)
        context.insert(transcription)

        let didChange = try TranscriptionFlagService.setFlagged(true, on: transcription, in: context)

        #expect(didChange == false)
        #expect(transcription.flagged == true)
    }

    @Test func unflaggingAFlaggedTranscriptionSucceeds() throws {
        let context = try makeContext()
        let transcription = Transcription(text: "hello", duration: 1.0, flagged: true)
        context.insert(transcription)

        let didChange = try TranscriptionFlagService.setFlagged(false, on: transcription, in: context)

        #expect(didChange == true)
        #expect(transcription.flagged == false)
    }

    @Test func unflaggingAnAlreadyUnflaggedTranscriptionIsANoOp() throws {
        let context = try makeContext()
        let transcription = Transcription(text: "hello", duration: 1.0)
        context.insert(transcription)

        let didChange = try TranscriptionFlagService.setFlagged(false, on: transcription, in: context)

        #expect(didChange == false)
        #expect(transcription.flagged == false)
    }
}
