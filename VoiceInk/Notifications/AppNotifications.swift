import Foundation

extension Notification.Name {
    static let AppSettingsDidChange = Notification.Name("appSettingsDidChange")
    static let languageDidChange = Notification.Name("languageDidChange")
    static let promptDidChange = Notification.Name("promptDidChange")
    static let toggleMiniRecorder = Notification.Name("toggleMiniRecorder")
    static let dismissMiniRecorder = Notification.Name("dismissMiniRecorder")
    static let didChangeModel = Notification.Name("didChangeModel")
    static let aiProviderKeyChanged = Notification.Name("aiProviderKeyChanged")
    static let licenseStatusChanged = Notification.Name("licenseStatusChanged")
    static let navigateToDestination = Notification.Name("navigateToDestination")
    static let promptSelectionChanged = Notification.Name("promptSelectionChanged")
    static let modeConfigurationApplied = Notification.Name("modeConfigurationApplied")
    static let modeConfigurationsDidChange = Notification.Name("ModeConfigurationsDidChange")
    static let modeShortcutAvailabilityDidChange = Notification.Name("modeShortcutAvailabilityDidChange")
    static let transcriptionCreated = Notification.Name("transcriptionCreated")
    static let transcriptionCompleted = Notification.Name("transcriptionCompleted")
    static let transcriptionDeleted = Notification.Name("transcriptionDeleted")
    static let sessionMetricsDidChange = Notification.Name("sessionMetricsDidChange")
    static let enhancementToggleChanged = Notification.Name("enhancementToggleChanged")
    static let openFileForTranscription = Notification.Name("openFileForTranscription")
    static let audioDeviceSwitchRequired = Notification.Name("audioDeviceSwitchRequired")
}
