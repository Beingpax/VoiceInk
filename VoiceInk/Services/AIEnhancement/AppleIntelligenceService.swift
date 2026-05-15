import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleIntelligenceAvailability: Equatable {
    case available
    case unsupportedOS
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var userFacingMessage: String {
        switch self {
        case .available:
            return "Apple Intelligence is ready."
        case .unsupportedOS:
            return "Apple Intelligence requires macOS 26 or later."
        case .deviceNotEligible:
            return "This Mac does not support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Enable Apple Intelligence in System Settings to use this provider."
        case .modelNotReady:
            return "Apple Intelligence is downloading the on-device model. Try again shortly."
        case .unknown(let detail):
            return "Apple Intelligence is unavailable: \(detail)"
        }
    }
}

enum AppleIntelligenceError: Error, LocalizedError {
    case notAvailable(AppleIntelligenceAvailability)
    case guardrailViolation
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable(let availability):
            return availability.userFacingMessage
        case .guardrailViolation:
            return "Apple Intelligence declined to process this text because it triggered the on-device safety filter. Try rephrasing or switch to another provider for this transcript."
        case .requestFailed(let message):
            return message
        }
    }
}

final class AppleIntelligenceService {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AppleIntelligenceService")

    var availability: AppleIntelligenceAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return Self.resolveAvailability()
        } else {
            return .unsupportedOS
        }
        #else
        return .unsupportedOS
        #endif
    }

    var isConfigured: Bool {
        availability.isAvailable
    }

    func enhance(systemPrompt: String, userPrompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await Self.respond(systemPrompt: systemPrompt, userPrompt: userPrompt, logger: logger)
        } else {
            throw AppleIntelligenceError.notAvailable(.unsupportedOS)
        }
        #else
        throw AppleIntelligenceError.notAvailable(.unsupportedOS)
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func resolveAvailability() -> AppleIntelligenceAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .deviceNotEligible
            case .appleIntelligenceNotEnabled:
                return .appleIntelligenceNotEnabled
            case .modelNotReady:
                return .modelNotReady
            @unknown default:
                return .unknown("Unrecognised availability state")
            }
        }
    }

    @available(macOS 26.0, *)
    private static func respond(systemPrompt: String, userPrompt: String, logger: Logger) async throws -> String {
        let availability = resolveAvailability()
        guard availability.isAvailable else {
            throw AppleIntelligenceError.notAvailable(availability)
        }

        do {
            let session = LanguageModelSession(instructions: systemPrompt)
            let response = try await session.respond(to: userPrompt)
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation:
                logger.warning("Apple Intelligence guardrail violation")
                throw AppleIntelligenceError.guardrailViolation
            default:
                logger.error("Apple Intelligence generation error: \(error.localizedDescription, privacy: .public)")
                throw AppleIntelligenceError.requestFailed(error.localizedDescription)
            }
        } catch {
            logger.error("Apple Intelligence request failed: \(error.localizedDescription, privacy: .public)")
            throw AppleIntelligenceError.requestFailed(error.localizedDescription)
        }
    }
    #endif
}
