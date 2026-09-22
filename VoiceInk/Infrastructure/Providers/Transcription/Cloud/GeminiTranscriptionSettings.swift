import Foundation
import LLMkit

enum GeminiTranscriptionSettings {
    static let smartTranscriptionKey = "GeminiSmartTranscription"

    static func mode(defaults: UserDefaults = .standard) -> GeminiTranscriptionMode {
        defaults.bool(forKey: smartTranscriptionKey) ? .smart : .verbatim
    }
}
