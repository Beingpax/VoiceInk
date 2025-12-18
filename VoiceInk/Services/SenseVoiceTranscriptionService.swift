import Foundation
import AVFoundation
import OnnxRuntimeBindings
import os.log

final class SenseVoiceTranscriptionService: TranscriptionService {
    private let modelsDirectory: URL
    private let featureExtractor = FastConformerFeatureExtractor()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SenseVoice")

    private var env: ORTEnv?
    private var sessions: [String: ORTSession] = [:]
    private var tokenizerCache: [String: SenseVoiceTokenizer] = [:]
    private let cacheLock = NSLock()

    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
        do {
            self.env = try ORTEnv(loggingLevel: .warning)
            logger.notice("ONNX Runtime environment initialized successfully")
        } catch {
            logger.error("Failed to initialize ONNX Runtime environment: \(error.localizedDescription)")
            self.env = nil
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        guard let senseVoiceModel = model as? SenseVoiceModel else {
            throw WhisperStateError.modelLoadFailed
        }

        let samples = try readAudioSamples(from: audioURL)
        guard !samples.isEmpty else { throw WhisperStateError.transcriptionFailed }
        
        let rawFeatures = featureExtractor.extract(samples: samples)
        guard !rawFeatures.isEmpty else { throw WhisperStateError.transcriptionFailed }
        
        // SenseVoice uses LFR (Low Frame Rate) features: stack 7 frames with stride 6
        // This converts 80-dim features to 560-dim (80 * 7)
        let features = applyLFR(features: rawFeatures, lfrM: 7, lfrN: 6)
        guard !features.isEmpty else { throw WhisperStateError.transcriptionFailed }
        
        logger.notice("SenseVoice: Feature shape after LFR: \(features.count) frames x \(features.first?.count ?? 0) dims")

        let session = try ensureSession(for: senseVoiceModel)
        let tokenizer = try tokenizer(for: senseVoiceModel)
        
        let inputNames = try session.inputNames()
        let outputNames = try session.outputNames()
        
        logger.notice("SenseVoice input names: \(inputNames, privacy: .public)")
        logger.notice("SenseVoice output names: \(outputNames, privacy: .public)")
        
        // SenseVoice expects: x, x_length, language, text_norm
        guard let outputName = outputNames.first else {
            logger.error("SenseVoice: Could not find output name")
            throw WhisperStateError.modelLoadFailed
        }
        
        let inputValue = try makeInputTensor(from: features)
        let lengthValue = try makeLengthTensor(frameCount: features.count)
        let languageId = senseVoiceLanguageId()
        let languageValue = try makeLanguageTensor(languageId: languageId)
        let textNormValue = try makeTextNormTensor(normalize: true)
        
        logger.notice("SenseVoice: Using language ID \(languageId)")
        
        // Build inputs dictionary using actual input names from model
        var inputs: [String: ORTValue] = [:]
        for name in inputNames {
            if name == "x" {
                inputs[name] = inputValue
            } else if name == "x_length" {
                inputs[name] = lengthValue
            } else if name == "language" {
                inputs[name] = languageValue
            } else if name == "text_norm" {
                inputs[name] = textNormValue
            }
        }
        
        logger.notice("SenseVoice: Running inference with \(inputs.count) inputs")

        let outputs = try session.run(withInputs: inputs,
                                      outputNames: [outputName],
                                      runOptions: nil)
        guard let outputValue = outputs[outputName] else {
            throw WhisperStateError.transcriptionFailed
        }

        let tokenIds = try extractTokenIds(from: outputValue)
        return tokenizer.decode(ids: tokenIds)
    }

    func invalidateSession(for modelName: String) {
        cacheLock.lock()
        sessions[modelName] = nil
        tokenizerCache[modelName] = nil
        cacheLock.unlock()
    }

    func cleanup() {
        cacheLock.lock()
        sessions.removeAll()
        tokenizerCache.removeAll()
        cacheLock.unlock()
    }

    private func tokenizer(for model: SenseVoiceModel) throws -> SenseVoiceTokenizer {
        cacheLock.lock()
        if let cached = tokenizerCache[model.name] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let tokenizerURL = modelsDirectory
            .appendingPathComponent(model.name)
            .appendingPathComponent("tokens.txt")
        let tokenizer = try SenseVoiceTokenizer(tokensFileURL: tokenizerURL)
        cacheLock.lock()
        tokenizerCache[model.name] = tokenizer
        cacheLock.unlock()
        return tokenizer
    }

    private func ensureSession(for model: SenseVoiceModel) throws -> ORTSession {
        cacheLock.lock()
        if let session = sessions[model.name] {
            cacheLock.unlock()
            return session
        }
        cacheLock.unlock()
        guard let env = env else {
            logger.error("SenseVoice: ONNX environment is nil")
            throw WhisperStateError.modelLoadFailed
        }

        let modelPath = modelsDirectory
            .appendingPathComponent(model.name)
            .appendingPathComponent("model.int8.onnx")

        logger.notice("SenseVoice model path: \(modelPath.path, privacy: .public)")
        logger.notice("SenseVoice model exists: \(FileManager.default.fileExists(atPath: modelPath.path), privacy: .public)")
        
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            logger.error("SenseVoice: Model file not found at path")
            throw WhisperStateError.modelLoadFailed
        }

        let options = try ORTSessionOptions()
        _ = try? options.setGraphOptimizationLevel(.all)
        // Skip CoreML for SenseVoice - use CPU for compatibility
        
        let session: ORTSession
        do {
            session = try ORTSession(env: env, modelPath: modelPath.path, sessionOptions: options)
            logger.notice("SenseVoice: ONNX session created successfully")
        } catch {
            logger.error("SenseVoice: Failed to create ONNX session: \(error.localizedDescription, privacy: .public)")
            throw WhisperStateError.modelLoadFailed
        }
        cacheLock.lock()
        sessions[model.name] = session
        cacheLock.unlock()
        return session
    }

    // LFR (Low Frame Rate) feature stacking for SenseVoice
    // Stacks lfrM frames with stride lfrN to produce higher dimensional features
    private func applyLFR(features: [[Float]], lfrM: Int, lfrN: Int) -> [[Float]] {
        guard !features.isEmpty else { return [] }
        
        let numFrames = features.count
        let featureDim = features[0].count
        
        // Calculate output frames
        var lfrFeatures: [[Float]] = []
        
        var i = 0
        while i < numFrames {
            var stackedFrame: [Float] = []
            stackedFrame.reserveCapacity(lfrM * featureDim)
            
            for j in 0..<lfrM {
                let frameIdx = min(i + j, numFrames - 1)
                stackedFrame.append(contentsOf: features[frameIdx])
            }
            
            lfrFeatures.append(stackedFrame)
            i += lfrN
        }
        
        return lfrFeatures
    }

    private func makeInputTensor(from features: [[Float]]) throws -> ORTValue {
        let frames = features.count
        guard let firstFrame = features.first else {
            throw WhisperStateError.transcriptionFailed
        }
        let dimension = firstFrame.count  // Use actual dimension from features
        
        var flattened: [Float] = []
        flattened.reserveCapacity(frames * dimension)
        for frame in features {
            flattened.append(contentsOf: frame)
        }

        let dataLength = flattened.count * MemoryLayout<Float>.size
        let tensorData = NSMutableData(length: dataLength) ?? NSMutableData()
        flattened.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            memcpy(tensorData.mutableBytes, baseAddress, dataLength)
        }

        let shape: [NSNumber] = [NSNumber(value: 1), NSNumber(value: frames), NSNumber(value: dimension)]
        return try ORTValue(tensorData: tensorData, elementType: .float, shape: shape)
    }

    private func makeLengthTensor(frameCount: Int) throws -> ORTValue {
        var length = Int32(frameCount)
        let dataLength = MemoryLayout<Int32>.size
        let tensorData = NSMutableData(length: dataLength) ?? NSMutableData()
        withUnsafeBytes(of: &length) { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            memcpy(tensorData.mutableBytes, baseAddress, dataLength)
        }
        let shape: [NSNumber] = [NSNumber(value: 1)]
        return try ORTValue(tensorData: tensorData, elementType: .int32, shape: shape)
    }

    // Maps user's selected language to SenseVoice language ID
    // SenseVoice language IDs: 0=zh, 1=yue, 2=en, 3=ja, 4=ko
    private func senseVoiceLanguageId() -> Int32 {
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
        
        switch selectedLanguage.lowercased() {
        case "zh", "zh-cn", "zh-tw", "chinese":
            return 0  // Chinese
        case "yue", "cantonese":
            return 1  // Cantonese
        case "en", "english", "auto":
            return 2  // English (default for auto)
        case "ja", "japanese":
            return 3  // Japanese
        case "ko", "korean":
            return 4  // Korean
        default:
            return 2  // Default to English for unsupported languages
        }
    }

    // Language IDs: 0=zh, 1=yue, 2=en, 3=ja, 4=ko
    private func makeLanguageTensor(languageId: Int32) throws -> ORTValue {
        var langId = languageId
        let dataLength = MemoryLayout<Int32>.size
        let tensorData = NSMutableData(length: dataLength) ?? NSMutableData()
        withUnsafeBytes(of: &langId) { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            memcpy(tensorData.mutableBytes, baseAddress, dataLength)
        }
        let shape: [NSNumber] = [NSNumber(value: 1)]
        return try ORTValue(tensorData: tensorData, elementType: .int32, shape: shape)
    }

    // text_norm: 0 = without inverse text normalization, 1 = with inverse text normalization
    private func makeTextNormTensor(normalize: Bool) throws -> ORTValue {
        var normFlag = Int32(normalize ? 1 : 0)
        let dataLength = MemoryLayout<Int32>.size
        let tensorData = NSMutableData(length: dataLength) ?? NSMutableData()
        withUnsafeBytes(of: &normFlag) { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            memcpy(tensorData.mutableBytes, baseAddress, dataLength)
        }
        let shape: [NSNumber] = [NSNumber(value: 1)]
        return try ORTValue(tensorData: tensorData, elementType: .int32, shape: shape)
    }

    private func extractTokenIds(from value: ORTValue) throws -> [Int] {
        let tensorData = try value.tensorData()
        let typeInfo = try value.tensorTypeAndShapeInfo()
        let elementType = typeInfo.elementType
        
        switch elementType {
        case .int64:
            let count = tensorData.length / MemoryLayout<Int64>.size
            var buffer = [Int64](repeating: 0, count: count)
            tensorData.getBytes(&buffer, length: tensorData.length)
            return buffer.map { Int($0) }
        case .int32:
            let count = tensorData.length / MemoryLayout<Int32>.size
            var buffer = [Int32](repeating: 0, count: count)
            tensorData.getBytes(&buffer, length: tensorData.length)
            return buffer.map { Int($0) }
        default:
            let floatCount = tensorData.length / MemoryLayout<Float>.size
            var floatBuffer = [Float](repeating: 0, count: floatCount)
            tensorData.getBytes(&floatBuffer, length: tensorData.length)
            
            let shape = typeInfo.shape.map { $0.intValue }
            if shape.count >= 2 {
                let vocabSize = shape.last ?? 1
                let frameCount = shape[shape.count - 2]
                return greedyDecode(floatBuffer, frameCount: frameCount, vocabSize: vocabSize)
            }
            return []
        }
    }

    private func greedyDecode(_ logits: [Float], frameCount: Int, vocabSize: Int) -> [Int] {
        guard frameCount > 0, vocabSize > 0 else { return [] }
        var decoded: [Int] = []
        decoded.reserveCapacity(frameCount)

        for frame in 0..<frameCount {
            let offset = frame * vocabSize
            var maxValue: Float = -.infinity
            var maxIndex = 0
            for vocabIndex in 0..<vocabSize {
                let value = logits[offset + vocabIndex]
                if value > maxValue {
                    maxValue = value
                    maxIndex = vocabIndex
                }
            }
            decoded.append(maxIndex)
        }

        return decoded
    }

    private func readAudioSamples(from url: URL) throws -> [Float] {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            guard let header = try handle.read(upToCount: 44), header.count == 44 else {
                return []
            }

            let chunkSize = 16_384
            var samples: [Float] = []
            var carryByte: UInt8?

            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                var data = chunk
                if let carry = carryByte {
                    data.insert(carry, at: 0)
                    carryByte = nil
                }
                if data.count % 2 != 0 {
                    carryByte = data.removeLast()
                }
                data.withUnsafeBytes { rawBuffer in
                    guard let base = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
                    let count = rawBuffer.count / MemoryLayout<Int16>.size
                    samples.reserveCapacity(samples.count + count)
                    for index in 0..<count {
                        let littleEndianSample = Int16(littleEndian: base[index])
                        let normalized = Float(littleEndianSample) / Float(Int16.max)
                        samples.append(max(-1.0, min(normalized, 1.0)))
                    }
                }
            }

            if carryByte != nil {
                carryByte = nil
            }

            return samples
        } catch {
            throw WhisperStateError.transcriptionFailed
        }
    }
}
