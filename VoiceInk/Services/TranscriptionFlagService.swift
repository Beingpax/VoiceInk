import Foundation
import OSLog
import SwiftData

enum TranscriptionFlagService {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionFlagService")

    @discardableResult
    static func setFlagged(_ flagged: Bool, on transcription: Transcription, in modelContext: ModelContext) throws -> Bool {
        guard transcription.flagged != flagged else {
            return false
        }

        transcription.flagged = flagged
        try modelContext.save()

        if flagged {
            TelemetryService.captureFlagEvent(transcriptionId: transcription.id)
            logger.notice("Flagged transcription \(transcription.id.uuidString, privacy: .public)")
        }

        return true
    }
}
