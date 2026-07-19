import Foundation
import FoundationModels

// Apple's on-device LLM (Foundation Models, macOS 26+) as an AI Enhancement provider — fully
// offline, no separate install/server required unlike Ollama. Every entry point here is safe to
// call from any OS version: availability is checked internally via `#available`/the framework's
// own runtime availability API, never assumed from the deployment target alone (macOS 26.0+ and
// Apple Intelligence enabled in System Settings are two independent conditions — a supported OS
// doesn't guarantee the model is actually usable).
enum AppleIntelligenceService {
    enum AppleIntelligenceError: Error, LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason):
                return String(format: String(localized: "Apple Intelligence is unavailable: %@"), reason)
            }
        }
    }

    static var isAvailable: Bool {
        guard #available(macOS 26.0, *) else { return false }
        return SystemLanguageModel.default.isAvailable
    }

    static var unavailableReason: String? {
        guard #available(macOS 26.0, *) else {
            return String(localized: "Requires macOS 26 or later.")
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            return unavailableReasonDescription(for: reason)
        }
    }

    @available(macOS 26.0, *)
    private static func unavailableReasonDescription(
        for reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            return String(localized: "This Mac isn't eligible for Apple Intelligence.")
        case .appleIntelligenceNotEnabled:
            return String(localized: "Apple Intelligence isn't enabled in System Settings.")
        case .modelNotReady:
            return String(localized: "The on-device model isn't ready yet (still downloading).")
        @unknown default:
            return String(localized: "Apple Intelligence is unavailable.")
        }
    }

    static func enhance(text: String, systemPrompt: String) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw AppleIntelligenceError.unavailable(String(localized: "Requires macOS 26 or later."))
        }
        guard SystemLanguageModel.default.isAvailable else {
            throw AppleIntelligenceError.unavailable(unavailableReason ?? String(localized: "Unknown reason."))
        }

        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(to: text)
        return response.content
    }
}
