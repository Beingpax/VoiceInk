import Foundation

@MainActor
final class DiarizationServiceRegistry {
    static let shared = DiarizationServiceRegistry()
    private lazy var fluidAudioService = FluidAudioDiarizationService()

    func currentService() -> any DiarizationService {
        // MVP: always FluidAudio. Future: pick based on user settings.
        return fluidAudioService
    }

    private init() {}
}
