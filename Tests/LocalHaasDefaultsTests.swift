import Foundation

@main
struct LocalHaasDefaultsTests {
    @MainActor static func main() async throws {
        let suite = "VoiceInkTests.HaasDefaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        LocalHaasSettings.registerDefaults(defaults: defaults)
        let models = try JSONDecoder().decode([CustomCloudModel].self, from: defaults.data(forKey: "customCloudModels")!)
        precondition(models.count == 1)
        precondition(models[0].selectionKey == defaults.string(forKey: "CurrentTranscriptionModel"))
        precondition(models[0].apiEndpoint == "voiceink-local://haas")
        precondition(models[0].apiKey.isEmpty)
        precondition(!models[0].supportsStreaming)
        precondition(models[0].supportedLanguages["auto"] != nil)
        let saved = Data("[]".utf8)
        defaults.set(saved, forKey: "customCloudModels")
        defaults.set("user-chosen-model", forKey: "CurrentTranscriptionModel")
        LocalHaasSettings.registerDefaults(defaults: defaults)
        precondition(defaults.data(forKey: "customCloudModels") == saved)
        precondition(defaults.string(forKey: "CurrentTranscriptionModel") == "user-chosen-model")
        print("PASS: clean defaults, model round trip, non-streaming, saved settings preserved")

        print("PASS: bundled model uses an internal route without an HTTP endpoint")
    }
}
