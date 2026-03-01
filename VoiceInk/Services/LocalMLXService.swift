import Foundation

class LocalMLXService: ObservableObject {
 static let defaultBaseURL = "http://localhost:8090"

 @Published var baseURL: String {
  didSet {
   UserDefaults.standard.set(baseURL, forKey: "localMLXBaseURL")
  }
 }

 @Published var selectedModel: String {
  didSet {
   UserDefaults.standard.set(selectedModel, forKey: "localMLXSelectedModel")
  }
 }

 @Published var availableModels: [String] = []
 @Published var isConnected: Bool = false

 init() {
  self.baseURL = UserDefaults.standard.string(forKey: "localMLXBaseURL") ?? Self.defaultBaseURL
  self.selectedModel = UserDefaults.standard.string(forKey: "localMLXSelectedModel") ?? ""
 }

 @MainActor
 func checkConnection() async {
  guard let url = URL(string: baseURL + "/v1/models") else {
   isConnected = false
   return
  }

  var request = URLRequest(url: url)
  request.timeoutInterval = 5

  do {
   let (_, response) = try await URLSession.shared.data(for: request)
   if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
    isConnected = true
   } else {
    isConnected = false
   }
  } catch {
   isConnected = false
  }
 }

 @MainActor
 func refreshModels() async {
  guard let url = URL(string: baseURL + "/v1/models") else {
   availableModels = []
   return
  }

  var request = URLRequest(url: url)
  request.timeoutInterval = 5

  do {
   let (data, response) = try await URLSession.shared.data(for: request)
   guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
    availableModels = []
    return
   }

   let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
   let models = decoded.data.map { $0.id }
   availableModels = models

   if !models.contains(selectedModel) && !models.isEmpty {
    selectedModel = models[0]
   }
  } catch {
   availableModels = []
  }
 }
}

// MARK: - Response Types

private struct ModelsResponse: Decodable {
 let data: [ModelEntry]
}

private struct ModelEntry: Decodable {
 let id: String
}
