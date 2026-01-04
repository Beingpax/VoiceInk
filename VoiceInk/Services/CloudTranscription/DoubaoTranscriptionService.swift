import Foundation
import os

class DoubaoTranscriptionService {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "DoubaoService")
    private let baseTimeout: TimeInterval = 120
    private let maxRetries: Int = 2
    private let initialRetryDelay: TimeInterval = 1.0

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        return try await transcribeWithRetry(audioURL: audioURL, model: model)
    }

    private func makeTranscriptionRequest(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)

        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.appId, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(config.accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue("volc.bigasr.auc_turbo", forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")
        request.timeoutInterval = baseTimeout

        let body = try createDoubaoRequestBody(audioURL: audioURL, appId: config.appId)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            logger.error("Doubao API request failed with status \\(httpResponse.statusCode): \\(errorMessage, privacy: .public)")
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        do {
            let transcriptionResponse = try JSONDecoder().decode(DoubaoResponse.self, from: data)
            guard let text = transcriptionResponse.result?.text else {
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            return text
        } catch {
            logger.error("Failed to decode Doubao API response: \\(error.localizedDescription)")
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }

    private func transcribeWithRetry(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        var retries = 0
        var currentDelay = initialRetryDelay

        while retries < self.maxRetries {
            do {
                return try await makeTranscriptionRequest(audioURL: audioURL, model: model)
            } catch let error as CloudTranscriptionError {
                switch error {
                case .networkError:
                    retries += 1
                    if retries < self.maxRetries {
                        logger.warning("Transcription request failed, retrying in \\(currentDelay)s... (Attempt \\(retries)/\\(self.maxRetries))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        logger.error("Transcription request failed after \\(self.maxRetries) retries.")
                        throw error
                    }
                case .apiRequestFailed(let statusCode, _):
                    if (500...599).contains(statusCode) || statusCode == 429 {
                        retries += 1
                        if retries < self.maxRetries {
                            logger.warning("Transcription request failed with status \\(statusCode), retrying in \\(currentDelay)s... (Attempt \\(retries)/\\(self.maxRetries))")
                            try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                            currentDelay *= 2
                        } else {
                            logger.error("Transcription request failed after \\(self.maxRetries) retries.")
                            throw error
                        }
                    } else {
                        throw error
                    }
                default:
                    throw error
                }
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain &&
                   [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost].contains(nsError.code) {
                    retries += 1
                    if retries < self.maxRetries {
                        logger.warning("Transcription request failed with network error, retrying in \\(currentDelay)s... (Attempt \\(retries)/\\(self.maxRetries))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        logger.error("Transcription request failed after \\(self.maxRetries) retries with network error.")
                        throw CloudTranscriptionError.networkError(error)
                    }
                } else {
                    throw error
                }
            }
        }

        throw CloudTranscriptionError.noTranscriptionReturned
    }

    private func getAPIConfig(for model: any TranscriptionModel) throws -> APIConfig {
        guard let appId = UserDefaults.standard.string(forKey: "DoubaoAppID"), !appId.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }

        guard let accessKey = UserDefaults.standard.string(forKey: "DoubaoAccessKey"), !accessKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }

        guard let apiURL = URL(string: "https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash") else {
            throw NSError(domain: "DoubaoTranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        return APIConfig(url: apiURL, appId: appId, accessKey: accessKey)
    }

    private func createDoubaoRequestBody(audioURL: URL, appId: String) throws -> Data {
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }

        let base64Audio = audioData.base64EncodedString()

        let requestBody: [String: Any] = [
            "user": ["uid": appId],
            "audio": ["data": base64Audio],
            "request": ["model_name": "bigmodel"]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw CloudTranscriptionError.dataEncodingError
        }

        return jsonData
    }

    private struct APIConfig {
        let url: URL
        let appId: String
        let accessKey: String
    }

    private struct DoubaoResponse: Decodable {
        let header: Header?
        let result: Result?

        struct Header: Decodable {
            let reqid: String?
            let code: Int?
            let message: String?
        }

        struct Result: Decodable {
            let text: String?
        }
    }
}
