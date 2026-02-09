import Foundation
import os

class GeminiTranscriptionService {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "GeminiService")
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)
        
        logger.notice("Starting Gemini transcription with model: \(model.name, privacy: .public)")
        
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-goog-api-key")
        
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }
        
        logger.notice("Audio file loaded, size: \(audioData.count) bytes")
        
        let base64AudioData = audioData.base64EncodedString()
        
        let requestBody = GeminiRequest(
            contents: [
                GeminiContent(
                    parts: [
                        .text(GeminiTextPart(text: "Please transcribe this audio file. Provide only the transcribed text.")),
                        .audio(GeminiAudioPart(
                            inlineData: GeminiInlineData(
                                mimeType: "audio/wav",
                                data: base64AudioData
                            )
                        ))
                    ]
                )
            ]
        )
        
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
            logger.notice("Request body encoded, sending to Gemini API")
        } catch {
            logger.error("Failed to encode Gemini request: \(error.localizedDescription)")
            throw CloudTranscriptionError.dataEncodingError
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            logger.error("Gemini API request failed with status \(httpResponse.statusCode): \(errorMessage, privacy: .public)")
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            guard let candidate = transcriptionResponse.candidates.first,
                  let part = candidate.content.parts.first,
                  !part.text.isEmpty else {
                logger.error("No transcript found in Gemini response")
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            logger.notice("Gemini transcription successful, text length: \(part.text.count)")
            return part.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            logger.error("Failed to decode Gemini API response: \(error.localizedDescription)")
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    private func getAPIConfig(for model: any TranscriptionModel) throws -> APIConfig {
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: "Gemini"), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model.name):generateContent"
        guard let apiURL = URL(string: urlString) else {
            throw CloudTranscriptionError.dataEncodingError
        }

        return APIConfig(url: apiURL, apiKey: apiKey, modelName: model.name)
    }
    
    private struct APIConfig {
        let url: URL
        let apiKey: String
        let modelName: String
    }
    
    private struct GeminiRequest: Codable {
        let contents: [GeminiContent]
    }
    
    private struct GeminiContent: Codable {
        let parts: [GeminiPart]
    }
    
    private enum GeminiPart: Codable {
        case text(GeminiTextPart)
        case audio(GeminiAudioPart)
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let textPart):
                try container.encode(textPart)
            case .audio(let audioPart):
                try container.encode(audioPart)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let textPart = try? container.decode(GeminiTextPart.self) {
                self = .text(textPart)
            } else if let audioPart = try? container.decode(GeminiAudioPart.self) {
                self = .audio(audioPart)
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid part"))
            }
        }
    }
    
    private struct GeminiTextPart: Codable {
        let text: String
    }
    
    private struct GeminiAudioPart: Codable {
        let inlineData: GeminiInlineData
    }
    
    private struct GeminiInlineData: Codable {
        let mimeType: String
        let data: String
    }
    
    private struct GeminiResponse: Codable {
        let candidates: [GeminiCandidate]
    }
    
    private struct GeminiCandidate: Codable {
        let content: GeminiResponseContent
    }
    
    private struct GeminiResponseContent: Codable {
        let parts: [GeminiResponsePart]
    }
    
    private struct GeminiResponsePart: Codable {
        let text: String
    }
}