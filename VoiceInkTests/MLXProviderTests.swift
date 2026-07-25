import Foundation
import Testing

@testable import VoiceInk

// Network-dependent paths (MLXClient.fetchModels/checkConnection/generate, MLXService.enhance)
// require a live MLX server and aren't covered here, matching the existing (untested) Ollama
// integration this provider mirrors. These tests cover the pure logic: provider registration
// and JSON/error mapping.
struct MLXProviderTests {

    @Test func mlxDoesNotRequireAnAPIKey() {
        #expect(AIProvider.mlx.requiresAPIKey == false)
    }

    @Test func mlxSupportsEnhancement() {
        #expect(AIProvider.mlx.supportsEnhancement == true)
    }

    @Test func mlxHasNoStaticAvailableModelsSinceTheyAreFetchedFromTheServer() {
        #expect(AIProvider.mlx.availableModels.isEmpty)
    }

    @Test func mlxBaseURLFallsBackToLocalhost8080WhenUnset() {
        UserDefaults.standard.removeObject(forKey: "mlxBaseURL")
        #expect(AIProvider.mlx.baseURL == "http://localhost:8080")
    }

    @Test func mlxModelDecodesFromOpenAICompatibleModelListJSON() throws {
        let json = Data(#"{"id": "mlx-community/Qwen2.5-3B-Instruct-4bit"}"#.utf8)
        let model = try JSONDecoder().decode(MLXModel.self, from: json)
        #expect(model.id == "mlx-community/Qwen2.5-3B-Instruct-4bit")
    }

    @Test func mlxErrorDescriptionsMentionMLXNotOllama() {
        for error in [
            MLXError.invalidURL, .serviceUnavailable, .invalidResponse, .modelNotFound, .serverError, .invalidRequest,
            .timeout,
        ] {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
            #expect(!description.contains("Ollama"))
        }
    }
}
