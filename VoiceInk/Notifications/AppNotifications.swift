import Foundation

extension Notification.Name {
    static let AppSettingsDidChange = Notification.Name("appSettingsDidChange")
    static let languageDidChange = Notification.Name("languageDidChange")
    static let promptDidChange = Notification.Name("promptDidChange")
    static let toggleRecorder = Notification.Name("toggleRecorder")
    static let dismissRecorder = Notification.Name("dismissRecorder")
    static let didChangeModel = Notification.Name("didChangeModel")
    static let aiProviderKeyChanged = Notification.Name("aiProviderKeyChanged")
    static let licenseStatusChanged = Notification.Name("licenseStatusChanged")
    static let navigateToDestination = Notification.Name("navigateToDestination")
    static let promptSelectionChanged = Notification.Name("promptSelectionChanged")
    static let powerModeConfigurationApplied = Notification.Name("powerModeConfigurationApplied")
    static let transcriptionCreated = Notification.Name("transcriptionCreated")
    static let transcriptionCompleted = Notification.Name("transcriptionCompleted")
    static let enhancementToggleChanged = Notification.Name("enhancementToggleChanged")
    static let openFileForTranscription = Notification.Name("openFileForTranscription")
}
