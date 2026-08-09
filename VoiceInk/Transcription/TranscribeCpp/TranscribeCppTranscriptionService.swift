import Foundation

/// Routes transcribe.cpp-backed models to their model-specific service.
/// Shared provider wiring stays stable as additional transcribe.cpp model
/// families are added.
final class TranscribeCppTranscriptionService: TranscriptionService, @unchecked Sendable {
    private let cohereService = CohereTranscriptionService()

    func loadModel(for model: TranscribeCppModel) async throws {
        switch model.name {
        case TranscribeCppModelCatalog.cohereTranscribe.modelName:
            try await cohereService.loadModel(for: model)
        default:
            throw unsupportedModelError(model.name)
        }
    }

    func transcribe(
        audioURL: URL,
        model: any TranscriptionModel,
        context: TranscriptionRequestContext
    ) async throws -> String {
        guard let transcribeCppModel = model as? TranscribeCppModel else {
            throw NSError(
                domain: "TranscribeCppTranscriptionService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported transcription model"]
            )
        }

        switch transcribeCppModel.name {
        case TranscribeCppModelCatalog.cohereTranscribe.modelName:
            return try await cohereService.transcribe(
                audioURL: audioURL,
                model: transcribeCppModel,
                context: context
            )
        default:
            throw unsupportedModelError(transcribeCppModel.name)
        }
    }

    func cleanup() {
        cohereService.cleanup()
    }

    private func unsupportedModelError(_ modelName: String) -> NSError {
        NSError(
            domain: "TranscribeCppTranscriptionService",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "No transcribe.cpp service is registered for \(modelName)"]
        )
    }
}
