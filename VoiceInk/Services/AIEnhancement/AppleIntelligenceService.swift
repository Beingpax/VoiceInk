import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

class AppleIntelligenceService: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AppleIntelligenceService")

    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var unavailabilityReason: String?

    init() {
        refreshAvailability()
    }

    func refreshAvailability() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                isAvailable = true
                unavailabilityReason = nil
            case .unavailable(.appleIntelligenceNotEnabled):
                isAvailable = false
                unavailabilityReason = "Apple Intelligence is not enabled. Turn it on in System Settings › Apple Intelligence & Siri."
            case .unavailable(.deviceNotEligible):
                isAvailable = false
                unavailabilityReason = "This Mac doesn't support Apple Intelligence."
            case .unavailable(.modelNotReady):
                isAvailable = false
                unavailabilityReason = "Apple Intelligence is still downloading the on-device model. Try again in a few minutes."
            @unknown default:
                isAvailable = false
                unavailabilityReason = "Apple Intelligence is unavailable."
            }
            return
        }
        #endif
        isAvailable = false
        unavailabilityReason = "Apple Intelligence requires macOS 26 or later on an Apple silicon Mac."
    }

    func enhance(_ text: String, systemPrompt: String) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            throw AppleIntelligenceError.unavailable("Requires macOS 26 or later.")
        }

        guard isAvailable else {
            throw AppleIntelligenceError.unavailable(unavailabilityReason ?? "Apple Intelligence is not available.")
        }

        let session = LanguageModelSession {
            systemPrompt
        }

        do {
            let response = try await session.respond(to: text)
            return response.content
        } catch {
            logger.error("Apple Intelligence enhancement failed: \(error.localizedDescription, privacy: .public)")
            throw AppleIntelligenceError.generationFailed(error.localizedDescription)
        }
        #else
        throw AppleIntelligenceError.unavailable("This build of VoiceInk was compiled without Apple Intelligence support (requires Xcode 26+).")
        #endif
    }
}

enum AppleIntelligenceError: Error, LocalizedError {
    case unavailable(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason
        case .generationFailed(let details):
            return "Apple Intelligence failed: \(details)"
        }
    }
}
