import Foundation
import LLMkit

enum GeminiTranscriptionSettings {
    static let smartTranscriptionKey = "GeminiSmartTranscription"

    static var mode: GeminiTranscriptionMode {
        UserDefaults.standard.bool(forKey: smartTranscriptionKey) ? .smart : .verbatim
    }
}
