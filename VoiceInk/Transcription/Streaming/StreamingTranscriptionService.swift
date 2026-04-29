import Foundation
import SwiftData
import os

/// Sendable source that bridges audio chunks from any thread into an AsyncStream.
private final class AudioChunkSource: @unchecked Sendable {
    let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        self.stream = stream
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    func send(_ data: Data) {
        continuation.yield(data)
    }

    func finish() {
        continuation.finish()
    }
}

private final class StreamingMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var receivedChunks = 0
    private var receivedBytes = 0
    private var sentChunks = 0
    private var sentBytes = 0

    func reset() {
        lock.lock()
        receivedChunks = 0
        receivedBytes = 0
        sentChunks = 0
        sentBytes = 0
        lock.unlock()
    }

    func recordReceived(_ byteCount: Int) {
        lock.lock()
        receivedChunks += 1
        receivedBytes += byteCount
        lock.unlock()
    }

    func recordSent(_ byteCount: Int) {
        lock.lock()
        sentChunks += 1
        sentBytes += byteCount
        lock.unlock()
    }

    func snapshot() -> (receivedChunks: Int, receivedBytes: Int, sentChunks: Int, sentBytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (receivedChunks, receivedBytes, sentChunks, sentBytes)
    }
}

/// Lifecycle states for a streaming transcription session.
enum StreamingState {
    case idle
    case connecting
    case streaming
    case committing
    case done
    case failed
    case cancelled
}

/// Manages a streaming transcription lifecycle: buffers audio chunks, sends them to the provider, and collects the final text.
@MainActor
class StreamingTranscriptionService {

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "StreamingTranscriptionService")
    private var provider: StreamingTranscriptionProvider?
    private var sendTask: Task<Void, Never>?
    private var eventConsumerTask: Task<Void, Never>?
    private let chunkSource = AudioChunkSource()
    private var state: StreamingState = .idle
    private var committedSegments: [String] = []
    private let modelContext: ModelContext
    private let fluidAudioService: FluidAudioTranscriptionService?
    private var onPartialTranscript: ((String) -> Void)?
    private let metrics = StreamingMetrics()
    private var stopStartedAt: Date?
    private var firstPartialLogged = false
    private var firstCommitLogged = false

    init(modelContext: ModelContext, fluidAudioService: FluidAudioTranscriptionService? = nil, onPartialTranscript: ((String) -> Void)? = nil) {
        self.modelContext = modelContext
        self.fluidAudioService = fluidAudioService
        self.onPartialTranscript = onPartialTranscript
    }

    deinit {
        onPartialTranscript = nil
        sendTask?.cancel()
        eventConsumerTask?.cancel()
        chunkSource.finish()
        commitSignal?.finish()
    }

    /// Signal used to notify `waitForFinalCommit` when a new committed segment arrives.
    private var commitSignal: AsyncStream<Void>.Continuation?

    /// Whether the streaming connection is fully established and actively sending.
    var isActive: Bool { state == .streaming || state == .committing }

    /// Start a streaming transcription session for the given model.
    func startStreaming(model: any TranscriptionModel) async throws {
        let start = Date()
        state = .connecting
        committedSegments = []
        metrics.reset()
        firstPartialLogged = false
        firstCommitLogged = false

        let provider = createProvider(for: model)
        self.provider = provider

        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        logger.notice("Streaming start requested model=\(model.displayName, privacy: .public) language=\(selectedLanguage, privacy: .public)")

        try await provider.connect(model: model, language: selectedLanguage)

        // If cancel() was called while we were awaiting the connection, tear down immediately.
        if state == .cancelled {
            await provider.disconnect()
            self.provider = nil
            return
        }

        state = .streaming
        startSendLoop()
        startEventConsumer()

        logger.notice("Streaming connected model=\(model.displayName, privacy: .public) elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s")
    }

    /// Buffers an audio chunk for sending. Safe to call from the audio callback thread.
    nonisolated func sendAudioChunk(_ data: Data) {
        metrics.recordReceived(data.count)
        chunkSource.send(data)
    }

    /// Stops streaming, commits remaining audio, and returns the final transcribed text.
    func stopAndGetFinalText() async throws -> String {
        guard let provider = provider, state == .streaming else {
            throw StreamingTranscriptionError.notConnected
        }

        state = .committing
        stopStartedAt = Date()
        let beforeDrain = metrics.snapshot()
        logger.notice("Streaming stop requested receivedChunks=\(beforeDrain.receivedChunks, privacy: .public) sentChunks=\(beforeDrain.sentChunks, privacy: .public) receivedBytes=\(beforeDrain.receivedBytes, privacy: .public) sentBytes=\(beforeDrain.sentBytes, privacy: .public)")

        // Finish the chunk source so the send loop drains remaining chunks and exits naturally.
        await drainRemainingChunks()

        // Set up the commit signal BEFORE sending commit to avoid a race with the response.
        let (signalStream, signalContinuation) = AsyncStream.makeStream(of: Void.self)
        self.commitSignal = signalContinuation

        // Send commit to finalize any remaining audio
        do {
            try await provider.commit()
        } catch {
            commitSignal?.finish()
            commitSignal = nil
            logger.error("Failed to send commit: \(error.localizedDescription, privacy: .public)")
            state = .failed
            await cleanupStreaming()
            throw error
        }

        // Wait for the server to acknowledge our commit (or timeout)
        let finalText = await waitForFinalCommit(signalStream: signalStream)
        if let stopStartedAt {
            logger.notice("Streaming stop completed elapsed=\(Date().timeIntervalSince(stopStartedAt), format: .fixed(precision: 3), privacy: .public)s finalChars=\(finalText.count, privacy: .public)")
        }

        state = .done
        await cleanupStreaming()

        return finalText
    }

    /// Cancels the streaming session without waiting for results.
    func cancel() {
        state = .cancelled
        onPartialTranscript = nil
        eventConsumerTask?.cancel()
        eventConsumerTask = nil
        sendTask?.cancel()
        sendTask = nil
        chunkSource.finish()

        // Clean up commit signal if waiting
        commitSignal?.finish()
        commitSignal = nil

        let providerToDisconnect = provider
        provider = nil

        Task {
            await providerToDisconnect?.disconnect()
        }

        committedSegments = []
        logger.notice("Streaming cancelled")
    }

    // MARK: - Private

    private func createProvider(for model: any TranscriptionModel) -> StreamingTranscriptionProvider {
        if model.provider == .fluidAudio {
            guard let fluidAudioService else {
                fatalError("FluidAudioTranscriptionService required for FluidAudio streaming. Ensure it is passed to StreamingTranscriptionService.")
            }
            return FluidAudioStreamingProvider(fluidAudioService: fluidAudioService)
        }
        guard let cloudProvider = CloudProviderRegistry.provider(for: model.provider),
              let streamingProvider = cloudProvider.makeStreamingProvider(modelContext: modelContext) else {
            fatalError("Unsupported streaming provider: \(model.provider). Check supportsStreaming() before calling startStreaming().")
        }
        return streamingProvider
    }

    /// Consumes audio chunks from the AsyncStream and sends them to the provider.
    private func startSendLoop() {
        let source = chunkSource
        let provider = provider
        let metrics = metrics

        sendTask = Task.detached { [weak self] in
            for await chunk in source.stream {
                do {
                    try await provider?.sendAudioChunk(chunk)
                    metrics.recordSent(chunk.count)
                } catch {
                    let desc = error.localizedDescription
                    await MainActor.run {
                        self?.logger.error("Failed to send audio chunk: \(desc, privacy: .public)")
                    }
                }
            }
        }
    }

    /// Finishes the chunk source and waits for the send loop to process all remaining buffered chunks.
    private func drainRemainingChunks() async {
        let start = Date()
        chunkSource.finish()
        await sendTask?.value
        sendTask = nil
        let snapshot = metrics.snapshot()
        logger.notice("Streaming drain finished elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s receivedChunks=\(snapshot.receivedChunks, privacy: .public) sentChunks=\(snapshot.sentChunks, privacy: .public) receivedBytes=\(snapshot.receivedBytes, privacy: .public) sentBytes=\(snapshot.sentBytes, privacy: .public)")
    }

    /// Consumes transcription events throughout the session, accumulating committed segments.
    private func startEventConsumer() {
        guard let provider = provider else { return }
        let events = provider.transcriptionEvents

        eventConsumerTask = Task.detached { [weak self] in
            for await event in events {
                guard let self = self else { break }
                switch event {
                case .committed(let text):
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run {
                        if !self.firstCommitLogged {
                            self.firstCommitLogged = true
                            let elapsed = self.stopStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                            self.logger.notice("Streaming first committed event chars=\(trimmed.count, privacy: .public) stopElapsed=\(elapsed, format: .fixed(precision: 3), privacy: .public)s")
                        }
                        if !trimmed.isEmpty {
                            self.committedSegments.append(trimmed)
                        }
                        // Refresh the live preview so it keeps showing the full running transcript
                        // after a commit (instead of resetting to empty until the next partial).
                        if self.state == .streaming {
                            self.onPartialTranscript?(self.committedSegments.joined(separator: " "))
                        }
                        if self.state == .committing {
                            self.commitSignal?.yield()
                        }
                    }
                case .partial(let text):
                    await MainActor.run {
                        if !self.firstPartialLogged {
                            self.firstPartialLogged = true
                            self.logger.notice("Streaming first partial event chars=\(text.count, privacy: .public)")
                        }
                        if self.state == .streaming {
                            let prefix = self.committedSegments.joined(separator: " ")
                            let display: String
                            if prefix.isEmpty {
                                display = text
                            } else if text.hasPrefix(prefix) || text.hasPrefix(prefix + " ") {
                                // Provider already sends cumulative partials (e.g. FluidAudio fullText).
                                display = text
                            } else {
                                display = prefix + " " + text
                            }
                            self.onPartialTranscript?(display)
                        }
                    }
                case .sessionStarted:
                    break
                case .error(let error):
                    await MainActor.run {
                        self.logger.error("Streaming event error: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }  
        }
    }

    /// Waits for the server to acknowledge our explicit commit, with a 10-second timeout.
    private func waitForFinalCommit(signalStream: AsyncStream<Void>) async -> String {
        // Race: wait for commit acknowledgment vs timeout
        let receivedInTime = await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                for await _ in signalStream {
                    return true
                }
                return false
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
        logger.notice("Streaming final wait finished received=\(receivedInTime, privacy: .public) segments=\(self.committedSegments.count, privacy: .public)")

        // Clean up the signal
        commitSignal?.finish()
        commitSignal = nil

        if !receivedInTime && committedSegments.isEmpty {
            logger.warning("No transcript received from streaming")
        }

        return committedSegments.isEmpty ? "" : committedSegments.joined(separator: " ")
    }

    private func cleanupStreaming() async {
        onPartialTranscript = nil
        eventConsumerTask?.cancel()
        eventConsumerTask = nil
        sendTask?.cancel()
        sendTask = nil
        chunkSource.finish()
        commitSignal?.finish()
        commitSignal = nil
        await provider?.disconnect()
        provider = nil
        state = .idle
        committedSegments = []
    }
}
