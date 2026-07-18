import Testing

@testable import VoiceInk

struct ModeTriggerHelpersTests {

    @Test func triggerSnapshotCombinesDirectAndGroupedTriggers() {
        let directApp = AppConfig(bundleIdentifier: "com.apple.Terminal", appName: "Terminal")
        let directURL = URLConfig(url: "example.com")
        let group = ModeTriggerGroup(
            templateId: "slack",
            name: "Slack",
            appConfigs: [AppConfig(bundleIdentifier: "com.tinyspeck.slackmacgap", appName: "Slack")],
            urlConfigs: [URLConfig(url: "slack.com")]
        )

        let snapshot = TriggerSnapshot(
            appConfigs: [directApp],
            websiteConfigs: [directURL],
            triggerGroups: [group],
            cleanURL: { $0 }
        )

        #expect(snapshot.appBundleIds == ["com.apple.Terminal", "com.tinyspeck.slackmacgap"])
        #expect(snapshot.websites == ["example.com", "slack.com"])
        #expect(snapshot.templateIds == ["slack"])
    }

    @Test func triggerSnapshotAppliesCleanURLToEveryWebsite() {
        let snapshot = TriggerSnapshot(
            appConfigs: [],
            websiteConfigs: [URLConfig(url: "HTTPS://Example.com/")],
            triggerGroups: [],
            cleanURL: { $0.lowercased() }
        )

        #expect(snapshot.websites == ["https://example.com/"])
    }

    @Test func summaryTextForNoTriggers() {
        let group = ModeTriggerGroup(name: "Empty")
        #expect(group.summaryText == "No triggers")
    }

    @Test func summaryTextForAppsOnly() {
        let group = ModeTriggerGroup(
            name: "Apps", appConfigs: [AppConfig(bundleIdentifier: "a", appName: "A")], urlConfigs: [])
        // Foundation's String(localized:) grammar-agrees the interpolated count — singular for 1.
        #expect(group.summaryText == "1 app")
    }

    @Test func summaryTextForWebsitesOnly() {
        let group = ModeTriggerGroup(name: "Sites", appConfigs: [], urlConfigs: [URLConfig(url: "a.com"), URLConfig(url: "b.com")])
        #expect(group.summaryText == "2 websites")
    }

    @Test func summaryTextForBothAppsAndWebsites() {
        let group = ModeTriggerGroup(
            name: "Mixed",
            appConfigs: [AppConfig(bundleIdentifier: "a", appName: "A")],
            urlConfigs: [URLConfig(url: "a.com")]
        )
        #expect(group.summaryText == "1 app · 1 website")
    }
}
