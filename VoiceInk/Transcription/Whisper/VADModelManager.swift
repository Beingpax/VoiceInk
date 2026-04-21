import Foundation
import OSLog

class VADModelManager {
    static let shared = VADModelManager()
    private let logger = Logger(subsystem: "VADModelManager", category: "ModelManagement")
    
    private init() {}

    func getModelPath() async -> String? {
        guard let modelURL = Bundle.main.url(forResource: "ggml-silero-v5.1.2", withExtension: "bin") else {
            logger.error("VAD model not found in bundle resources")
            return nil
        }
        
        return modelURL.path
    }
} 