import Foundation
import os

class LocalMLXService: ObservableObject {
 static let defaultBaseURL = "http://localhost:8090"
 private static let logger = Logger(subsystem: "com.prakashjoshipax.VoiceInk", category: "LocalMLXService")

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
 @Published var isStartingServer: Bool = false

 private var serverProcess: Process?

 init() {
  self.baseURL = UserDefaults.standard.string(forKey: "localMLXBaseURL") ?? Self.defaultBaseURL
  self.selectedModel = UserDefaults.standard.string(forKey: "localMLXSelectedModel") ?? ""
 }

 deinit {
  stopServer()
 }

 // MARK: - Connection

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

 // MARK: - Server Lifecycle

 @MainActor
 func startServerIfNeeded(model: String? = nil) async -> Bool {
  // Already connected
  await checkConnection()
  if isConnected { return true }

  // Already launching
  if serverProcess?.isRunning == true { return false }

  guard let binary = findServerBinary() else {
   Self.logger.warning("mlx_lm.server binary not found")
   return false
  }

  let modelToLoad = model ?? selectedModel
  guard !modelToLoad.isEmpty else {
   Self.logger.warning("No model specified for mlx_lm server")
   return false
  }

  let port = extractPort(from: baseURL) ?? "8090"

  Self.logger.info("Starting mlx_lm server: model=\(modelToLoad) port=\(port)")
  isStartingServer = true

  let process = Process()
  process.executableURL = URL(fileURLWithPath: binary)
  process.arguments = ["--model", modelToLoad, "--port", port]
  process.environment = ProcessInfo.processInfo.environment.merging(
   ["KMP_DUPLICATE_LIB_OK": "TRUE"],
   uniquingKeysWith: { _, new in new }
  )

  // Suppress stdout/stderr to avoid broken pipe issues
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice

  do {
   try process.run()
   serverProcess = process
  } catch {
   Self.logger.error("Failed to launch mlx_lm server: \(error.localizedDescription)")
   isStartingServer = false
   return false
  }

  // Poll for server readiness (up to 60s for model loading)
  let started = await waitForServer(timeout: 60)
  isStartingServer = false

  if started {
   Self.logger.info("mlx_lm server is ready")
   isConnected = true
   await refreshModels()
  } else {
   Self.logger.warning("mlx_lm server failed to start in time")
   stopServer()
  }

  return started
 }

 func stopServer() {
  guard let process = serverProcess, process.isRunning else {
   serverProcess = nil
   return
  }
  Self.logger.info("Stopping mlx_lm server (pid \(process.processIdentifier))")
  process.terminate()
  serverProcess = nil
 }

 var isServerManagedByApp: Bool {
  serverProcess?.isRunning == true
 }

 // MARK: - Private

 private func findServerBinary() -> String? {
  let candidates = [
   "/opt/homebrew/bin/mlx_lm.server",
   "/usr/local/bin/mlx_lm.server"
  ]
  for path in candidates {
   if FileManager.default.isExecutableFile(atPath: path) {
    return path
   }
  }
  return nil
 }

 private func extractPort(from urlString: String) -> String? {
  guard let url = URL(string: urlString),
        let port = url.port else { return nil }
  return String(port)
 }

 private func waitForServer(timeout: TimeInterval) async -> Bool {
  let start = Date()
  while Date().timeIntervalSince(start) < timeout {
   // Check process hasn't crashed
   if serverProcess?.isRunning == false { return false }

   if let url = URL(string: baseURL + "/v1/models") {
    var request = URLRequest(url: url)
    request.timeoutInterval = 2
    if let (_, response) = try? await URLSession.shared.data(for: request),
       let http = response as? HTTPURLResponse,
       http.statusCode == 200 {
     return true
    }
   }
   try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
  }
  return false
 }
}

// MARK: - Response Types

private struct ModelsResponse: Decodable {
 let data: [ModelEntry]
}

private struct ModelEntry: Decodable {
 let id: String
}
