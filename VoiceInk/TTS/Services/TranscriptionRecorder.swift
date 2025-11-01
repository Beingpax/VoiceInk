import AVFoundation

final class TranscriptionRecorder {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private let levelLock = NSLock()
    private var lastLevel: Float = 0
    private var tapInstalled = false

    @MainActor
    func startRecording() async throws -> URL {
        try await Self.ensurePermission()

        if engine.isRunning {
            engine.stop()
        }
        engine.reset()

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let recordingURL = makeRecordingURL()
        let file = try AVAudioFile(forWriting: recordingURL, settings: format.settings)

        if tapInstalled {
            inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        let levelSink: (Float) -> Void = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.setLevel(level)
            }
        }

        let tapHandler = Self.makeTapHandler(file: file, levelSink: levelSink)

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format, block: tapHandler)

        audioFile = file
        currentURL = recordingURL
        lastLevel = 0
        tapInstalled = true

        engine.prepare()
        try engine.start()

        return recordingURL
    }

    @MainActor
    func stopRecording() -> URL? {
        let url = currentURL
        teardownRecording()
        return url
    }

    @MainActor
    func cancelRecording() -> URL? {
        let url = currentURL
        teardownRecording()
        return url
    }

    func currentLevel() -> Float {
        levelLock.lock()
        let value = lastLevel
        levelLock.unlock()
        return value
    }

    @MainActor
    private func teardownRecording() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
        audioFile = nil
        currentURL = nil
    }

    private static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channel = channelData[0]
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for frame in 0..<frameLength {
            let sample = channel[frame]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))
        let minDb: Float = -60
        let db = 20 * log10(max(rms, 0.000_000_1))
        let clamped = max(minDb, db)
        let normalized = (clamped - minDb) / abs(minDb)
        return max(0, min(1, normalized))
    }

    @MainActor
    private func setLevel(_ level: Float) {
        levelLock.lock()
        lastLevel = level
        levelLock.unlock()
    }

    private static func makeTapHandler(file: AVAudioFile,
                                       levelSink: @escaping (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            do {
                try file.write(from: buffer)
            } catch {
                // Ignore transient write errors
            }
            let level = normalizedLevel(from: buffer)
            levelSink(level)
        }
    }

    private static func ensurePermission() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            guard granted else {
                throw TTSError.apiError("Microphone access is required to record audio")
            }
        default:
            throw TTSError.apiError("Enable microphone access in System Settings")
        }
    }

    private func makeRecordingURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
        let filename = "transcription-recording-\(UUID().uuidString).wav"
        return directory.appendingPathComponent(filename)
    }
}
