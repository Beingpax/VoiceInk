import Foundation
import os

class MistralTranscriptionService {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MistralTranscriptionService")
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        logger.notice("Sending transcription request to Mistral for model: \(model.name)")
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: "Mistral"), !apiKey.isEmpty else {
            logger.error("Mistral API key is missing.")
            throw CloudTranscriptionError.missingAPIKey
        }

        guard let url = URL(string: "https://api.mistral.ai/v1/audio/transcriptions") else {
            throw NSError(domain: "MistralTranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        var body = Data()

        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append(model.name.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        // Add file data - matching Python SDK structure (no language field as it's commented out in all Python examples)
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorResponse = String(data: data, encoding: .utf8) ?? "No response body"
                logger.error("Mistral transcription request failed with status code \((response as? HTTPURLResponse)?.statusCode ?? 500): \(errorResponse)")
                throw CloudTranscriptionError.apiRequestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: errorResponse)
            }

            do {
                let transcriptionResponse = try JSONDecoder().decode(MistralTranscriptionResponse.self, from: data)
                logger.notice("Successfully received transcription from Mistral.")
                return transcriptionResponse.text
            } catch {
                logger.error("Failed to decode Mistral response: \(error.localizedDescription)")
                throw CloudTranscriptionError.noTranscriptionReturned
            }
        } catch {
            logger.error("Mistral transcription request threw an error: \(error.localizedDescription)")
            throw error
        }
    }
}

struct MistralTranscriptionResponse: Codable {
    let text: String
} 
