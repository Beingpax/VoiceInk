import Foundation
import Combine

@MainActor
final class WhisperModelWarmupCoordinator: ObservableObject {
    static let shared = WhisperModelWarmupCoordinator()
    
    @Published private(set) var warmingModels: Set<String> = []
    
    private init() {}
    
    func isWarming(modelNamed name: String) -> Bool {
        warmingModels.contains(name)
    }
    
    func scheduleWarmup(for model: LocalModel, modelManager: ModelManager) {
        guard shouldWarmup(modelName: model.name),
              !warmingModels.contains(model.name) else {
            return
        }

        warmingModels.insert(model.name)

        Task {
            do {
                try await runWarmup(for: model, modelManager: modelManager)
            } catch {
                await MainActor.run {
                    modelManager.logger.error("Warmup failed for \(model.name): \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                self.warmingModels.remove(model.name)
            }
        }
    }

    private func runWarmup(for model: LocalModel, modelManager: ModelManager) async throws {
        guard let sampleURL = warmupSampleURL() else { return }
        let service = LocalTranscriptionService(
            modelsDirectory: modelManager.modelsDirectory,
            modelManager: modelManager
        )
        _ = try await service.transcribe(audioURL: sampleURL, model: model)
    }
    
    private func warmupSampleURL() -> URL? {
        let bundle = Bundle.main
        let candidates: [URL?] = [
            bundle.url(forResource: "esc", withExtension: "wav", subdirectory: "Resources/Sounds"),
            bundle.url(forResource: "esc", withExtension: "wav", subdirectory: "Sounds"),
            bundle.url(forResource: "esc", withExtension: "wav")
        ]

        for candidate in candidates {
            if let url = candidate {
                return url
            }
        }

        return nil
    }
    
    private func shouldWarmup(modelName: String) -> Bool {
        !modelName.contains("q5") && !modelName.contains("q8")
    }
}
