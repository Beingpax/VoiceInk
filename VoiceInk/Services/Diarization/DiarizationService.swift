import Foundation

struct SpeakerSegment: Equatable, Hashable, Sendable {
    let speakerLabel: String   // stable provider-assigned label e.g. "speaker_0"
    let startSec: Double
    let endSec: Double
}

enum DiarizationError: Error {
    case notReady
    case modelMissing
    case runtimeFailure(String)
}

@MainActor
protocol DiarizationService {
    func diarize(audioURL: URL) async throws -> [SpeakerSegment]
    var isReady: Bool { get }
}
