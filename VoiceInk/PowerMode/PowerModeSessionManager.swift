import Foundation
import AppKit

struct ApplicationState: Codable {
    var enhancementMode: String
    var useScreenCaptureContext: Bool
    var selectedPromptId: String?
    var selectedAIProvider: String?
    var selectedAIModel: String?
    var selectedLanguage: String?
    var transcriptionModelName: String?

    // Migration: decode old format with isEnhancementEnabled boolean
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let mode = try? container.decode(String.self, forKey: .enhancementMode) {
            self.enhancementMode = mode
        } else {
            // Fall back to old boolean key
            let wasEnabled = (try? container.decode(Bool.self, forKey: .enhancementMode)) ?? false
            self.enhancementMode = wasEnabled ? EnhancementMode.on.rawValue : EnhancementMode.off.rawValue
        }
        self.useScreenCaptureContext = try container.decode(Bool.self, forKey: .useScreenCaptureContext)
        self.selectedPromptId = try container.decodeIfPresent(String.self, forKey: .selectedPromptId)
        self.selectedAIProvider = try container.decodeIfPresent(String.self, forKey: .selectedAIProvider)
        self.selectedAIModel = try container.decodeIfPresent(String.self, forKey: .selectedAIModel)
        self.selectedLanguage = try container.decodeIfPresent(String.self, forKey: .selectedLanguage)
        self.transcriptionModelName = try container.decodeIfPresent(String.self, forKey: .transcriptionModelName)
    }

    init(enhancementMode: String, useScreenCaptureContext: Bool, selectedPromptId: String? = nil,
         selectedAIProvider: String? = nil, selectedAIModel: String? = nil,
         selectedLanguage: String? = nil, transcriptionModelName: String? = nil) {
        self.enhancementMode = enhancementMode
        self.useScreenCaptureContext = useScreenCaptureContext
        self.selectedPromptId = selectedPromptId
        self.selectedAIProvider = selectedAIProvider
        self.selectedAIModel = selectedAIModel
        self.selectedLanguage = selectedLanguage
        self.transcriptionModelName = transcriptionModelName
    }

    private enum CodingKeys: String, CodingKey {
        // Use the old key name for backward-compatible decoding
        case enhancementMode = "isEnhancementEnabled"
        case useScreenCaptureContext, selectedPromptId, selectedAIProvider
        case selectedAIModel, selectedLanguage, transcriptionModelName
    }
}

struct PowerModeSession: Codable {
    let id: UUID
    let startTime: Date
    var originalState: ApplicationState
}

@MainActor
class PowerModeSessionManager {
    static let shared = PowerModeSessionManager()
    private let sessionKey = "powerModeActiveSession.v1"
    private var isApplyingPowerModeConfig = false

    private var whisperState: WhisperState?
    private var enhancementService: AIEnhancementService?

    private init() {
        recoverSession()
    }

    func configure(whisperState: WhisperState, enhancementService: AIEnhancementService) {
        self.whisperState = whisperState
        self.enhancementService = enhancementService
    }

    func beginSession(with config: PowerModeConfig) async {
        guard let whisperState = whisperState, let enhancementService = enhancementService else {
            print("SessionManager not configured.")
            return
        }

        // Only capture baseline if NO session exists
        if loadSession() == nil {
            let originalState = ApplicationState(
                enhancementMode: enhancementService.enhancementMode.rawValue,
                useScreenCaptureContext: enhancementService.useScreenCaptureContext,
                selectedPromptId: enhancementService.selectedPromptId?.uuidString,
                selectedAIProvider: enhancementService.getAIService()?.selectedProvider.rawValue,
                selectedAIModel: enhancementService.getAIService()?.currentModel,
                selectedLanguage: UserDefaults.standard.string(forKey: "SelectedLanguage"),
                transcriptionModelName: whisperState.currentTranscriptionModel?.name
            )

            let newSession = PowerModeSession(
                id: UUID(),
                startTime: Date(),
                originalState: originalState
            )
            saveSession(newSession)

            NotificationCenter.default.addObserver(self, selector: #selector(updateSessionSnapshot), name: .AppSettingsDidChange, object: nil)
        }

        // Always apply the new configuration
        isApplyingPowerModeConfig = true
        await applyConfiguration(config)
        isApplyingPowerModeConfig = false
    }

    var hasActiveSession: Bool {
        return loadSession() != nil
    }

    func endSession() async {
        guard let session = loadSession() else { return }

        isApplyingPowerModeConfig = true
        await restoreState(session.originalState)
        isApplyingPowerModeConfig = false
        
        NotificationCenter.default.removeObserver(self, name: .AppSettingsDidChange, object: nil)

        clearSession()
    }
    
    @objc func updateSessionSnapshot() {
        guard !isApplyingPowerModeConfig else { return }
        
        guard var session = loadSession(), let whisperState = whisperState, let enhancementService = enhancementService else { return }

        let updatedState = ApplicationState(
            enhancementMode: enhancementService.enhancementMode.rawValue,
            useScreenCaptureContext: enhancementService.useScreenCaptureContext,
            selectedPromptId: enhancementService.selectedPromptId?.uuidString,
            selectedAIProvider: enhancementService.getAIService()?.selectedProvider.rawValue,
            selectedAIModel: enhancementService.getAIService()?.currentModel,
            selectedLanguage: UserDefaults.standard.string(forKey: "SelectedLanguage"),
            transcriptionModelName: whisperState.currentTranscriptionModel?.name
        )
        
        session.originalState = updatedState
        saveSession(session)
    }

    private func applyConfiguration(_ config: PowerModeConfig) async {
        guard let enhancementService = enhancementService else { return }

        await MainActor.run {
            // When PowerMode disables enhancement, set to .off
            // When PowerMode enables enhancement, leave the current mode (respects user's On/Background choice)
            if !config.isAIEnhancementEnabled {
                enhancementService.enhancementMode = .off
            } else if enhancementService.enhancementMode == .off {
                enhancementService.enhancementMode = .on
            }
            enhancementService.useScreenCaptureContext = config.useScreenCapture

            if config.isAIEnhancementEnabled {
                if let promptId = config.selectedPrompt, let uuid = UUID(uuidString: promptId) {
                    enhancementService.selectedPromptId = uuid
                }

                if let aiService = enhancementService.getAIService() {
                    if let providerName = config.selectedAIProvider, let provider = AIProvider(rawValue: providerName) {
                        aiService.selectedProvider = provider
                    }
                    if let model = config.selectedAIModel {
                        aiService.selectModel(model)
                    }
                }
            }

            if let language = config.selectedLanguage {
                UserDefaults.standard.set(language, forKey: "SelectedLanguage")
                NotificationCenter.default.post(name: .languageDidChange, object: nil)
            }
        }

        if let whisperState = whisperState,
           let modelName = config.selectedTranscriptionModelName,
           let selectedModel = await whisperState.allAvailableModels.first(where: { $0.name == modelName }),
           whisperState.currentTranscriptionModel?.name != modelName {
            await handleModelChange(to: selectedModel)
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .powerModeConfigurationApplied, object: nil)
        }
    }

    private func restoreState(_ state: ApplicationState) async {
        guard let enhancementService = enhancementService else { return }

        await MainActor.run {
            enhancementService.enhancementMode = EnhancementMode(rawValue: state.enhancementMode) ?? .off
            enhancementService.useScreenCaptureContext = state.useScreenCaptureContext
            enhancementService.selectedPromptId = state.selectedPromptId.flatMap(UUID.init)

            if let aiService = enhancementService.getAIService() {
                if let providerName = state.selectedAIProvider, let provider = AIProvider(rawValue: providerName) {
                    aiService.selectedProvider = provider
                }
                if let model = state.selectedAIModel {
                    aiService.selectModel(model)
                }
            }

            if let language = state.selectedLanguage {
                UserDefaults.standard.set(language, forKey: "SelectedLanguage")
                NotificationCenter.default.post(name: .languageDidChange, object: nil)
            }
        }

        if let whisperState = whisperState,
           let modelName = state.transcriptionModelName,
           let selectedModel = await whisperState.allAvailableModels.first(where: { $0.name == modelName }),
           whisperState.currentTranscriptionModel?.name != modelName {
            await handleModelChange(to: selectedModel)
        }
    }
    
    private func handleModelChange(to newModel: any TranscriptionModel) async {
        guard let whisperState = whisperState else { return }

        await whisperState.setDefaultTranscriptionModel(newModel)

        switch newModel.provider {
        case .local:
            await whisperState.cleanupModelResources()
            if let localModel = await whisperState.availableModels.first(where: { $0.name == newModel.name }) {
                do {
                    try await whisperState.loadModel(localModel)
                } catch {
                    print("Power Mode: Failed to load local model '\(localModel.name)': \(error)")
                }
            }
        case .parakeet:
            await whisperState.cleanupModelResources()

        default:
            await whisperState.cleanupModelResources()
        }
    }
    
    private func recoverSession() {
        guard let session = loadSession() else { return }
        print("Recovering abandoned Power Mode session.")
        Task {
            await endSession()
        }
    }

    private func saveSession(_ session: PowerModeSession) {
        do {
            let data = try JSONEncoder().encode(session)
            UserDefaults.standard.set(data, forKey: sessionKey)
        } catch {
            print("Error saving Power Mode session: \(error)")
        }
    }
    
    private func loadSession() -> PowerModeSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey) else { return nil }
        do {
            return try JSONDecoder().decode(PowerModeSession.self, from: data)
        } catch {
            print("Error loading Power Mode session: \(error)")
            return nil
        }
    }

    private func clearSession() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }
}
