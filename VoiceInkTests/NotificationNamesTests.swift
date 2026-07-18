import Foundation
import Testing

@testable import VoiceInk

// A duplicate raw string here would make two logically distinct
// notifications collide silently at runtime — cheap to catch, easy to miss
// by eye in a 20-entry list.
struct NotificationNamesTests {

    @Test func everyDefinedNotificationNameIsUnique() {
        let names: [Notification.Name] = [
            .AppSettingsDidChange,
            .languageDidChange,
            .promptDidChange,
            .toggleRecorderPanel,
            .dismissRecorderPanel,
            .didChangeModel,
            .aiProviderKeyChanged,
            .licenseStatusChanged,
            .licenseCelebrationRequested,
            .navigateToDestination,
            .showMainWindowRequested,
            .modeConfigurationApplied,
            .modeConfigurationsDidChange,
            .modeShortcutAvailabilityDidChange,
            .transcriptionCreated,
            .transcriptionCompleted,
            .transcriptionDeleted,
            .sessionMetricsDidChange,
            .openFileForTranscription,
            .audioDeviceSwitchRequired,
        ]

        let rawValues = names.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }
}
