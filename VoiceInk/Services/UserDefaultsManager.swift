import Foundation

enum UserDefaultsKeys {
    // MARK: - Transcription Service
    enum TranscriptionService {
        static let transcriptionServiceType = "TranscriptionServiceType"
        static let cloudTranscriptionApiKey = "CloudTranscriptionApiKey"
        static let cloudTranscriptionApiEndpoint = "CloudTranscriptionApiEndpoint"
        static let cloudTranscriptionModelName = "CloudTranscriptionModelName"
        static let cloudTranscriptionLanguage = "CloudTranscriptionLanguage"
        static let selectedLanguage = "SelectedLanguage"
        static let transcriptionPrompt = "TranscriptionPrompt"
        static let currentModel = "CurrentModel"
    }
    
    // MARK: - Word Replacement
    enum WordReplacement {
        static let isEnabled = "IsWordReplacementEnabled"
        static let replacements = "wordReplacements"
    }
    
    // MARK: - Auto Copy
    enum AutoCopy {
        static let isEnabled = "IsAutoCopyEnabled"
    }
    
    // MARK: - Recorder
    enum Recorder {
        static let type = "RecorderType"
    }
    
    // MARK: - Ollama Service
    enum Ollama {
        static let baseURL = "ollamaBaseURL"
        static let selectedModel = "ollamaSelectedModel"
    }
    
    // MARK: - AI Enhancement
    enum AIEnhancement {
        static let isEnabled = "isAIEnhancementEnabled"
        static let useClipboardContext = "useClipboardContext"
        static let useScreenCaptureContext = "useScreenCaptureContext"
        static let assistantTriggerWord = "assistantTriggerWord"
        static let customPrompts = "customPrompts"
        static let selectedPromptId = "selectedPromptId"
    }
    
    // MARK: - Audio Device
    enum AudioDevice {
        static let inputMode = "audioInputMode"
        static let selectedDeviceID = "selectedAudioDeviceID"
        static let prioritizedDevices = "prioritizedDevices"
    }
    
    // MARK: - Dictionary
    enum Dictionary {
        static let data = "dictionary_data"
    }
    
    // MARK: - Menu Bar
    enum MenuBar {
        static let isMenuBarOnly = "IsMenuBarOnly"
    }
    
    // MARK: - Media Control
    enum Media {
        static let isPauseEnabled = "isMediaPauseEnabled"
    }
    
    // MARK: - Power Mode
    enum PowerMode {
        static let isEnabled = "PowerModeEnabled"
        static let defaultConfig = "PowerModeDefaultConfig"
        static let config = "PowerModeConfig"
    }
    
    // MARK: - Push To Talk
    enum PushToTalk {
        static let isEnabled = "isPushToTalkEnabled"
        static let key = "pushToTalkKey"
    }
    
    // MARK: - Audio Cleanup
    enum AudioCleanup {
        static let retentionPeriod = "AudioRetentionPeriod"
        static let isEnabled = "IsAudioCleanupEnabled"
    }
    
    // MARK: - Paste Method
    enum Paste {
        static let useAppleScriptPaste = "UseAppleScriptPaste"
    }
    
    // MARK: - Custom Provider
    enum CustomProvider {
        static let baseURL = "customProviderBaseURL"
        static let model = "customProviderModel"
    }
    
    // MARK: - License
    enum License {
        static let key = "VoiceInkLicense"
        static let trialStartDate = "VoiceInkTrialStartDate"
        static let activationId = "VoiceInkActivationId"
        static let aiProviderApiKey = "VoiceInkAIProviderKey"
    }
    
    // MARK: - Whisper Prompts
    enum WhisperPrompts {
        static let savedPrompts = "WhisperPrompts"
    }
}

extension UserDefaults {
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
    
    // MARK: - Word Replacement
    var isWordReplacementEnabled: Bool {
        get { bool(forKey: UserDefaultsKeys.WordReplacement.isEnabled) }
        set { set(newValue, forKey: UserDefaultsKeys.WordReplacement.isEnabled) }
    }
    
    var wordReplacements: [String: String] {
        get { dictionary(forKey: UserDefaultsKeys.WordReplacement.replacements) as? [String: String] ?? [:] }
        set { set(newValue, forKey: UserDefaultsKeys.WordReplacement.replacements) }
    }
    
    // MARK: - Paste Method
    var useAppleScriptPaste: Bool {
        get { bool(forKey: UserDefaultsKeys.Paste.useAppleScriptPaste) }
        set { set(newValue, forKey: UserDefaultsKeys.Paste.useAppleScriptPaste) }
    }
    
    // MARK: - Auto Copy
    var isAutoCopyEnabled: Bool {
        get { bool(forKey: UserDefaultsKeys.AutoCopy.isEnabled) }
        set { set(newValue, forKey: UserDefaultsKeys.AutoCopy.isEnabled) }
    }
    
    // MARK: - Menu Bar
    var isMenuBarOnly: Bool {
        get { bool(forKey: UserDefaultsKeys.MenuBar.isMenuBarOnly) }
        set { set(newValue, forKey: UserDefaultsKeys.MenuBar.isMenuBarOnly) }
    }
    
    // MARK: - Recorder
    var recorderType: String {
        get { string(forKey: UserDefaultsKeys.Recorder.type) ?? "mini" }
        set { set(newValue, forKey: UserDefaultsKeys.Recorder.type) }
    }
    
    // MARK: - Media Control
    var isMediaPauseEnabled: Bool {
        get { bool(forKey: UserDefaultsKeys.Media.isPauseEnabled) }
        set { set(newValue, forKey: UserDefaultsKeys.Media.isPauseEnabled) }
    }
    
    // MARK: - Push To Talk
    var isPushToTalkEnabled: Bool {
        get { bool(forKey: UserDefaultsKeys.PushToTalk.isEnabled) }
        set { set(newValue, forKey: UserDefaultsKeys.PushToTalk.isEnabled) }
    }
    
    var pushToTalkKey: String {
        get { string(forKey: UserDefaultsKeys.PushToTalk.key) ?? "" }
        set { set(newValue, forKey: UserDefaultsKeys.PushToTalk.key) }
    }
    
    // MARK: - AI Enhancement
    var isAIEnhancementEnabled: Bool {
        get { bool(forKey: UserDefaultsKeys.AIEnhancement.isEnabled) }
        set { set(newValue, forKey: UserDefaultsKeys.AIEnhancement.isEnabled) }
    }
    
    var useClipboardContext: Bool {
        get { bool(forKey: UserDefaultsKeys.AIEnhancement.useClipboardContext) }
        set { set(newValue, forKey: UserDefaultsKeys.AIEnhancement.useClipboardContext) }
    }
    
    var useScreenCaptureContext: Bool {
        get { bool(forKey: UserDefaultsKeys.AIEnhancement.useScreenCaptureContext) }
        set { set(newValue, forKey: UserDefaultsKeys.AIEnhancement.useScreenCaptureContext) }
    }
    
    var assistantTriggerWord: String {
        get { string(forKey: UserDefaultsKeys.AIEnhancement.assistantTriggerWord) ?? "hey" }
        set { set(newValue, forKey: UserDefaultsKeys.AIEnhancement.assistantTriggerWord) }
    }
    
    var aiEnhancementCustomPrompts: Data? {
        get { data(forKey: UserDefaultsKeys.AIEnhancement.customPrompts) }
        set { set(newValue, forKey: UserDefaultsKeys.AIEnhancement.customPrompts) }
    }
    
    var selectedPromptId: String? {
        get { string(forKey: UserDefaultsKeys.AIEnhancement.selectedPromptId) }
        set { set(newValue, forKey: UserDefaultsKeys.AIEnhancement.selectedPromptId) }
    }
    
    // MARK: - Ollama
    var ollamaBaseURL: String {
        get { string(forKey: UserDefaultsKeys.Ollama.baseURL) ?? "http://localhost:11434" }
        set { set(newValue, forKey: UserDefaultsKeys.Ollama.baseURL) }
    }
    
    var ollamaSelectedModel: String {
        get { string(forKey: UserDefaultsKeys.Ollama.selectedModel) ?? "llama2" }
        set { set(newValue, forKey: UserDefaultsKeys.Ollama.selectedModel) }
    }
    
    // MARK: - Custom Provider
    var customProviderBaseURL: String {
        get { string(forKey: UserDefaultsKeys.CustomProvider.baseURL) ?? "" }
        set { set(newValue, forKey: UserDefaultsKeys.CustomProvider.baseURL) }
    }
    
    var customProviderModel: String {
        get { string(forKey: UserDefaultsKeys.CustomProvider.model) ?? "" }
        set { set(newValue, forKey: UserDefaultsKeys.CustomProvider.model) }
    }
    
    // MARK: - Audio Device
    var audioInputMode: String? {
        get { string(forKey: UserDefaultsKeys.AudioDevice.inputMode) }
        set { set(newValue, forKey: UserDefaultsKeys.AudioDevice.inputMode) }
    }
    
    var selectedAudioDeviceID: Any? {
        get { object(forKey: UserDefaultsKeys.AudioDevice.selectedDeviceID) }
        set { set(newValue, forKey: UserDefaultsKeys.AudioDevice.selectedDeviceID) }
    }
    
    var prioritizedDevices: Data? {
        get { data(forKey: UserDefaultsKeys.AudioDevice.prioritizedDevices) }
        set { set(newValue, forKey: UserDefaultsKeys.AudioDevice.prioritizedDevices) }
    }
    
    // MARK: - Transcription Service
    var selectedLanguage: String? {
        get { string(forKey: UserDefaultsKeys.TranscriptionService.selectedLanguage) }
        set { set(newValue, forKey: UserDefaultsKeys.TranscriptionService.selectedLanguage) }
    }
    
    var transcriptionPrompt: String {
        get { string(forKey: UserDefaultsKeys.TranscriptionService.transcriptionPrompt) ?? "" }
        set { set(newValue, forKey: UserDefaultsKeys.TranscriptionService.transcriptionPrompt) }
    }
    
    var currentModel: String? {
        get { string(forKey: UserDefaultsKeys.TranscriptionService.currentModel) }
        set { set(newValue, forKey: UserDefaultsKeys.TranscriptionService.currentModel) }
    }
    
    var cloudTranscriptionLanguage: String? {
        get { string(forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionLanguage) }
        set { set(newValue, forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionLanguage) }
    }
    
    // MARK: - Transcription Service
    var transcriptionServiceType: TranscriptionServiceType {
        get {
            if let rawValue = string(forKey: UserDefaultsKeys.TranscriptionService.transcriptionServiceType),
               let type = TranscriptionServiceType(rawValue: rawValue)
            {
                return type
            }
            return .local // Default to local if not set
        }
        set {
            set(newValue.rawValue, forKey: UserDefaultsKeys.TranscriptionService.transcriptionServiceType)
        }
    }
    
    var cloudTranscriptionApiKey: String {
        get { string(forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionApiKey) ?? "" }
        set { set(newValue, forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionApiKey) }
    }
    
    var cloudTranscriptionApiEndpoint: String {
        get { string(forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionApiEndpoint) ?? "https://api.openai.com/v1/audio/transcriptions" }
        set { set(newValue, forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionApiEndpoint) }
    }
    
    var cloudTranscriptionModelName: String {
        get { string(forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionModelName) ?? "gpt-4o-transcribe" }
        set { set(newValue, forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionModelName) }
    }
    
    // MARK: - License
    var aiProviderApiKey: String? {
        get { string(forKey: UserDefaultsKeys.License.aiProviderApiKey) }
        set { setValue(newValue, forKey: UserDefaultsKeys.License.aiProviderApiKey) }
    }
    
    var licenseKey: String? {
        get { string(forKey: UserDefaultsKeys.License.key) }
        set { setValue(newValue, forKey: UserDefaultsKeys.License.key) }
    }
    
    var trialStartDate: Date? {
        get { object(forKey: UserDefaultsKeys.License.trialStartDate) as? Date }
        set { setValue(newValue, forKey: UserDefaultsKeys.License.trialStartDate) }
    }
    
    var activationId: String? {
        get { string(forKey: UserDefaultsKeys.License.activationId) }
        set { setValue(newValue, forKey: UserDefaultsKeys.License.activationId) }
    }
}
