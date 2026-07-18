import Testing

@testable import VoiceInk

struct TranscriptionModelRegistryTests {

    @Test func includesExpectedBuiltInModels() {
        let names = Set(TranscriptionModelRegistry.models.map(\.name))
        #expect(names.contains("apple-speech"))
        #expect(names.contains("ggml-large-v3"))
        #expect(names.contains("ggml-large-v3-turbo"))
        #expect(names.contains("parakeet-tdt-0.6b-v3"))
    }

    @Test func builtInWhisperModelsHaveNoDuplicateNames() {
        let whisperNames = TranscriptionModelRegistry.models
            .map(\.name)
            .filter { $0.hasPrefix("ggml-") }
        #expect(whisperNames.count == Set(whisperNames).count)
    }

    @Test func whisperModelsHaveSpeedAndAccuracyWithinUnitRange() {
        let whisperModels = TranscriptionModelRegistry.models.compactMap { $0 as? WhisperModel }
        #expect(!whisperModels.isEmpty)
        for model in whisperModels {
            #expect((0.0...1.0).contains(model.speed), "\(model.name) speed out of range: \(model.speed)")
            #expect((0.0...1.0).contains(model.accuracy), "\(model.name) accuracy out of range: \(model.accuracy)")
        }
    }

    @Test func everyBuiltInModelHasANonEmptyDisplayName() {
        for model in TranscriptionModelRegistry.models where model.name.hasPrefix("ggml-") || model.name.hasPrefix("parakeet-") {
            #expect(!model.displayName.isEmpty, "\(model.name) has an empty displayName")
        }
    }
}
