import Foundation
import AppKit

struct ApplicationState: Codable {
    var isEnhancementEnabled: Bool
    var useScreenCaptureContext: Bool
    var selectedPromptId: String?
    var selectedLanguage: String?
    var transcriptionModelName: String?
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
                isEnhancementEnabled: enhancementService.isEnhancementEnabled,
                useScreenCaptureContext: enhancementService.useScreenCaptureContext,
                selectedPromptId: enhancementService.selectedPromptId?.uuidString,
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
            isEnhancementEnabled: enhancementService.isEnhancementEnabled,
            useScreenCaptureContext: enhancementService.useScreenCaptureContext,
            selectedPromptId: enhancementService.selectedPromptId?.uuidString,
            selectedLanguage: UserDefaults.standard.string(forKey: "SelectedLanguage"),
            transcriptionModelName: whisperState.currentTranscriptionModel?.name
        )
        
        session.originalState = updatedState
        saveSession(session)
    }

    private func applyConfiguration(_ config: PowerModeConfig) async {
        guard let enhancementService = enhancementService else { return }

        await MainActor.run {
            enhancementService.isEnhancementEnabled = config.isAIEnhancementEnabled
            enhancementService.useScreenCaptureContext = config.useScreenCapture

            if config.isAIEnhancementEnabled {
                if let promptId = config.selectedPrompt, let uuid = UUID(uuidString: promptId) {
                    enhancementService.selectedPromptId = uuid
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
            enhancementService.isEnhancementEnabled = state.isEnhancementEnabled
            enhancementService.useScreenCaptureContext = state.useScreenCaptureContext
            enhancementService.selectedPromptId = state.selectedPromptId.flatMap(UUID.init)

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
