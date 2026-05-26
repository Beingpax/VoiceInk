import Foundation

class ShellScriptService {
    static let shared = ShellScriptService()
    
    private init() {}
    
    @discardableResult
    func runScript(_ script: String, transcript: String = "", rawTranscript: String = "", powerModeName: String = "") async -> String {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        
        var environment = ProcessInfo.processInfo.environment
        environment["VOICEINK_TRANSCRIPT"] = transcript
        environment["VOICEINK_ORIG_TRANSCRIPT"] = rawTranscript
        environment["VOICEINK_POWERMODE"] = powerModeName
        process.environment = environment
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        
        do {
            try process.run()
            
            while process.isRunning {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms sleep
            }
            
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outData, encoding: .utf8) ?? ""
            let error = String(data: errData, encoding: .utf8) ?? ""
            
            if !error.isEmpty {
                print("Shell script error: \(error)")
                return output + "\nError: " + error
            }
            return output
        } catch {
            print("Failed to run shell script: \(error)")
            return "Failed to execute: \(error.localizedDescription)"
        }
    }
}
