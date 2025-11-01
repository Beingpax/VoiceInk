import Foundation
import AVFoundation

@MainActor
final class LocalTTSService: NSObject, TTSProvider {
    // MARK: - Properties
    private let voices: [Voice]

    override init() {
        self.voices = LocalTTSService.loadSystemVoices()
        super.init()
    }

    var name: String { "Tight Ass Mode" }

    var availableVoices: [Voice] { voices }

    var defaultVoice: Voice {
        if let preferred = voices.first(where: { $0.language.lowercased().hasPrefix("en") }) {
            return preferred
        }
        return voices.first ?? LocalTTSService.fallbackVoice
    }

    func hasValidAPIKey() -> Bool { true }

    func synthesizeSpeech(text: String, voice: Voice, settings: AudioSettings) async throws -> Data {
        guard settings.format == .wav else {
            throw TTSError.unsupportedFormat
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let utterance = AVSpeechUtterance(string: text)
                guard let systemVoice = LocalTTSService.resolveVoice(identifier: voice.id, language: voice.language) else {
                    continuation.resume(throwing: TTSError.invalidVoice)
                    return
                }

                utterance.voice = systemVoice

                let rateMultiplier = min(max(settings.speed, 0.5), 2.0)
                let baseRate = AVSpeechUtteranceDefaultSpeechRate
                let minimumRate = AVSpeechUtteranceMinimumSpeechRate
                let maximumRate = AVSpeechUtteranceMaximumSpeechRate
                let proposedRate = baseRate * Float(rateMultiplier)
                utterance.rate = min(max(proposedRate, minimumRate), maximumRate)
                utterance.pitchMultiplier = Float(min(max(settings.pitch, 0.5), 2.0))
                utterance.volume = Float(min(max(settings.volume, 0.0), 1.0))

                let synthesizer = AVSpeechSynthesizer()
                let destinationURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("wav")

                var audioFile: AVAudioFile?
                var hasCompleted = false

                synthesizer.write(utterance) { buffer in
                    guard !hasCompleted else { return }

                    do {
                        guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                            return
                        }

                        if pcmBuffer.frameLength == 0 {
                            hasCompleted = true
                            audioFile = nil
                            let data = try Data(contentsOf: destinationURL)
                            try FileManager.default.removeItem(at: destinationURL)
                            continuation.resume(returning: data)
                            return
                        }

                        if audioFile == nil {
                            audioFile = try AVAudioFile(
                                forWriting: destinationURL,
                                settings: pcmBuffer.format.settings
                            )
                        }

                        try audioFile?.write(from: pcmBuffer)
                    } catch {
                        hasCompleted = true
                        synthesizer.stopSpeaking(at: .immediate)
                        try? FileManager.default.removeItem(at: destinationURL)
                        continuation.resume(throwing: TTSError.apiError(error.localizedDescription))
                    }
                }
            }
        }
    }
}

// MARK: - Voice Helpers
private extension LocalTTSService {
    static func loadSystemVoices() -> [Voice] {
        let fetchVoices: () -> [AVSpeechSynthesisVoice] = {
            AVSpeechSynthesisVoice.speechVoices()
        }

        let systemVoices: [AVSpeechSynthesisVoice]
        if Thread.isMainThread {
            systemVoices = fetchVoices()
        } else {
            systemVoices = DispatchQueue.main.sync(execute: fetchVoices)
        }

        let mapped = systemVoices
            .sorted { lhs, rhs in
                if lhs.language == rhs.language {
                    return lhs.name < rhs.name
                }
                return lhs.language < rhs.language
            }
            .map { voice in
                Voice(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    gender: mapGender(from: voice),
                    provider: .tightAss,
                    previewURL: nil
                )
            }
        
        if mapped.isEmpty {
            return [fallbackVoice]
        }
        
        return mapped
    }

    static func mapGender(from voice: AVSpeechSynthesisVoice) -> Voice.Gender {
        switch voice.gender {
        case .male:
            return .male
        case .female:
            return .female
        default:
            return .neutral
        }
    }

    static func resolveVoice(identifier: String, language: String) -> AVSpeechSynthesisVoice? {
        if let match = AVSpeechSynthesisVoice(identifier: identifier) {
            return match
        }
        return AVSpeechSynthesisVoice(language: language)
    }

    static var fallbackVoice: Voice {
        Voice(
            id: "com.apple.speech.synthesis.voice.samantha",
            name: "Samantha",
            language: "en-US",
            gender: .female,
            provider: .tightAss,
            previewURL: nil
        )
    }
}
