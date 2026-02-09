import Foundation
import os

class DeepgramTranscriptionService {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "DeepgramService")
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)
        
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.setValue("Token \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }
        
        let (data, response) = try await URLSession.shared.upload(for: request, from: audioData)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            logger.error("Deepgram API request failed with status \(httpResponse.statusCode): \(errorMessage, privacy: .public)")
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(DeepgramResponse.self, from: data)
            guard let transcript = transcriptionResponse.results.channels.first?.alternatives.first?.transcript,
                  !transcript.isEmpty else {
                logger.error("No transcript found in Deepgram response")
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            return transcript
        } catch {
            logger.error("Failed to decode Deepgram API response: \(error.localizedDescription)")
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    private func getAPIConfig(for model: any TranscriptionModel) throws -> APIConfig {
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: "Deepgram"), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }
        
        // Build the URL with query parameters
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        var queryItems: [URLQueryItem] = []
        
        // Add language parameter if not auto-detect
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        
        // Use the model name from the TranscriptionModel (nova-3 or nova-3-medical)
        queryItems.append(URLQueryItem(name: "model", value: model.name))
        
        queryItems.append(contentsOf: [
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "paragraphs", value: "true")
        ])
        
        if selectedLanguage != "auto" && !selectedLanguage.isEmpty {
            queryItems.append(URLQueryItem(name: "language", value: selectedLanguage))
        }
        
        components.queryItems = queryItems
        
        guard let apiURL = components.url else {
            throw CloudTranscriptionError.dataEncodingError
        }
        
        return APIConfig(url: apiURL, apiKey: apiKey, modelName: model.name)
    }
    
    private struct APIConfig {
        let url: URL
        let apiKey: String
        let modelName: String
    }
    
    private struct DeepgramResponse: Decodable {
        let results: Results
        
        struct Results: Decodable {
            let channels: [Channel]
            
            struct Channel: Decodable {
                let alternatives: [Alternative]
                
                struct Alternative: Decodable {
                    let transcript: String
                    let confidence: Double?
                }
            }
        }
    }
} 