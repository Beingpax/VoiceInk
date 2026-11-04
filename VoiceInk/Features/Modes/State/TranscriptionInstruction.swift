import Foundation

/// Per-mode instruction sent to instruction-following transcription models
/// (custom models served through an OpenAI-compatible chat completions endpoint).
struct TranscriptionInstruction: Codable, Equatable {
    enum Preset: String, Codable, CaseIterable, Identifiable {
        case clean
        case polished
        case verbatim
        case nearestSpeaker
        case speakerTags
        case custom

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .clean: return String(localized: "Clean")
            case .polished: return String(localized: "Polished")
            case .verbatim: return String(localized: "Verbatim")
            case .nearestSpeaker: return String(localized: "Nearest Speaker Only")
            case .speakerTags: return String(localized: "Speaker Tags")
            case .custom: return String(localized: "Custom")
            }
        }

        var summary: String {
            switch self {
            case .clean: return String(localized: "Readable text without fillers or accidental repetitions.")
            case .polished:
                return String(
                    localized:
                        "Like Clean, and keeps only the corrected version when the speaker corrects themselves.")
            case .verbatim: return String(localized: "Every spoken word, including fillers and repetitions.")
            case .nearestSpeaker:
                return String(localized: "Ignores background voices and transcribes only the person at the microphone.")
            case .speakerTags: return String(localized: "Labels each speaker turn as Speaker 1, Speaker 2, and so on.")
            case .custom: return String(localized: "Your own instruction, sent with the audio.")
            }
        }
    }

    var preset: Preset = .clean
    var customText: String = ""
    var temperature: Double = 0

    static let `default` = TranscriptionInstruction()
    static let temperatureRange: ClosedRange<Double> = 0...1

    /// The temperature sent to the model, clamped to `temperatureRange` and rounded to one decimal.
    var requestTemperature: Double {
        (min(max(temperature, Self.temperatureRange.lowerBound), Self.temperatureRange.upperBound) * 10).rounded() / 10
    }

    /// The user-message instruction for the given language code; nil or "auto" lets the model detect it.
    func prompt(language: String?) -> String {
        switch preset {
        case .clean:
            return
                "Audio transcription. Language: \(Self.languagePhrase(language)). Wording: omit fillers and accidental repetitions; keep the remaining spoken wording unchanged. Formatting: punctuation and capitalization. Output: transcript only."
        case .polished:
            return
                "Audio transcription. Language: \(Self.languagePhrase(language)). Wording: apply the speaker's self-corrections and keep only the final corrected version; omit fillers, false starts, and repetitions. Formatting: punctuation and capitalization. Output: transcript only."
        case .verbatim:
            return
                "Audio transcription. Language: \(Self.languagePhrase(language)). Wording: verbatim, including fillers and repetitions. Formatting: punctuation and capitalization. Output: transcript only."
        case .nearestSpeaker:
            return
                "Transcribe this audio. Include all spoken words and verbal fillers. Write numbers as spoken. No punctuation or capitalization. Transcribe only the speaker nearest to the microphone. Do not transcribe any other voices."
        case .speakerTags:
            return
                "Transcribe this audio with punctuation and capitalization. Include all spoken words and verbal fillers. Write numbers in their standard written form. Put speaker tags <spk:0> <spk:1> <spk:2> <spk:3> on the transcription."
        case .custom:
            let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? Self.default.prompt(language: language) : trimmed
        }
    }

    private static func languagePhrase(_ language: String?) -> String {
        guard let language, !language.isEmpty, language != "auto",
            let name = Locale(identifier: "en").localizedString(forIdentifier: language)
        else {
            return "as spoken"
        }
        return name
    }
}

extension TranscriptionInstruction {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preset = (try? container.decodeIfPresent(Preset.self, forKey: .preset)) ?? .clean
        customText = try container.decodeIfPresent(String.self, forKey: .customText) ?? ""
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0
    }
}
