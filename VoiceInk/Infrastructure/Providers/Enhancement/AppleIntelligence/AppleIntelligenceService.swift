import AppKit
import Combine
import Foundation
import os

#if canImport(FoundationModels)
    import FoundationModels
#endif

enum AppleIntelligenceAvailabilityStatus: Equatable, Sendable {
    case available
    case unsupportedOS
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable

    var isReady: Bool {
        self == .available
    }

    var title: String {
        switch self {
        case .available:
            return String(localized: "Available")
        case .unsupportedOS:
            return String(localized: "Needs macOS 26+")
        case .deviceNotEligible:
            return String(localized: "This Mac is not eligible")
        case .appleIntelligenceNotEnabled:
            return String(localized: "Turned off")
        case .modelNotReady:
            return String(localized: "Downloading")
        case .unavailable:
            return String(localized: "Unavailable")
        }
    }

    var guidance: String {
        switch self {
        case .available:
            return String(
                localized: "Uses this Mac’s on-device Apple Foundation Model. No API key and no extra server."
            )
        case .unsupportedOS:
            return String(localized: "Apple Intelligence enhancement requires macOS 26 or later.")
        case .deviceNotEligible:
            return String(
                localized: "This Mac does not support Apple Intelligence. Apple silicon is required."
            )
        case .appleIntelligenceNotEnabled:
            return String(
                localized: "Turn on Apple Intelligence in System Settings, then check again."
            )
        case .modelNotReady:
            return String(
                localized: "Apple is still preparing the on-device model. Keep the Mac awake and try again shortly."
            )
        case .unavailable:
            return String(localized: "Apple Intelligence is not available right now.")
        }
    }

    var showsSettingsButton: Bool {
        switch self {
        case .appleIntelligenceNotEnabled, .modelNotReady:
            return true
        default:
            return false
        }
    }
}

enum AppleIntelligenceCloudAvailabilityStatus: Equatable, Sendable {
    case available
    case unsupportedOS
    case missingEntitlement
    case deviceNotEligible
    case systemNotReady
    case unavailable

    var isReady: Bool {
        self == .available
    }

    var title: String {
        switch self {
        case .available:
            return String(localized: "Available")
        case .unsupportedOS:
            return String(localized: "Needs macOS 27+")
        case .missingEntitlement:
            return String(localized: "Needs entitlement")
        case .deviceNotEligible:
            return String(localized: "This Mac is not eligible")
        case .systemNotReady:
            return String(localized: "Not ready")
        case .unavailable:
            return String(localized: "Unavailable")
        }
    }

    var guidance: String {
        switch self {
        case .available:
            return String(
                localized: "Apple’s server model. This build includes Apple’s Private Cloud Compute entitlement."
            )
        case .unsupportedOS:
            return AppleIntelligenceCloudSupport.unavailableReason
        case .missingEntitlement:
            return AppleIntelligenceModel.privateCloudComputeEntitlementMessage
        case .deviceNotEligible:
            return String(localized: "This Mac cannot use Private Cloud Compute.")
        case .systemNotReady:
            return String(
                localized: "Private Cloud Compute is not ready yet. Turn on Apple Intelligence, stay online, and try again."
            )
        case .unavailable:
            return String(localized: "Private Cloud Compute is not available right now.")
        }
    }

    var showsSettingsButton: Bool {
        switch self {
        case .systemNotReady, .deviceNotEligible:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class AppleIntelligenceService: ObservableObject {
    static let shared = AppleIntelligenceService()

    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "AppleIntelligenceService"
    )
    private let runner = AppleIntelligenceSessionRunner()
    private var lifecycleObserver: AnyCancellable?
    private static let cachedStatus = OSAllocatedUnfairLock(
        initialState: AppleIntelligenceAvailabilityStatus.unavailable
    )
    private static let cachedCloudStatus = OSAllocatedUnfairLock(
        initialState: AppleIntelligenceCloudAvailabilityStatus.unavailable
    )
    private static let cachedOnDeviceVariantName = OSAllocatedUnfairLock(
        initialState: String?.none
    )

    @Published private(set) var status: AppleIntelligenceAvailabilityStatus
    @Published private(set) var cloudStatus: AppleIntelligenceCloudAvailabilityStatus
    @Published private(set) var onDeviceVariantName: String?

    nonisolated var isReady: Bool {
        Self.cachedStatus.withLock(\.isReady)
    }

    nonisolated var isProviderUsable: Bool {
        isReady || isCloudReady
    }

    nonisolated var isCloudReady: Bool {
        Self.cachedCloudStatus.withLock(\.isReady)
    }

    nonisolated var currentStatus: AppleIntelligenceAvailabilityStatus {
        Self.cachedStatus.withLock { $0 }
    }

    nonisolated var currentCloudStatus: AppleIntelligenceCloudAvailabilityStatus {
        Self.cachedCloudStatus.withLock { $0 }
    }

    nonisolated func isReady(for model: AppleIntelligenceModel) -> Bool {
        switch model {
        case .onDevice:
            return isReady
        case .privateCloudCompute:
            return isCloudReady
        }
    }

    nonisolated func guidance(for model: AppleIntelligenceModel) -> String {
        switch model {
        case .onDevice:
            return currentStatus.guidance
        case .privateCloudCompute:
            return currentCloudStatus.guidance
        }
    }

    private init() {
        let initialStatus = Self.resolveAvailability()
        let initialCloudStatus = Self.resolveCloudAvailability()
        let initialVariantName = Self.resolveOnDeviceVariantName()
        Self.cachedStatus.withLock { $0 = initialStatus }
        Self.cachedCloudStatus.withLock { $0 = initialCloudStatus }
        Self.cachedOnDeviceVariantName.withLock { $0 = initialVariantName }
        status = initialStatus
        cloudStatus = initialCloudStatus
        onDeviceVariantName = initialVariantName
        lifecycleObserver = LifecycleObserver.shared.publisher(
            for: [.applicationDidBecomeActive, .systemDidWake]
        )
        .sink { [weak self] _ in
            self?.refreshAvailability()
        }
    }

    nonisolated func refreshAvailability() {
        let resolvedStatus = Self.resolveAvailability()
        let resolvedCloudStatus = Self.resolveCloudAvailability()
        let resolvedVariantName = Self.resolveOnDeviceVariantName()
        Self.cachedStatus.withLock { $0 = resolvedStatus }
        Self.cachedCloudStatus.withLock { $0 = resolvedCloudStatus }
        Self.cachedOnDeviceVariantName.withLock { $0 = resolvedVariantName }
        Task { @MainActor in
            self.publishAvailability(
                resolvedStatus,
                cloudStatus: resolvedCloudStatus,
                onDeviceVariantName: resolvedVariantName
            )
        }
    }

    private func publishAvailability(
        _ resolvedStatus: AppleIntelligenceAvailabilityStatus,
        cloudStatus resolvedCloudStatus: AppleIntelligenceCloudAvailabilityStatus,
        onDeviceVariantName resolvedVariantName: String?
    ) {
        let statusChanged = status != resolvedStatus
        let cloudChanged = cloudStatus != resolvedCloudStatus
        let variantChanged = onDeviceVariantName != resolvedVariantName
        guard statusChanged || cloudChanged || variantChanged else { return }

        if statusChanged {
            status = resolvedStatus
        }
        if cloudChanged {
            cloudStatus = resolvedCloudStatus
        }
        if variantChanged {
            onDeviceVariantName = resolvedVariantName
        }
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Siri-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.siri",
        ].compactMap(URL.init(string:))

        for url in urls where NSWorkspace.shared.open(url) {
            return
        }
    }

    func enhance(
        systemPrompt: String,
        userPrompt: String,
        modelName: String?,
        timeout: TimeInterval = AppleIntelligenceLimits.requestTimeout
    ) async throws -> AppleIntelligenceEnhanceResult {
        refreshAvailability()
        let resolvedModel = AppleIntelligenceModel.resolved(from: modelName)
        guard isReady(for: resolvedModel) else {
            throw EnhancementError.customError(guidance(for: resolvedModel))
        }

        do {
            let runner = self.runner
            let result = try await AppleIntelligenceTaskTimeout.run(timeout) {
                try await runner.enhance(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    model: resolvedModel
                )
            }
            logger.debug(
                "Apple Intelligence enhancement completed model=\(result.modelLabel, privacy: .public)"
            )
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as EnhancementError {
            throw error
        } catch {
            throw AppleIntelligenceGenerationError.map(error, model: resolvedModel)
        }
    }

    private nonisolated static func resolveAvailability() -> AppleIntelligenceAvailabilityStatus {
        guard #available(macOS 26, *) else {
            return .unsupportedOS
        }

        #if canImport(FoundationModels)
            let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
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
                    return .unavailable
                }
            }
        #else
            return .unsupportedOS
        #endif
    }

    private nonisolated static func resolveCloudAvailability() -> AppleIntelligenceCloudAvailabilityStatus {
        guard #available(macOS 27, *) else {
            return .unsupportedOS
        }

        guard AppleIntelligenceCloudSupport.hasPrivateCloudComputeEntitlement else {
            return .missingEntitlement
        }

        guard AppleIntelligenceCloudSupport.isCallableWithCurrentSDK else {
            return .unsupportedOS
        }

        #if canImport(FoundationModels)
            let model = PrivateCloudComputeLanguageModel()
            switch model.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .deviceNotEligible
                case .systemNotReady:
                    return .systemNotReady
                @unknown default:
                    return .unavailable
                }
            }
        #else
            return .unsupportedOS
        #endif
    }

    private nonisolated static func resolveOnDeviceVariantName() -> String? {
        guard #available(macOS 27, *) else {
            return nil
        }

        #if canImport(FoundationModels)
            let model = SystemLanguageModel(
                useCase: .general,
                guardrails: .permissiveContentTransformations
            )
            guard model.isAvailable else {
                return nil
            }
            return model.variant.displayName
        #else
            return nil
        #endif
    }
}

enum AppleIntelligenceTaskTimeout {
    static func run<T: Sendable>(
        _ timeout: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let finished = OSAllocatedUnfairLock(initialState: false)

            func resumeOnce(_ result: Result<T, Error>) {
                let shouldResume = finished.withLock { isFinished -> Bool in
                    if isFinished {
                        return false
                    }
                    isFinished = true
                    return true
                }
                guard shouldResume else { return }
                continuation.resume(with: result)
            }

            let work = Task {
                do {
                    let value = try await operation()
                    resumeOnce(.success(value))
                } catch {
                    resumeOnce(.failure(error))
                }
            }

            Task {
                let nanoseconds = UInt64(max(timeout, 1) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                work.cancel()
                resumeOnce(.failure(EnhancementError.timeout))
            }
        }
    }
}

enum AppleIntelligenceGenerationError {
    static func map(_ error: Error, model: AppleIntelligenceModel = .onDevice) -> EnhancementError {
        #if canImport(FoundationModels)
            if #available(macOS 26, *),
                let generationError = error as? LanguageModelSession.GenerationError
            {
                switch generationError {
                case .exceededContextWindowSize:
                    return .customError(
                        String(
                            localized: "The transcript and context are too long for Apple Intelligence. Try a shorter recording or turn off extra context."
                        )
                    )
                case .assetsUnavailable, .unsupportedLanguageOrLocale:
                    return .customError(
                        String(localized: "Apple Intelligence could not load the on-device model. Try again in a moment.")
                    )
                case .guardrailViolation, .refusal:
                    return .guardrailViolation
                case .rateLimited, .concurrentRequests:
                    return .rateLimitExceeded
                case .decodingFailure, .unsupportedGuide:
                    return .enhancementFailed
                @unknown default:
                    break
                }
            }

            if #available(macOS 27, *),
                let cloudError = error as? PrivateCloudComputeLanguageModel.Error
            {
                switch cloudError {
                case .networkFailure:
                    return .customError(
                        String(localized: "Private Cloud Compute could not reach Apple. Check the network and try again.")
                    )
                case .quotaLimitReached:
                    return .rateLimitExceeded
                case .serviceUnavailable:
                    return .customError(
                        String(localized: "Private Cloud Compute is temporarily unavailable. Try again in a moment.")
                    )
                }
            }

            if #available(macOS 27, *),
                let languageModelError = error as? LanguageModelError
            {
                switch languageModelError {
                case .contextSizeExceeded:
                    return .customError(
                        String(
                            localized: "The transcript and context are too long for Apple Intelligence. Try a shorter recording or turn off extra context."
                        )
                    )
                case .rateLimited:
                    return .rateLimitExceeded
                case .guardrailViolation, .refusal:
                    return .guardrailViolation
                case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide,
                    .unsupportedLanguageOrLocale:
                    break
                default:
                    break
                }
            }
        #endif

        if let enhancementError = error as? EnhancementError {
            return enhancementError
        }

        if model == .privateCloudCompute {
            return .customError(AppleIntelligenceModel.privateCloudComputeEntitlementMessage)
        }

        return .customError(error.localizedDescription)
    }
}

actor AppleIntelligenceSessionRunner {
    func enhance(
        systemPrompt: String,
        userPrompt: String,
        model: AppleIntelligenceModel
    ) async throws -> AppleIntelligenceEnhanceResult {
        try Task.checkCancellation()

        switch model {
        case .onDevice:
            return try await enhanceOnDevice(systemPrompt: systemPrompt, userPrompt: userPrompt)
        case .privateCloudCompute:
            return try await enhancePrivateCloudCompute(systemPrompt: systemPrompt, userPrompt: userPrompt)
        }
    }

    private func enhanceOnDevice(systemPrompt: String, userPrompt: String) async throws -> AppleIntelligenceEnhanceResult {
        guard #available(macOS 26, *) else {
            throw EnhancementError.customError(
                String(localized: "Apple Intelligence enhancement requires macOS 26 or later.")
            )
        }

        #if canImport(FoundationModels)
            let model = SystemLanguageModel(
                useCase: .general,
                guardrails: .permissiveContentTransformations
            )
            guard model.isAvailable else {
                throw EnhancementError.customError(
                    String(localized: "Apple Intelligence is not available right now.")
                )
            }

            let options = GenerationOptions(temperature: 0.4)
            let session = LanguageModelSession(model: model, instructions: systemPrompt)
            let text = try await unconstrainedTranscript(
                session: session,
                userPrompt: userPrompt,
                options: options
            )
            return AppleIntelligenceEnhanceResult(
                text: text,
                modelLabel: Self.onDeviceModelLabel(for: model)
            )
        #else
            throw EnhancementError.customError(
                String(localized: "This build of VoiceInk was compiled without Foundation Models.")
            )
        #endif
    }

    private func enhancePrivateCloudCompute(systemPrompt: String, userPrompt: String) async throws -> AppleIntelligenceEnhanceResult {
        guard AppleIntelligenceCloudSupport.isCallableWithCurrentSDK else {
            throw EnhancementError.customError(AppleIntelligenceCloudSupport.unavailableReason)
        }

        guard #available(macOS 27, *) else {
            throw EnhancementError.customError(AppleIntelligenceCloudSupport.unavailableReason)
        }

        #if canImport(FoundationModels)
            let model = PrivateCloudComputeLanguageModel()
            guard model.isAvailable else {
                throw EnhancementError.customError(
                    String(localized: "Private Cloud Compute is not available right now.")
                )
            }

            if model.quotaUsage.isLimitReached {
                throw EnhancementError.rateLimitExceeded
            }

            let options = GenerationOptions(temperature: 0.4)
            let session = LanguageModelSession(model: model, instructions: systemPrompt)
            let text = try await unconstrainedTranscript(
                session: session,
                userPrompt: userPrompt,
                options: options
            )
            return AppleIntelligenceEnhanceResult(
                text: text,
                modelLabel: AppleIntelligenceModel.privateCloudCompute.rawValue
            )
        #else
            throw EnhancementError.customError(AppleIntelligenceCloudSupport.unavailableReason)
        #endif
    }

    #if canImport(FoundationModels)
        @available(macOS 26, *)
        private static func onDeviceModelLabel(for model: SystemLanguageModel) -> String {
            if #available(macOS 27, *) {
                let variantName = model.variant.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !variantName.isEmpty {
                    return "On-Device (\(variantName))"
                }
            }
            return AppleIntelligenceModel.onDevice.rawValue
        }

        @available(macOS 26, *)
        private func unconstrainedTranscript(
            session: LanguageModelSession,
            userPrompt: String,
            options: GenerationOptions
        ) async throws -> String {
            let response = try await session.respond(to: userPrompt, options: options)
            let text = AppleIntelligenceOutputSanitizer.sanitize(response.content)
            guard !text.isEmpty else {
                throw EnhancementError.enhancementFailed
            }
            return text
        }
    #endif
}
