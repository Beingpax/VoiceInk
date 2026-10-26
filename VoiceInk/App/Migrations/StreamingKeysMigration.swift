import Foundation

// Safe to delete once all users have updated past this version.
enum StreamingKeysMigration {
    static func run() {
        let defaults = UserDefaults.standard
        // Run after the older migration, including for users who already ran it.
        defer { migrateVoxtral3(defaults: defaults) }
        guard !defaults.bool(forKey: "streaming-keys-migrated") else { return }

        let legacyStreamingMappings: [(old: String, new: [String])] = [
            (
                "parakeet-streaming-enabled",
                [
                    "streaming-enabled-parakeet-tdt-0.6b-v2",
                    "streaming-enabled-parakeet-tdt-0.6b-v3",
                ]
            )
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
            let replacement = removedModelMappings[savedModel]
        {
            defaults.set(replacement, forKey: "CurrentTranscriptionModel")
        }

        // Remap selectedTranscriptionModelName inside each stored ModeConfig.
        // Check both the renamed key and the legacy key so older saved data is fixed
        // before ModeDataMigration copies it forward.
        // Uses JSONSerialization so the migration stays independent of the ModeConfig struct shape.
        for modeKey in ["modeConfigurationsV2", "powerModeConfigurationsV2"] {
            if let data = defaults.data(forKey: modeKey),
                var configs = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
            {
                var changed = false
                for index in configs.indices {
                    guard let savedModel = configs[index]["selectedTranscriptionModelName"] as? String,
                        let replacement = removedModelMappings[savedModel]
                    else { continue }
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

    private static func migrateVoxtral3(defaults: UserDefaults) {
        guard !defaults.bool(forKey: "voxtral-3-models-migrated") else { return }
        let legacyModels: Set<String> = [
            "voxtral-mini-latest", "voxtral-mini-2507", "voxtral-mini-2602",
            "voxtral-mini-transcribe-realtime-2602",
        ]

        let globalSelection = defaults.string(forKey: "CurrentTranscriptionModel")
        // The old combined entry used realtime by default. Preserve that behavior.
        if let selected = globalSelection, legacyModels.contains(selected) {
            defaults.set("voxtral-mini-transcribe-realtime-3-0", forKey: "CurrentTranscriptionModel")
        }

        for key in ["modeConfigurationsV2", "powerModeConfigurationsV2"] {
            guard let data = defaults.data(forKey: key),
                  var configs = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { continue }
            var changed = false
            for index in configs.indices {
                // Preserve each mode's setting when it inherits the legacy global model.
                let selected = configs[index]["selectedTranscriptionModelName"] as? String
                    ?? configs[index]["selectedWhisperModel"] as? String
                    ?? globalSelection
                guard let selected,
                      legacyModels.contains(selected) else { continue }
                let realtime = configs[index]["isRealtimeTranscriptionEnabled"] as? Bool ?? true
                configs[index]["selectedTranscriptionModelName"] = realtime
                    ? "voxtral-mini-transcribe-realtime-3-0" : "voxtral-mini-transcribe-3-0"
                changed = true
            }
            if changed, let updated = try? JSONSerialization.data(withJSONObject: configs) {
                defaults.set(updated, forKey: key)
            }
        }
        defaults.set(true, forKey: "voxtral-3-models-migrated")
    }
}
