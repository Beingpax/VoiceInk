import Foundation

enum LocalMLXClient {

 static func chatCompletion(
  baseURL: String,
  model: String,
  text: String,
  systemPrompt: String,
  timeout: TimeInterval = 30
 ) async throws -> String {
  guard let url = URL(string: baseURL) else {
   throw LocalMLXError.invalidURL
  }

  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  request.timeoutInterval = timeout
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")

  let body: [String: Any] = [
   "model": model,
   "messages": [
    ["role": "system", "content": systemPrompt],
    ["role": "user", "content": text]
   ],
   "temperature": 0.3,
   "stream": false
  ]

  guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
   throw LocalMLXError.encodingError
  }
  request.httpBody = httpBody

  let (data, response) = try await URLSession.shared.data(for: request)

  guard let httpResponse = response as? HTTPURLResponse else {
   throw LocalMLXError.invalidResponse
  }

  guard httpResponse.statusCode == 200 else {
   let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
   throw LocalMLXError.serverError(message)
  }

  let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
  guard let content = decoded.choices.first?.message.content else {
   throw LocalMLXError.noResult
  }
  return content
 }
}

// MARK: - Response Types

private struct ChatResponse: Decodable {
 let choices: [Choice]
}

private struct Choice: Decodable {
 let message: Message
}

private struct Message: Decodable {
 let content: String
}

// MARK: - Errors

enum LocalMLXError: Error, LocalizedError {
 case invalidURL
 case encodingError
 case invalidResponse
 case serverError(String)
 case noResult

 var errorDescription: String? {
  switch self {
  case .invalidURL:
   return "Invalid Local MLX server URL"
  case .encodingError:
   return "Failed to encode request"
  case .invalidResponse:
   return "Invalid response from Local MLX server"
  case .serverError(let message):
   return "Local MLX server error: \(message)"
  case .noResult:
   return "No result returned from Local MLX server"
  }
 }
}
