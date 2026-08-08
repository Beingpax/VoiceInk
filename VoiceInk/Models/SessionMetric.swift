import Foundation
import SwiftData

@Model
final class SessionMetric {
    var id: UUID = UUID()
    var transcriptionId: UUID = UUID()
    var timestamp: Date = Date()
    var source: String?
    var wordCount: Int = 0
    var audioDuration: TimeInterval = 0
    var transcriptionModelName: String?
    var transcriptionDuration: TimeInterval?
    var speedFactor: Double?
    @Attribute(originalName: "powerModeName")
    var modeName: String?
    var aiEnhancementModelName: String?
    var enhancementDuration: TimeInterval?
    var enhancementEstimatedTokenCount: Int?

    /// Where the text actually landed. Captured at record time: the recorder panels are all
    /// non-activating, so the frontmost app is still the one about to receive the paste.
    var targetBundleIdentifier: String?
    /// Set later, if the result is taken back. The only signal in the app for "that came out wrong".
    var wasUndone: Bool = false
    /// How many dictionary replacements fired. Nil means the take predates this being recorded,
    /// which is different from zero and has to stay distinguishable.
    var dictionaryHitCount: Int?

    init(
        transcriptionId: UUID,
        timestamp: Date = Date(),
        source: String? = "recorder",
        wordCount: Int,
        audioDuration: TimeInterval,
        transcriptionModelName: String?,
        transcriptionDuration: TimeInterval?,
        speedFactor: Double?,
        modeName: String?,
        aiEnhancementModelName: String?,
        enhancementDuration: TimeInterval?,
        enhancementEstimatedTokenCount: Int? = nil,
        targetBundleIdentifier: String? = nil,
        dictionaryHitCount: Int? = nil
    ) {
        self.id = UUID()
        self.transcriptionId = transcriptionId
        self.timestamp = timestamp
        self.source = source
        self.wordCount = wordCount
        self.audioDuration = audioDuration
        self.transcriptionModelName = transcriptionModelName
        self.transcriptionDuration = transcriptionDuration
        self.speedFactor = speedFactor
        self.modeName = modeName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.enhancementDuration = enhancementDuration
        self.enhancementEstimatedTokenCount = enhancementEstimatedTokenCount
        self.targetBundleIdentifier = targetBundleIdentifier
        self.wasUndone = false
        self.dictionaryHitCount = dictionaryHitCount
    }
}
