import Foundation
import AVFoundation
import CoreMedia

struct TranscriptSegment: Equatable, Hashable, Sendable {
    let startSec: Double
    let endSec: Double
    let text: String
}

protocol TranscriptionService {
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String
    func transcribeWithSegments(audioURL: URL, model: any TranscriptionModel) async throws -> [TranscriptSegment]
}

extension TranscriptionService {
    func transcribeWithSegments(audioURL: URL, model: any TranscriptionModel) async throws -> [TranscriptSegment] {
        let text = try await transcribe(audioURL: audioURL, model: model)
        let durationSec = try await audioDurationSeconds(url: audioURL)
        return [TranscriptSegment(startSec: 0, endSec: durationSec, text: text)]
    }
}

private func audioDurationSeconds(url: URL) async throws -> Double {
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration)
    return CMTimeGetSeconds(duration)
}
