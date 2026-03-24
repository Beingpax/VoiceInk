import Foundation
import AVFoundation
import os

@MainActor
class TTSService: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TTSService")

    @Published var isPlaying = false

    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var currentTask: Task<Void, Never>?
    private var synthesizer: AVSpeechSynthesizer?

    // MVP defaults — ElevenLabs "Rachel" voice + Turbo v2.5 model
    private let defaultVoiceId = "21m00Tcm4TlvDq8ikWAM"
    private let ttsModelId = "eleven_turbo_v2_5"

    // PCM format matching ElevenLabs pcm_16000 output: 16kHz, 16-bit signed LE, mono
    private let pcmFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!

    // Float format for AVAudioPlayerNode (requires float)
    private let floatFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    init() {
        setupAudioEngine()
    }

    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: floatFormat)
    }

    func speak(text: String) async {
        guard !text.isEmpty else { return }

        // Check for ElevenLabs API key, fall back to system TTS
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: "ElevenLabs"), !apiKey.isEmpty else {
            logger.info("No ElevenLabs API key, falling back to system TTS")
            await speakWithSystemTTS(text: text)
            return
        }

        stop()

        isPlaying = true

        let task = Task {
            do {
                try await streamElevenLabsTTS(text: text, apiKey: apiKey)
            } catch {
                if !Task.isCancelled {
                    logger.error("ElevenLabs TTS failed: \(error.localizedDescription, privacy: .public). Falling back to system TTS.")
                    await speakWithSystemTTS(text: text)
                }
            }
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            await MainActor.run {
                self.isPlaying = false
            }
        }
        currentTask = task

        // Wait for playback to actually finish before returning
        await task.value
    }

    func stop() {
        currentTask?.cancel()
        currentTask = nil

        playerNode.stop()
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        synthesizer?.stopSpeaking(at: .immediate)

        isPlaying = false
    }

    // MARK: - ElevenLabs Streaming

    private func streamElevenLabsTTS(text: String, apiKey: String) async throws {
        let urlString = "https://api.elevenlabs.io/v1/text-to-speech/\(defaultVoiceId)/stream"
        guard let url = URL(string: urlString) else {
            throw TTSError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let body: [String: Any] = [
            "text": text,
            "model_id": ttsModelId,
            "output_format": "pcm_16000",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Start audio engine
        if !audioEngine.isRunning {
            try audioEngine.start()
        }
        playerNode.play()

        // Stream the response
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            // Read error body
            var errorData = Data()
            for try await byte in asyncBytes {
                errorData.append(byte)
                if errorData.count > 1024 { break }
            }
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw TTSError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // Buffer PCM bytes and schedule in chunks
        var pcmBuffer = Data()
        let chunkSize = 16000 * 2 // 1 second of 16kHz 16-bit mono audio (32000 bytes)

        for try await byte in asyncBytes {
            try Task.checkCancellation()

            pcmBuffer.append(byte)

            if pcmBuffer.count >= chunkSize {
                scheduleBuffer(pcmData: pcmBuffer)
                pcmBuffer = Data()
            }
        }

        // Schedule remaining bytes with completion handler
        if !pcmBuffer.isEmpty {
            await scheduleBufferAndWait(pcmData: pcmBuffer)
        } else {
            // Wait for last scheduled buffer to finish
            await waitForPlaybackCompletion()
        }
    }

    private func scheduleBufferAndWait(pcmData: Data) async {
        let usableBytes = pcmData.count & ~1
        let sampleCount = usableBytes / 2
        guard sampleCount > 0 else { return }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: AVAudioFrameCount(sampleCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(sampleCount)

        guard let floatData = buffer.floatChannelData?[0] else { return }
        pcmData.withUnsafeBytes { rawBuffer in
            guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<sampleCount {
                floatData[i] = Float(int16Ptr[i]) / Float(Int16.max)
            }
        }

        await withCheckedContinuation { continuation in
            playerNode.scheduleBuffer(buffer) {
                continuation.resume()
            }
        }
    }

    private func scheduleBuffer(pcmData: Data) {
        let usableBytes = pcmData.count & ~1 // Ensure even byte count for Int16 alignment
        let sampleCount = usableBytes / 2 // 16-bit = 2 bytes per sample
        guard sampleCount > 0 else { return }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            logger.error("Failed to create audio buffer")
            return
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)

        // Convert Int16 PCM to Float32
        guard let floatData = buffer.floatChannelData?[0] else { return }
        pcmData.withUnsafeBytes { rawBuffer in
            guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<sampleCount {
                floatData[i] = Float(int16Ptr[i]) / Float(Int16.max)
            }
        }

        playerNode.scheduleBuffer(buffer)
    }

    private func waitForPlaybackCompletion() async {
        // Brief wait for any remaining audio to drain
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms grace period
    }

    // MARK: - System TTS Fallback

    private func speakWithSystemTTS(text: String) async {
        await MainActor.run {
            isPlaying = true
        }

        let synth = AVSpeechSynthesizer()
        self.synthesizer = synth

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        synth.speak(utterance)

        // Wait for completion
        while synth.isSpeaking && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        await MainActor.run {
            self.isPlaying = false
            self.synthesizer = nil
        }
    }
}

enum TTSError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid TTS URL"
        case .invalidResponse: return "Invalid TTS response"
        case .apiError(let code, let msg): return "TTS API error \(code): \(msg)"
        case .noAPIKey: return "No ElevenLabs API key configured"
        }
    }
}
