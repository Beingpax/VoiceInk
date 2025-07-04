import Foundation
import AVFoundation
import os

/// Transcription service that leverages NVIDIA's Parakeet TDT 0.6B v2 model
/// Uses MLX framework for high-quality English speech recognition with timestamps
class ParakeetTDTTranscriptionService: TranscriptionService {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ParakeetTDTTranscriptionService")
    private let modelsDirectory: URL
    private let pythonEnvPath: URL
    
    // Persistent process management
    private var persistentProcess: Process?
    private var processInput: FileHandle?
    private var processOutput: FileHandle?
    private var processError: FileHandle?
    private var modelUnloadTimer: Timer?
    private var isModelLoaded = false
    private let modelTimeoutInterval: TimeInterval = 10 * 60 // 10 minutes
    
    enum ServiceError: Error, LocalizedError {
        case dependencyNotInstalled
        case modelNotInstalled
        case invalidModel
        case audioFileNotFound
        case invalidAudioFormat
        case transcriptionFailed
        case serverStartFailed
        case processNotRunning
        case invalidResponse
        case custom(String)
        
        var errorDescription: String? {
            switch self {
            case .dependencyNotInstalled:
                return "Parakeet MLX is not installed. Please install it using: pip install parakeet-mlx"
            case .modelNotInstalled:
                return "Parakeet TDT model is not available"
            case .invalidModel:
                return "Invalid model type for Parakeet TDT service"
            case .audioFileNotFound:
                return "Audio file not found"
            case .invalidAudioFormat:
                return "Invalid audio format"
            case .transcriptionFailed:
                return "Parakeet TDT transcription failed"
            case .serverStartFailed:
                return "Failed to start Parakeet server"
            case .processNotRunning:
                return "Parakeet process is not running"
            case .invalidResponse:
                return "Invalid response from Parakeet server"
            case .custom(let message):
                return message
            }
        }
    }
    
    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
        self.pythonEnvPath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".wonderwhisper_models/parakeet_env")
    }
    
    deinit {
        stopPersistentProcess()
    }
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        guard let parakeetModel = model as? ParakeetTDTModel else {
            logger.error("Invalid model type provided to ParakeetTDTTranscriptionService")
            throw ServiceError.invalidModel
        }
        
        logger.notice("Starting Parakeet TDT transcription with model: \(parakeetModel.displayName)")
        
        // Check if Parakeet MLX is available
        guard isParakeetMLXInstalled() else {
            logger.error("Parakeet MLX is not installed. Please install it first.")
            throw ServiceError.dependencyNotInstalled
        }
        
        // Validate audio file
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            logger.error("Audio file not found at path: \(audioURL.path)")
            throw ServiceError.audioFileNotFound
        }
        
        // Convert audio to required format if needed
        let processedAudioPath = try await preprocessAudio(audioURL)
        
        // Ensure persistent process is running
        try await ensurePersistentProcess()
        
        // Reset timeout timer
        resetModelUnloadTimer()
        
        // Run transcription using Parakeet MLX
        let transcription = try await runParakeetMLXInference(audioPath: processedAudioPath)
        
        logger.notice("Parakeet TDT transcription completed successfully. Length: \(transcription.count) characters")
        return transcription
    }
    
    // MARK: - Private Methods
    
    private func isParakeetMLXInstalled() -> Bool {
        let task = Process()
        task.launchPath = pythonEnvPath.appendingPathComponent("bin/python").path
        task.arguments = ["-c", "import parakeet_mlx; print('Parakeet MLX installed')"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            logger.error("Failed to check Parakeet MLX installation: \(error.localizedDescription)")
            return false
        }
    }
    
    private func preprocessAudio(_ audioURL: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let outputPath = modelsDirectory
                .appendingPathComponent("temp_audio_\(UUID().uuidString).wav").path
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
            process.arguments = [
                "-i", audioURL.path,
                "-ar", "16000",        // 16kHz sample rate
                "-ac", "1",           // Mono channel
                "-c:a", "pcm_s16le",  // 16-bit PCM
                "-y",                 // Overwrite output
                outputPath
            ]
            
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume(returning: outputPath)
                } else {
                    continuation.resume(throwing: ServiceError.invalidAudioFormat)
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func ensurePersistentProcess() async throws {
        if persistentProcess?.isRunning == true && isModelLoaded {
            logger.notice("✅ Using existing persistent process")
            return
        }
        
        logger.notice("🚀 Starting persistent Parakeet process...")
        
        stopPersistentProcess()
        
        // Create the persistent Python script
        let persistentScript = createParakeetServerScript()
        
        let scriptPath = modelsDirectory.appendingPathComponent("parakeet_server.py")
        try persistentScript.write(to: scriptPath, atomically: true, encoding: .utf8)
        
        // Start the persistent process
        let process = Process()
        process.executableURL = pythonEnvPath.appendingPathComponent("bin/python")
        process.arguments = [scriptPath.path]
        process.currentDirectoryURL = modelsDirectory
        
        // Set environment with FFmpeg path
        var environment = ProcessInfo.processInfo.environment
        let currentPath = environment["PATH"] ?? ""
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
        process.environment = environment
        
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        
        persistentProcess = process
        processInput = inputPipe.fileHandleForWriting
        processOutput = outputPipe.fileHandleForReading
        processError = errorPipe.fileHandleForReading
        
        // Wait for server to be ready
        let readyResponse = await readProcessLine()
        
        if let responseData = readyResponse.data(using: .utf8),
           let result = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let status = result["status"] as? String,
           status == "PARAKEET_SERVER_READY" {
            
            logger.notice("✅ Persistent Parakeet server started successfully")
            
            // Load the model
            let loadCommand = ["action": "load_model", "model_name": "mlx-community/parakeet-tdt-0.6b-v2"]
            let commandData = try JSONSerialization.data(withJSONObject: loadCommand)
            let commandString = String(data: commandData, encoding: .utf8)! + "\n"
            
            processInput?.write(commandString.data(using: .utf8) ?? Data())
            
            // Wait for model to load
            let loadResponse = await readProcessLine()
            if let loadData = loadResponse.data(using: .utf8),
               let loadResult = try? JSONSerialization.jsonObject(with: loadData) as? [String: Any],
               let loadStatus = loadResult["status"] as? String,
               (loadStatus == "MODEL_LOADED" || loadStatus == "MODEL_ALREADY_LOADED") {
                isModelLoaded = true
                logger.notice("✅ Parakeet model loaded and ready")
            } else {
                throw ServiceError.transcriptionFailed
            }
        } else {
            throw ServiceError.serverStartFailed
        }
    }
    
    private func runParakeetMLXInference(audioPath: String) async throws -> String {
        guard let processInput = processInput else {
            throw ServiceError.processNotRunning
        }
        
        let transcribeCommand = ["action": "transcribe", "audio_path": audioPath]
        let commandData = try JSONSerialization.data(withJSONObject: transcribeCommand)
        let commandString = String(data: commandData, encoding: .utf8)! + "\n"
        
        processInput.write(commandString.data(using: .utf8) ?? Data())
        
        let response = await readProcessLine()
        
        guard let responseData = response.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw ServiceError.invalidResponse
        }
        
        if let success = result["success"] as? Bool, success,
           let text = result["text"] as? String {
            return text
        } else {
            let error = result["error"] as? String ?? "Unknown error"
            logger.error("Parakeet transcription failed: \(error)")
            throw ServiceError.transcriptionFailed
        }
    }
    
    private func readProcessLine() async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                guard let processOutput = self.processOutput else {
                    continuation.resume(returning: "")
                    return
                }
                
                let timeout = DispatchTime.now() + .seconds(30)
                var accumulatedData = Data()
                
                while DispatchTime.now() < timeout {
                    let data = processOutput.availableData
                    if !data.isEmpty {
                        accumulatedData.append(data)
                        
                        if let string = String(data: accumulatedData, encoding: .utf8),
                           let newlineIndex = string.firstIndex(of: "\n") {
                            let line = String(string[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                            continuation.resume(returning: line)
                            return
                        }
                    } else {
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                }
                
                let finalResult = String(data: accumulatedData, encoding: .utf8) ?? ""
                continuation.resume(returning: finalResult.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
    
    private func resetModelUnloadTimer() {
        modelUnloadTimer?.invalidate()
        
        modelUnloadTimer = Timer.scheduledTimer(withTimeInterval: modelTimeoutInterval, repeats: false) { [weak self] _ in
            self?.logger.notice("⏰ Model timeout reached, unloading Parakeet model...")
            self?.stopPersistentProcess()
        }
    }
    
    private func stopPersistentProcess() {
        modelUnloadTimer?.invalidate()
        modelUnloadTimer = nil
        
        if let process = persistentProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        
        persistentProcess = nil
        processInput = nil
        processOutput = nil
        processError = nil
        isModelLoaded = false
        
        logger.notice("🛑 Parakeet persistent process stopped")
    }
    
    private func createParakeetServerScript() -> String {
        return """
import sys
import json
import os
from parakeet_mlx import from_pretrained
import traceback

class ParakeetServer:
    def __init__(self):
        self.model = None
        self.model_name = None
        
    def load_model(self, model_name):
        try:
            if self.model_name != model_name:
                print(f"🔄 Loading model: {model_name}", file=sys.stderr, flush=True)
                self.model = from_pretrained(model_name)
                self.model_name = model_name
                return {"status": "MODEL_LOADED", "success": True}
            else:
                return {"status": "MODEL_ALREADY_LOADED", "success": True}
        except Exception as e:
            return {"status": "MODEL_LOAD_ERROR", "success": False, "error": str(e)}
            
    def transcribe(self, audio_path):
        try:
            if self.model is None:
                return {"success": False, "error": "Model not loaded"}
                
            if not os.path.exists(audio_path):
                return {"success": False, "error": f"Audio file not found: {audio_path}"}
                
            result = self.model.transcribe(audio_path)
            return {
                "text": result.text.strip(),
                "success": True,
                "sentences": len(result.sentences) if hasattr(result, 'sentences') else 0
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
            }

def main():
    server = ParakeetServer()
    
    # Signal that we're ready
    print(json.dumps({"status": "PARAKEET_SERVER_READY", "success": True}), flush=True)
    
    try:
        while True:
            line = sys.stdin.readline()
            if not line:
                break
                
            line = line.strip()
            if not line:
                continue
                
            try:
                command = json.loads(line)
                
                if command["action"] == "load_model":
                    result = server.load_model(command["model_name"])
                    print(json.dumps(result), flush=True)
                    
                elif command["action"] == "transcribe":
                    result = server.transcribe(command["audio_path"])
                    print(json.dumps(result), flush=True)
                    
                elif command["action"] == "quit":
                    print(json.dumps({"status": "QUITTING", "success": True}), flush=True)
                    break
                    
            except json.JSONDecodeError:
                print(json.dumps({"success": False, "error": "Invalid JSON command"}), flush=True)
            except Exception as e:
                print(json.dumps({"success": False, "error": str(e)}), flush=True)
                
    except KeyboardInterrupt:
        pass
    except Exception as e:
        print(f"Server error: {e}", file=sys.stderr, flush=True)

if __name__ == "__main__":
    main()
"""
    }
}

