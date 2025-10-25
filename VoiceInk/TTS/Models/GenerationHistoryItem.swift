import Foundation

struct GenerationHistoryItem: Identifiable, Equatable {
    struct VoiceSnapshot: Equatable {
        let id: String
        let name: String
    }

    let id: UUID
    let provider: TTSProviderType
    let voice: VoiceSnapshot
    let format: AudioSettings.AudioFormat
    let text: String
    let audioData: Data
    let duration: TimeInterval
    let transcript: TranscriptBundle?
    let createdAt: Date

    init(provider: TTSProviderType,
         voice: VoiceSnapshot,
         format: AudioSettings.AudioFormat,
         text: String,
         audioData: Data,
         duration: TimeInterval,
         transcript: TranscriptBundle? = nil,
         createdAt: Date = Date()) {
        self.id = UUID()
        self.provider = provider
        self.voice = voice
        self.format = format
        self.text = text
        self.audioData = audioData
        self.duration = duration
        self.transcript = transcript
        self.createdAt = createdAt
    }

    var textPreview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 80 else { return trimmed }
        let prefix = trimmed.prefix(77)
        return "\(prefix)…"
    }

    var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    var formattedDuration: String {
        guard duration.isFinite, duration > 0 else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func matches(provider: TTSProviderType, voiceID: String, text: String) -> Bool {
        provider == self.provider && voice.id == voiceID && self.text == text
    }
}
