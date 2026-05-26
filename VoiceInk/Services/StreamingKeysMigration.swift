import Foundation

// Safe to delete once all users have updated past this version.
enum StreamingKeysMigration {
    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "streaming-keys-migrated") else { return }

        let legacyStreamingMappings: [(old: String, new: [String])] = [
            ("parakeet-streaming-enabled", [
                "streaming-enabled-parakeet-tdt-0.6b-v2",
                "streaming-enabled-parakeet-tdt-0.6b-v3",
            ]),
        ]

        for mapping in legacyStreamingMappings {
            if let value = defaults.object(forKey: mapping.old) as? Bool {
                for newKey in mapping.new {
                    defaults.set(value, forKey: newKey)
                }
                defaults.removeObject(forKey: mapping.old)
            }
        }

        // Remap CurrentTranscriptionModel if it points to a removed streaming-only model name.
        let removedModelMappings: [String: String] = [
            "stt-rt-v4": "stt-async-v4",
            "voxtral-mini-transcribe-realtime-2602": "voxtral-mini-latest",
        ]

        if let savedModel = defaults.string(forKey: "CurrentTranscriptionModel"),
           let replacement = removedModelMappings[savedModel] {
            defaults.set(replacement, forKey: "CurrentTranscriptionModel")
        }

        // Remap selectedTranscriptionModelName inside each stored ModeConfig.
        // Check both the renamed key and the legacy key so older saved data is fixed
        // before ModeDataMigration copies it forward.
        // Uses JSONSerialization so the migration stays independent of the ModeConfig struct shape.
        for modeKey in ["modeConfigurationsV2", "powerModeConfigurationsV2"] {
            if let data = defaults.data(forKey: modeKey),
               var configs = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                var changed = false
                for index in configs.indices {
                    guard let savedModel = configs[index]["selectedTranscriptionModelName"] as? String,
                          let replacement = removedModelMappings[savedModel] else { continue }
                    configs[index]["selectedTranscriptionModelName"] = replacement
                    changed = true
                }
                if changed, let newData = try? JSONSerialization.data(withJSONObject: configs) {
                    defaults.set(newData, forKey: modeKey)
                }
            }
        }

        defaults.set(true, forKey: "streaming-keys-migrated")
    }
}
