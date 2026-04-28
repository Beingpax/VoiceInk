import Foundation
import SwiftUI

struct LanguageMode: Codable, Identifiable, Equatable {
    var id: UUID
    var transcriptionModelName: String?
    var language: String

    init(
        id: UUID = UUID(),
        transcriptionModelName: String? = nil,
        language: String = "auto"
    ) {
        self.id = id
        self.transcriptionModelName = transcriptionModelName
        self.language = language
    }

    enum CodingKeys: String, CodingKey {
        case id, transcriptionModelName, language
    }

    var displayName: String {
        if language == "auto" { return "Auto-detect" }
        return LanguageDictionary.all[language] ?? language.uppercased()
    }

    var emoji: String {
        Self.flag(forLanguage: language)
    }

    static func flag(forLanguage code: String) -> String {
        // Use BCP-47 region if present (e.g. "en-GB" → 🇬🇧).
        if let dash = code.firstIndex(of: "-") {
            let region = String(code[code.index(after: dash)...]).uppercased()
            if region.count == 2, let flag = regionFlag(region) { return flag }
        }
        return languageFlags[code.lowercased()] ?? "🌐"
    }

    private static func regionFlag(_ region: String) -> String? {
        let base: UInt32 = 127397
        var s = ""
        for ch in region.unicodeScalars {
            guard let scalar = UnicodeScalar(base + ch.value) else { return nil }
            s.unicodeScalars.append(scalar)
        }
        return s.isEmpty ? nil : s
    }

    private static let languageFlags: [String: String] = [
        "auto": "🌐",
        "en": "🇬🇧", "de": "🇩🇪", "es": "🇪🇸", "fr": "🇫🇷", "it": "🇮🇹",
        "pt": "🇵🇹", "nl": "🇳🇱", "pl": "🇵🇱", "ru": "🇷🇺", "ja": "🇯🇵",
        "zh": "🇨🇳", "yue": "🇭🇰", "ko": "🇰🇷", "ar": "🇸🇦", "hi": "🇮🇳",
        "tr": "🇹🇷", "sv": "🇸🇪", "da": "🇩🇰", "no": "🇳🇴", "fi": "🇫🇮",
        "cs": "🇨🇿", "el": "🇬🇷", "he": "🇮🇱", "th": "🇹🇭", "vi": "🇻🇳",
        "id": "🇮🇩", "uk": "🇺🇦", "ro": "🇷🇴", "hu": "🇭🇺", "bg": "🇧🇬",
        "hr": "🇭🇷", "sk": "🇸🇰", "sl": "🇸🇮", "et": "🇪🇪", "lv": "🇱🇻",
        "lt": "🇱🇹", "mt": "🇲🇹", "is": "🇮🇸", "ga": "🇮🇪", "cy": "🇬🇧",
        "fa": "🇮🇷", "ur": "🇵🇰", "bn": "🇧🇩", "ta": "🇮🇳", "te": "🇮🇳",
        "ml": "🇮🇳", "kn": "🇮🇳", "mr": "🇮🇳", "gu": "🇮🇳", "pa": "🇮🇳",
        "sw": "🇰🇪", "af": "🇿🇦", "ms": "🇲🇾", "tl": "🇵🇭", "ca": "🇪🇸",
        "eu": "🇪🇸", "gl": "🇪🇸"
    ]
}

@MainActor
class LanguageModeManager: ObservableObject {
    static let shared = LanguageModeManager()

    @Published var modes: [LanguageMode] = []
    @Published var activeModeId: UUID?

    private let modesKey = "languageModesV1"
    private let activeIdKey = "activeLanguageModeId"

    private weak var stateProvider: (any PowerModeStateProvider)?
    private weak var engine: VoiceInkEngine?
    private weak var recorderUIManager: RecorderUIManager?

    private init() {
        loadModes()
        if let raw = UserDefaults.standard.string(forKey: activeIdKey) {
            activeModeId = UUID(uuidString: raw)
        }
    }

    func configure(engine: VoiceInkEngine, recorderUIManager: RecorderUIManager) {
        self.engine = engine
        self.stateProvider = engine
        self.recorderUIManager = recorderUIManager
    }

    private func loadModes() {
        guard let data = UserDefaults.standard.data(forKey: modesKey),
              let decoded = try? JSONDecoder().decode([LanguageMode].self, from: data) else { return }
        modes = decoded
    }

    func saveModes() {
        if let data = try? JSONEncoder().encode(modes) {
            UserDefaults.standard.set(data, forKey: modesKey)
        }
    }

    func addMode(_ mode: LanguageMode) {
        modes.append(mode)
        saveModes()
    }

    func updateMode(_ mode: LanguageMode) {
        guard let idx = modes.firstIndex(where: { $0.id == mode.id }) else { return }
        modes[idx] = mode
        saveModes()
    }

    func removeMode(id: UUID) {
        modes.removeAll { $0.id == id }
        if activeModeId == id { activeModeId = nil }
        saveModes()
    }

    func moveModes(fromOffsets: IndexSet, toOffset: Int) {
        modes.move(fromOffsets: fromOffsets, toOffset: toOffset)
        saveModes()
    }

    /// Replace all modes in one shot. Used by settings import to restore a backup.
    func replaceAll(modes newModes: [LanguageMode], activeId: UUID?) {
        modes = newModes
        saveModes()
        if let activeId = activeId, newModes.contains(where: { $0.id == activeId }) {
            activeModeId = activeId
            UserDefaults.standard.set(activeId.uuidString, forKey: activeIdKey)
        } else {
            activeModeId = nil
            UserDefaults.standard.removeObject(forKey: activeIdKey)
        }
    }

    var activeMode: LanguageMode? {
        guard let id = activeModeId else { return nil }
        return modes.first { $0.id == id }
    }

    /// Advance to the next mode in the list and apply it.
    /// If a recording is in progress, stop it (the current take transcribes normally),
    /// switch the mode, and start a new recording in the new language.
    func cycleToNext() async {
        guard !modes.isEmpty else {
            NotificationManager.shared.showNotification(
                title: "No Language Modes configured",
                type: .warning
            )
            return
        }

        let nextIndex: Int
        if let currentId = activeModeId,
           let currentIdx = modes.firstIndex(where: { $0.id == currentId }) {
            nextIndex = (currentIdx + 1) % modes.count
        } else {
            nextIndex = 0
        }

        let next = modes[nextIndex]

        let wasRecording = (engine?.recordingState == .recording) && (recorderUIManager?.isMiniRecorderVisible == true)

        if wasRecording, let recorderUIManager = recorderUIManager {
            // Stop the current take. This awaits transcription + paste + dismiss.
            await recorderUIManager.toggleMiniRecorder()
        }

        await apply(next)

        if wasRecording, let recorderUIManager = recorderUIManager {
            // Start a fresh recording in the new language.
            await recorderUIManager.toggleMiniRecorder()
        }
    }

    func setActive(id: UUID) async {
        guard let mode = modes.first(where: { $0.id == id }) else { return }
        await apply(mode)
    }

    private func apply(_ mode: LanguageMode) async {
        activeModeId = mode.id
        UserDefaults.standard.set(mode.id.uuidString, forKey: activeIdKey)

        UserDefaults.standard.set(mode.language, forKey: "SelectedLanguage")
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)

        if let modelName = mode.transcriptionModelName,
           let stateProvider = stateProvider,
           stateProvider.currentTranscriptionModel?.name != modelName,
           let selectedModel = stateProvider.allAvailableModels.first(where: { $0.name == modelName }) {
            if selectedModel.provider == .whisper,
               !stateProvider.availableModels.contains(where: { $0.name == modelName }) {
                NotificationManager.shared.showNotification(
                    title: "Model '\(selectedModel.displayName)' is not downloaded",
                    type: .error
                )
            } else {
                await switchModel(to: selectedModel, using: stateProvider)
            }
        }

        NotificationManager.shared.showNotification(
            title: "Mode: \(mode.emoji) \(mode.displayName)",
            type: .info,
            duration: 1.5
        )
    }

    private func switchModel(to newModel: any TranscriptionModel, using stateProvider: any PowerModeStateProvider) async {
        stateProvider.setDefaultTranscriptionModel(newModel)

        switch newModel.provider {
        case .whisper:
            await stateProvider.cleanupModelResources()
            if let whisperModel = stateProvider.availableModels.first(where: { $0.name == newModel.name }) {
                try? await stateProvider.loadModel(whisperModel)
            }
        default:
            await stateProvider.cleanupModelResources()
        }
    }
}
