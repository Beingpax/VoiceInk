import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import os

private final class RealtimeAudioChunkGate: @unchecked Sendable {
    private struct State {
        var bufferedChunks: [Data] = []
        var callback: ((Data) -> Void)?
        var isActive = false
        var droppedChunks = 0
    }

    private let maxBufferedChunks = 2_048
    private let state = OSAllocatedUnfairLock(initialState: State())

    func receive(_ data: Data) {
        let callback = state.withLock { state -> ((Data) -> Void)? in
            guard state.isActive else {
                if state.bufferedChunks.count < maxBufferedChunks {
                    state.bufferedChunks.append(data)
                } else {
                    state.droppedChunks += 1
                }
                return nil
            }
            return state.callback
        }
        callback?(data)
    }

    func activate(_ callback: @escaping (Data) -> Void) -> Int {
        let initialState = state.withLock { state -> (chunks: [Data], droppedChunks: Int) in
            state.callback = callback
            state.isActive = false
            let chunks = state.bufferedChunks
            let droppedChunks = state.droppedChunks
            state.bufferedChunks.removeAll()
            state.droppedChunks = 0
            return (chunks, droppedChunks)
        }
        var chunksToSend = initialState.chunks
        var droppedChunks = initialState.droppedChunks

        while true {
            for chunk in chunksToSend {
                callback(chunk)
            }

            let nextState = state.withLock { state -> (chunks: [Data], droppedChunks: Int, finished: Bool) in
                let droppedChunks = state.droppedChunks
                state.droppedChunks = 0
                guard !state.bufferedChunks.isEmpty else {
                    state.isActive = true
                    return ([], droppedChunks, true)
                }
                let chunks = state.bufferedChunks
                state.bufferedChunks.removeAll()
                return (chunks, droppedChunks, false)
            }
            droppedChunks += nextState.droppedChunks

            if nextState.finished {
                return droppedChunks
            }
            chunksToSend = nextState.chunks
        }
    }

    func reset() -> Int {
        state.withLock { state -> Int in
            let droppedChunks = state.droppedChunks
            state.bufferedChunks.removeAll()
            state.callback = nil
            state.isActive = false
            state.droppedChunks = 0
            return droppedChunks
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VoiceInkEngine — MULTI-SESSION refactor (record-while-transcribing)
// ═══════════════════════════════════════════════════════════════════════════════
//
// WHAT CHANGED vs the old single-flight engine:
//   OLD: one `currentSession`/`recordedFile`/`shouldCancelRecording`/`partialTranscript`
//        set, and STOP awaited `runPipeline` INLINE before the mic could be reused.
//   NEW: a COLLECTION of RecordingSession objects (`sessions`). At most one is
//        `.recording` (owns the mic); the rest are transcribing/delivering in the
//        background. STOP no longer awaits the pipeline — it ENQUEUES the pipeline on
//        a SERIAL FIFO queue and returns immediately, freeing the mic for a new record.
//
// See RecordingSession.swift for the per-session state machine + the one-active invariant.
//
// ── CONCURRENCY: SERIAL FIFO transcription queue (NOT concurrent) ──────────────
// Transcription jobs run one-at-a-time on a chained-Task serial queue. This is a
// DELIBERATE correctness decision, not a perf compromise:
//   • WhisperTranscriptionService reuses a single mutable `whisperContext`, and
//     `whisperModelManager.whisperContext` is a SHARED singleton actor. setLanguage /
//     setPrompt then fullTranscribe are sequential stateful mutations on ONE shared
//     context — running two whisper jobs concurrently would interleave language/prompt
//     state and corrupt output.
//   • `whisperModelManager.cleanupResources()` / `serviceRegistry.cleanup()` release the
//     SHARED model — concurrent jobs would tear each other's model down mid-transcribe.
//   • FluidAudio also loads a single shared model.
//   • The cloud/Deepgram path COULD be concurrency-safe, but the provider is chosen
//     per-job and we can't assume it, so a single serial queue is the only universally
//     safe choice.
//   • The UX goal is STILL met: the new RECORDING starts immediately (mic frees the
//     instant the prior session stops); only the transcription WORK queues behind
//     earlier jobs. Serial = simplest race-free correctness.
//
// ── DELIVERY ORDERING: FIFO for free ───────────────────────────────────────────
// We deliver/paste results in RECORDING (FIFO) order so pasted text stays in the order
// the user spoke. Because transcription itself is serial FIFO, completion order already
// EQUALS recording order — so the serial transcription queue gives FIFO delivery for
// free with NO separate delivery reorder buffer required.
// NOTE: RecorderStateProvider conformance is declared in VoiceInkEngine+Protocols.swift
// (extension VoiceInkEngine: RecorderStateProvider {}). We intentionally do NOT repeat it
// here — the engine already exposes `recordingState` + `partialTranscript` (the protocol
// requirements) as @Published members below, so the extension's conformance is satisfied.
@MainActor
class VoiceInkEngine: NSObject, ObservableObject {

    // ── Session collection (drives the UI stack) ──
    // Ordered oldest→newest (creation order). The base/active recording card renders from
    // the .recording session; transcribing cards stack above it. @Published so the stack
    // container redraws on add/remove.
    @Published var sessions: [RecordingSession] = []

    // ── DERIVED compat state ──
    // Existing single-card UI (the active MiniRecorderView/NotchRecorderView via the
    // window managers) + RecorderUIManager + the shortcut gate all read `recordingState`
    // and `partialTranscript` off the engine. We KEEP those as DERIVED values so nothing
    // downstream has to change to keep compiling.
    //
    // IMPORTANT DESIGN CHOICE (shortcut-gate safety): `recordingState` reflects ONLY the
    // ACTIVE recording session's state, else `.idle` — it does NOT report `.transcribing`
    // when there is no active recording. Rationale: RecordingShortcutManager.canHandleShort
    // cutAction() BLOCKS a record toggle whenever recordingState is .transcribing/.enhancing/
    // .busy. If the derived state reported `.transcribing` while a background job ran, the
    // user could NOT start a new recording — which would defeat this entire feature. The
    // stacked-card UI shows the "transcribing…" cards directly off each session.phase, so
    // the derived engine state never needs to surface .transcribing for the stack to render.
    // (Per-card status spinners read the session's own liveRecordingState, not this.)
    @Published var recordingState: RecordingState = .idle

    // Live partial of the ACTIVE recording session (only the recording session streams partials).
    @Published var partialTranscript: String = ""

    // ── Pipeline cancel-poisoning ──
    // Set of Transcription ids whose pipeline result must be DISCARDED (per-session cancel).
    // Keyed by RecordingSession.pipelineTranscriptionID so cancelling one session can never
    // discard another's finished 200. (The old global shouldCancelRecording flag is gone;
    // cancel is now per-session via RecordingSession.shouldCancel + this set.)
    private var canceledPipelineTranscriptionIDs = Set<UUID>()

    // ── Serial transcription queue (chained Task on the MainActor) ──
    // Each enqueue appends to a Task chain: the new tail awaits the previous tail's value
    // before running its pipeline. This guarantees:
    //   (a) FIFO order — jobs run in the order they were enqueued (= recording order), and
    //   (b) full serialization — each pipeline fully finishes (transcribe→enhance→deliver)
    //       before the next begins, so they never share the whisper/fluidaudio model.
    // `prev?.value` never throws (Task<Void, Never>); we simply await it to chain.
    private var transcriptionQueueTail: Task<Void, Never>?

    let recorder = Recorder()
    let recordingsDirectory: URL

    // Injected managers
    let whisperModelManager: WhisperModelManager
    let transcriptionModelManager: TranscriptionModelManager
    weak var recorderUIManager: RecorderPanelPresenting?

    let modelContext: ModelContext
    internal let serviceRegistry: TranscriptionServiceRegistry
    let enhancementService: AIEnhancementService?
    let assistantSession = AssistantSession()
    let assistantChat: AssistantChatService?
    private let pipeline: TranscriptionPipeline

    let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "VoiceInkEngine")

    init(
        modelContext: ModelContext,
        whisperModelManager: WhisperModelManager,
        transcriptionModelManager: TranscriptionModelManager,
        enhancementService: AIEnhancementService? = nil
    ) {
        self.modelContext = modelContext
        self.whisperModelManager = whisperModelManager
        self.transcriptionModelManager = transcriptionModelManager
        self.enhancementService = enhancementService
        if let aiService = enhancementService?.getAIService() {
            self.assistantChat = AssistantChatService(
                modelContext: modelContext,
                aiService: aiService
            )
        } else {
            self.assistantChat = nil
        }

        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
        self.recordingsDirectory = appSupportDirectory.appendingPathComponent("Recordings")

        self.serviceRegistry = TranscriptionServiceRegistry(
            modelProvider: whisperModelManager,
            modelsDirectory: whisperModelManager.modelsDirectory,
            modelContext: modelContext
        )
        self.pipeline = TranscriptionPipeline(
            modelContext: modelContext,
            serviceRegistry: serviceRegistry,
            enhancementService: enhancementService
        )

        super.init()

        setupNotifications()
        createRecordingsDirectoryIfNeeded()
    }

    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error("❌ Error creating recordings directory: \(error, privacy: .public)")
        }
    }

    func getEnhancementService() -> AIEnhancementService? {
        return enhancementService
    }

    // MARK: - Session Accessors

    /// The one session currently capturing audio (mic owner), if any. By the one-active
    /// invariant there is at most one. nil ⇒ no recording in progress (idle OR only
    /// background transcriptions running).
    var activeRecordingSession: RecordingSession? {
        sessions.first { $0.phase == .recording }
    }

    /// The most-recent in-flight transcribing/delivering session (the "top card"). Used as
    /// the cancel target when no session is actively recording.
    private var topInFlightSession: RecordingSession? {
        sessions.last { $0.phase == .transcribing || $0.phase == .delivering }
    }

    /// Recompute the DERIVED compat `recordingState` + `partialTranscript` from the active
    /// recording session. See the big comment on `recordingState` for why we deliberately
    /// fall back to `.idle` (NOT a transcribing session's state) when nothing is recording.
    private func recomputeDerivedState() {
        if let active = activeRecordingSession {
            recordingState = active.liveRecordingState
            partialTranscript = active.partialTranscript
        } else {
            // No active recording. Background jobs may still be transcribing, but we report
            // .idle so the record shortcut stays usable (can start a new dictation).
            recordingState = .idle
            partialTranscript = ""
        }
    }

    /// Remove a finished/aborted session from the collection + recompute derived state.
    /// SwiftUI animates the card out (transition on the `sessions` array).
    private func removeSession(_ session: RecordingSession) {
        session.phase = .done
        session.clearContext()
        sessions.removeAll { $0.id == session.id }
        recomputeDerivedState()
    }

    // MARK: - Toggle Record

    // The single entry point for the record shortcut / record button. Behaviour:
    //   • A session is actively RECORDING → STOP it (move to .transcribing + enqueue its
    //     pipeline on the serial queue, NON-blocking). Mic frees immediately.
    //   • The active session is mid-START handshake (.starting) → cancel that not-yet-
    //     started session (re-press during the brief start window).
    //   • Otherwise (idle OR only background transcriptions running) → START a fresh
    //     active session.
    func toggleRecord(modeId: UUID? = nil, isAssistantFollowUp: Bool = false) async {
        // Mid-start re-press: the active session is still starting → cancel it.
        if let active = activeRecordingSession, active.liveRecordingState == .starting {
            await cancelSession(active)
            return
        }

        if let active = activeRecordingSession {
            // ── STOP branch ──────────────────────────────────────────────────────────
            // The mic owner stops. We flip its phase .recording→.transcribing, release the
            // mic (recorder.stopRecording), build its Transcription record, and ENQUEUE the
            // pipeline on the serial queue. CRITICAL: we do NOT await the pipeline here —
            // that inline await is exactly what blocked the next start in the old engine.
            // The function returns as soon as the mic is free, so a record press right after
            // can immediately START a new session.
            logger.info("toggleRecord: STOP session \(active.id.uuidString, privacy: .public) → .transcribing (shouldCancel=\(active.shouldCancel, privacy: .public))")

            active.phase = .transcribing
            active.liveRecordingState = .transcribing
            active.partialTranscript = ""
            active.startID = UUID() // invalidate the start handshake token (it has fully started)
            recomputeDerivedState()

            await recorder.stopRecording()
            // ── MEDIA RESUME-BETWEEN-SESSIONS NUANCE ──
            // recorder.stopRecording() schedules resumeMedia()/unmuteSystemAudio(). If the
            // user immediately starts session B, recorder.startRecording() will pauseMedia()/
            // muteSystemAudio() again. So media may briefly resume in the gap between stop and
            // the next start — that's acceptable and self-consistent: the single Recorder is
            // only ever owned by the single active recording session, so its pause/resume
            // bracketing always pairs with exactly one recording at a time.

            if let audioURL = active.audioURL {
                if !active.shouldCancel {
                    // Build the pending Transcription record and enqueue the pipeline.
                    let transcription = makeRecordingTranscription(
                        for: audioURL,
                        text: "",
                        duration: 0,
                        transcriptionStatus: .pending
                    )
                    modelContext.insert(transcription)
                    try? modelContext.save()
                    NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)

                    active.pipelineTranscriptionID = transcription.id
                    enqueueTranscription(for: active, transcription: transcription)
                } else {
                    // Cancelled while recording → save a canceled record, no pipeline.
                    await finishCanceledRecording(active)
                    removeSession(active)
                }
            } else {
                // No file captured (e.g. start failed). Just tear the session down.
                if !active.shouldCancel {
                    logger.error("❌ No recorded file found after stopping recording")
                }
                active.transcriptionSession?.cancel()
                removeSession(active)
                await cleanupResources()
            }
        } else {
            // ── START branch ─────────────────────────────────────────────────────────
            // Defensive invariant assert: never create a second .recording session. The
            // toggle path guarantees this (a press while recording hits the STOP branch),
            // but assert it anyway.
            assert(activeRecordingSession == nil, "one-active-recording invariant violated")

            let canContinueAssistantSession = isAssistantFollowUp && assistantSession.canSendFollowUp
            let useCase: RecordingSession.UseCase = canContinueAssistantSession ? .assistantFollowUp : .newSession

            if !useCase.isAssistantFollowUp {
                assistantSession.reset()
            }

            requestRecordPermission { [self] granted in
                if granted {
                    Task { @MainActor [self] in
                        await self.startNewSession(modeId: modeId, useCase: useCase)
                    }
                } else {
                    logger.error("Recording permission denied")
                }
            }
        }
    }

    // MARK: - Start a fresh session

    // Creates a brand-new RecordingSession, drives the same start handshake the old engine
    // used (permission already granted, recorder.startRecording, mode config apply, streaming
    // session prepare, model preload), and appends it to `sessions` with phase .recording.
    private func startNewSession(modeId: UUID?, useCase: RecordingSession.UseCase) async {
        let startID = UUID()
        let session = RecordingSession(phase: .recording, useCase: useCase, startID: startID)
        // Born .recording but we drive it through .starting → .recording during the handshake.
        session.liveRecordingState = .starting

        // Append to the collection so the card appears immediately (shows the .starting state).
        sessions.append(session)
        recomputeDerivedState()

        let activeModeTask = ActiveWindowService.shared.beginApplyingConfiguration(modeId: modeId) { [weak self, weak session] in
            guard let self, let session else { return false }
            // Only keep applying config while THIS session is still the live start.
            return session.startID == startID && !session.shouldCancel && self.sessions.contains(where: { $0.id == session.id })
        }

        do {
            let fileName = "\(UUID().uuidString).wav"
            let permanentURL = self.recordingsDirectory.appendingPathComponent(fileName)
            session.audioURL = permanentURL

            // Buffer audio chunks until the streaming session (if any) is ready to receive them.
            let pendingChunks = OSAllocatedUnfairLock(initialState: [Data]())
            self.recorder.onAudioChunk = { data in
                pendingChunks.withLock { $0.append(data) }
            }

            session.liveRecordingState = .starting
            recomputeDerivedState()

            try await self.recorder.startRecording(toOutputFile: permanentURL)

            // Re-press / cancel / panel-gone guard: if this is no longer the live start, abort.
            guard session.startID == startID,
                  self.sessions.contains(where: { $0.id == session.id }),
                  self.recorderUIManager?.isRecorderPanelVisible ?? false,
                  !session.shouldCancel else {
                activeModeTask.cancel()
                let shouldKeepRecordingFile = session.shouldCancel
                if session.startID == startID {
                    await self.recorder.stopRecording()
                    if !shouldKeepRecordingFile {
                        session.audioURL = nil
                    }
                    self.removeSession(session)
                }
                return
            }

            session.liveRecordingState = .recording
            session.phase = .recording
            recomputeDerivedState()

            await activeModeTask.value

            guard session.liveRecordingState == .recording,
                  session.startID == startID,
                  !session.shouldCancel else {
                return
            }

            // Begin app/window context capture for AI enhancement.
            self.startRecordingContextCapture(for: session)

            guard let transcriptionConfiguration = ModeRuntimeResolver.transcriptionConfiguration(
                transcriptionModelManager: self.transcriptionModelManager
            ) else {
                NotificationManager.shared.showNotification(title: String(localized: "No AI Model Selected"), type: .error)
                await self.recorder.stopRecording()
                try? FileManager.default.removeItem(at: permanentURL)
                session.audioURL = nil
                self.removeSession(session)
                await self.cleanupResources()
                await self.recorderUIManager?.dismissRecorderPanel()
                return
            }

            session.transcriptionConfiguration = transcriptionConfiguration

            if self.serviceRegistry.shouldUseRealtimeTranscription(for: transcriptionConfiguration) {
                let streamingSession = self.serviceRegistry.createSession(
                    for: transcriptionConfiguration,
                    onPartialTranscript: { [weak self, weak session] partial in
                        Task { @MainActor in
                            guard let self, let session,
                                  session.startID == startID,
                                  session.liveRecordingState == .recording else {
                                return
                            }
                            session.partialTranscript = partial
                            // Mirror to the engine's derived partial only while this is the
                            // active recording session (it always is here, but be explicit).
                            if self.activeRecordingSession?.id == session.id {
                                self.partialTranscript = partial
                            }
                        }
                    }
                )
                session.transcriptionSession = streamingSession
                let realCallback = try await streamingSession.prepare(
                    configuration: transcriptionConfiguration
                )

                if let realCallback {
                    self.recorder.onAudioChunk = realCallback
                    let buffered = pendingChunks.withLock { chunks -> [Data] in
                        let result = chunks
                        chunks.removeAll()
                        return result
                    }
                    for chunk in buffered { realCallback(chunk) }
                }
            } else {
                session.transcriptionSession = nil
                self.recorder.onAudioChunk = nil
                pendingChunks.withLock { $0.removeAll() }
            }

            // Best-effort model preload so the eventual transcribe is fast.
            Task { @MainActor [weak self] in
                guard let self else { return }

                let currentModel = ModeRuntimeResolver.transcriptionConfiguration(
                    transcriptionModelManager: self.transcriptionModelManager
                )?.model

                if let model = currentModel,
                   model.provider == .whisper {
                    if let localWhisperModel = self.whisperModelManager.availableModels.first(where: { $0.name == model.name }),
                       self.whisperModelManager.whisperContext == nil {
                        do {
                            try await self.whisperModelManager.loadModel(localWhisperModel)
                        } catch {
                            self.logger.error("❌ Model loading failed: \(error, privacy: .public)")
                        }
                    }
                } else if let fluidAudioModel = currentModel as? FluidAudioModel {
                    try? await self.serviceRegistry.fluidAudioTranscriptionService.loadModel(for: fluidAudioModel)
                }
            }

        } catch {
            activeModeTask.cancel()
            self.logger.error("Recording failed to start: \(error, privacy: .public)")
            await self.recorder.stopRecording()
            session.transcriptionSession?.cancel()
            if let recordedFile = session.audioURL {
                try? FileManager.default.removeItem(at: recordedFile)
            }
            session.audioURL = nil
            self.removeSession(session)
            await self.cleanupResources()
            NotificationManager.shared.showNotification(title: String(localized: "Recording failed to start"), type: .error)
            await self.recorderUIManager?.dismissRecorderPanel()
        }
    }

    private func requestRecordPermission(response: @escaping (Bool) -> Void) {
        response(true)
    }

    // MARK: - Recording Context

    private func startRecordingContextCapture(for session: RecordingSession) {
        session.clearContext()

        let store = RecordingContextSnapshotStore()
        session.contextStore = store
        session.contextTasks = RecordingContextCaptureService.startCapture(into: store)
    }

    // MARK: - Serial Transcription Queue

    // Enqueue this session's pipeline onto the serial FIFO chain. See the
    // `transcriptionQueueTail` declaration for the full serialization rationale. We capture
    // the previous tail, then replace it with a new Task that first awaits the previous
    // tail's completion, then runs THIS session's pipeline to completion. Result: pipelines
    // run strictly one-after-another in enqueue (= recording) order ⇒ FIFO delivery for free.
    private func enqueueTranscription(for session: RecordingSession, transcription: Transcription) {
        let previousTail = transcriptionQueueTail
        transcriptionQueueTail = Task { @MainActor [weak self] in
            // Wait for all earlier-enqueued pipelines to finish first (serial chain).
            await previousTail?.value
            guard let self else { return }
            await self.runPipeline(for: session, transcription: transcription)
        }
    }

    // MARK: - Pipeline Dispatch

    // Run the full transcribe→enhance→deliver pipeline for ONE session, using that session's
    // stored config / transcription session / context store / pipeline id (NOT engine
    // singletons). On completion the session is removed from the collection.
    private func runPipeline(for session: RecordingSession, transcription: Transcription) async {
        guard let transcriptionConfiguration = session.transcriptionConfiguration ??
            ModeRuntimeResolver.transcriptionConfiguration(transcriptionModelManager: transcriptionModelManager) else {
            transcription.text = String(localized: "Transcription Failed: No model selected")
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
            try? modelContext.save()
            removeSession(session)
            return
        }

        guard let audioURL = session.audioURL else {
            removeSession(session)
            return
        }

        let streamingSession = session.transcriptionSession
        let transcriptionID = transcription.id
        session.pipelineTranscriptionID = transcriptionID
        session.phase = .delivering // pipeline is running; mark past pure-transcribing
        session.liveRecordingState = .transcribing

        await pipeline.run(
            transcription: transcription,
            audioURL: audioURL,
            transcriptionConfiguration: transcriptionConfiguration,
            formattingConfiguration: {
                ModeRuntimeResolver.transcriptionFormattingConfiguration()
            },
            session: streamingSession,
            triggerWordModeSelection: { [weak self] text in
                self?.selectTriggerWordModeIfNeeded(for: text)
            },
            enhancementConfiguration: { [weak self] in
                guard let self,
                      let enhancementService = self.enhancementService,
                      let aiService = enhancementService.getAIService() else {
                    return nil
                }
                return ModeRuntimeResolver.currentEnhancementConfiguration(
                    enhancementService: enhancementService,
                    aiService: aiService
                )
            },
            recordingContextSnapshot: { [weak session] in
                await MainActor.run {
                    session?.contextStore?.snapshot
                }
            },
            outputConfiguration: {
                ModeRuntimeResolver.outputConfiguration()
            },
            // Per-session UI state: drive this session's card spinner (.enhancing etc.).
            onStateChange: { [weak self, weak session] state in
                guard let session else { return }
                session.liveRecordingState = state
                // Keep the engine's derived state fresh ONLY if this session is the active
                // recording one (it never is during the pipeline, but be defensive).
                self?.recomputeDerivedState()
            },
            shouldCancel: { [weak self, weak session] in
                guard let self else { return false }
                // Per-session cancel: poisoned id OR this session's own cancel flag.
                return self.canceledPipelineTranscriptionIDs.contains(transcriptionID)
                    || (session?.shouldCancel ?? false)
            },
            onCancel: { [weak self, streamingSession] in
                guard let self else { return }
                self.cancelPipelineSession(transcriptionID: transcriptionID, session: streamingSession)
            },
            onDismiss: { [weak self, weak session] in
                guard let self, let session else { return }
                // Only the pipeline owning the TOP/most-recent card should be allowed to
                // dismiss the whole panel; but in practice each pipeline's onDismiss fires
                // at its own completion. We dismiss the panel only when removing the LAST
                // session leaves the collection empty (handled in removeSession + the
                // RecorderUIManager visibility logic). Here we just no-op the per-pipeline
                // dismiss; final hide is decided after removal below.
                _ = session
            },
            assistant: TranscriptionPipeline.AssistantHooks(
                isFollowUp: session.useCase.isAssistantFollowUp,
                sendFollowUp: { [weak self] text, transcription in
                    guard let self else { return }
                    await self.sendAssistantFollowUp(text, transcription: transcription)
                },
                startResponse: { [weak self] transcript, configuration in
                    guard let self else { return }
                    self.assistantSession.beginInitialResponse(
                        transcript: transcript,
                        provider: configuration.provider,
                        modelName: configuration.modelName ?? configuration.provider?.defaultModel,
                        modeName: configuration.mode?.name,
                        modeEmoji: configuration.mode?.icon.value,
                        promptName: configuration.prompt?.title
                    )
                },
                showResponse: { [weak self] response, systemPrompt in
                    guard let self else { return }
                    await self.completeAssistantResponse(response, systemPrompt: systemPrompt)
                },
                failResponse: { [weak self] message in
                    guard let self else { return }
                    self.assistantSession.fail(message)
                }
            )
        )

        // Pipeline finished (delivered, failed, or canceled). Capture the result, release
        // shared model resources, drop the poison key, and remove the session from the stack.
        session.transcript = transcription.text
        canceledPipelineTranscriptionIDs.remove(transcriptionID)
        session.transcriptionSession = nil

        await finishRecorderSession()
        // Release shared model resources only when NO other session still needs them, i.e.
        // when this was the last in-flight job. cleanupResources() tears down the SHARED
        // whisper/fluidaudio model; doing it while another queued job is about to run would
        // force a reload, but the serial queue means the NEXT job hasn't started yet, so a
        // cleanup here is safe (the next job reloads on demand). We still guard on "no other
        // transcribing/delivering session" to avoid needless reload churn.
        removeSession(session)
        if !sessions.contains(where: { $0.phase == .transcribing || $0.phase == .delivering }) {
            await cleanupResources()
        }

        // If the panel is now empty (no sessions + no assistant response), let the UI manager
        // hide it. We trigger a generic dismiss; RecorderUIManager only actually hides when
        // there is nothing left to show.
        if sessions.isEmpty {
            await recorderUIManager?.dismissRecorderPanel()
        }
    }

    private func selectTriggerWordModeIfNeeded(for text: String) -> String? {
        guard let (triggeredMode, processedText) = ModeManager.shared.getConfigurationForTriggerWord(text) else {
            return nil
        }

        ModeManager.shared.setActiveConfiguration(triggeredMode)
        return processedText
    }

    // MARK: - Cancellation

    // Public cancel from the RecorderUIManager / shortcuts. Targets:
    //   • the ACTIVE recording session if one is recording, else
    //   • the most-recent in-flight transcribing/delivering session (top card).
    // This preserves the old "cancel button aborts what's live" UX in the multi-session world.
    func cancelRecording() async {
        if let active = activeRecordingSession {
            await cancelSession(active)
        } else if let top = topInFlightSession {
            await cancelSession(top)
        } else {
            // Nothing to cancel — just recompute derived state.
            recomputeDerivedState()
        }
    }

    // Per-card cancel entry point wired to the per-session "X" (engine.cancelSession(id:)).
    func cancelSession(id: UUID) async {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        await cancelSession(session)
    }

    // Cancel a SPECIFIC session. Behaviour depends on its phase:
    //   • .recording / .starting → stop the mic, save a "canceled" record, remove the card.
    //   • .transcribing / .delivering → poison its pipeline id so its result is DISCARDED
    //     (not pasted). The pipeline's defensive gates still deliver a finished 200 if text
    //     is already in hand (see TranscriptionPipeline) — that's intentional: we never throw
    //     away words the user already got transcribed. The card is removed when the pipeline
    //     unwinds; here we just flag + mark it cancelling.
    func cancelSession(_ session: RecordingSession) async {
        // Poison point. For a recording session this is a clean discard; for an in-flight one
        // it inserts into canceledPipelineTranscriptionIDs which the pipeline's shouldCancel()
        // gate reads to discard the result (subject to the "don't discard a finished result"
        // defensive gates).
        logger.info("cancelSession: \(session.id.uuidString, privacy: .public) phase=\(String(describing: session.phase), privacy: .public) liveState=\(String(describing: session.liveRecordingState), privacy: .public)")

        session.shouldCancel = true
        session.transcriptionSession?.cancel()

        switch session.phase {
        case .recording:
            // Mic owner. Stop capture, persist a canceled record, drop the card.
            session.startID = UUID() // invalidate start handshake
            session.clearContext()
            await recorder.stopRecording()
            await finishCanceledRecording(session)
            removeSession(session)
            await cleanupResources()

        case .transcribing, .delivering:
            // In-flight job. Poison its pipeline id; the running pipeline will pick this up
            // at its next shouldCancel() gate. The card stays until the pipeline unwinds and
            // removeSession() fires in runPipeline's tail (or here if there's no live pipeline).
            if let pipelineID = session.pipelineTranscriptionID {
                logger.info("cancelSession: poisoning pipeline id \(pipelineID.uuidString, privacy: .public)")
                canceledPipelineTranscriptionIDs.insert(pipelineID)
            } else {
                // No pipeline started yet (queued but not running) → just drop the card.
                removeSession(session)
            }
            session.liveRecordingState = .idle
            recomputeDerivedState()

        case .done:
            removeSession(session)
        }
    }

    // Full reset (launch / hard reset): cancel everything, clear the queue, drop all sessions.
    func resetRecordingSession() async {
        // Cancel the serial queue chain so no queued pipeline starts after reset.
        transcriptionQueueTail?.cancel()
        transcriptionQueueTail = nil

        for session in sessions {
            session.shouldCancel = true
            session.transcriptionSession?.cancel()
            session.clearContext()
        }
        sessions.removeAll()
        canceledPipelineTranscriptionIDs.removeAll()
        partialTranscript = ""
        assistantSession.reset()
        recordingState = .idle
        await recorder.stopRecording()
        await cleanupResources()
        await finishRecorderSession()
    }

    // Persist a "canceled" Transcription record for a session whose recording was aborted.
    private func finishCanceledRecording(_ session: RecordingSession) async {
        guard let audioURL = session.audioURL,
              FileManager.default.fileExists(atPath: audioURL.path)
        else { return }

        let duration = await AudioFileMetadata.duration(for: audioURL)
        let transcription = makeRecordingTranscription(
            for: audioURL,
            text: Transcription.canceledTranscriptionText,
            duration: duration,
            transcriptionStatus: .canceled
        )

        modelContext.insert(transcription)

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
        } catch {
            logger.error("Failed to save canceled recording: \(error, privacy: .public)")
        }
    }

    private func makeRecordingTranscription(
        for audioURL: URL,
        text: String,
        duration: TimeInterval,
        transcriptionStatus: TranscriptionStatus
    ) -> Transcription {
        let modeMetadata = currentModeMetadata()

        return Transcription(
            text: text,
            duration: duration,
            audioFileURL: audioURL.absoluteString,
            transcriptionModelName: ModeRuntimeResolver.transcriptionConfiguration(
                transcriptionModelManager: transcriptionModelManager
            )?.model.displayName,
            modeName: modeMetadata.name,
            modeEmoji: modeMetadata.emoji,
            transcriptionStatus: transcriptionStatus
        )
    }

    private func currentModeMetadata() -> (name: String?, emoji: String?) {
        guard let mode = ModeManager.shared.currentEffectiveConfiguration,
              mode.isEnabled else {
            return (nil, nil)
        }

        return (mode.name, mode.icon.value)
    }

    // MARK: - Resource Cleanup

    private func cancelPipelineSession(transcriptionID: UUID, session: TranscriptionSession?) {
        session?.cancel()
    }

    private func finishRecorderSession() async {
        enhancementService?.clearCapturedContexts()
    }

    func cleanupResources() async {
        logger.notice("cleanupResources: releasing model resources")
        await whisperModelManager.cleanupResources()
        await serviceRegistry.cleanup()
        logger.notice("cleanupResources: completed")
    }

    // MARK: - Notification Handling

    func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePromptChange),
            name: .promptDidChange,
            object: nil
        )
    }

    @objc func handlePromptChange() {
        Task {
            let currentPrompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt")
                ?? whisperModelManager.whisperPrompt.transcriptionPrompt
            if let context = whisperModelManager.whisperContext {
                await context.setPrompt(currentPrompt)
            }
        }
    }
}

enum AudioFileMetadata {
    static func duration(for url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : 0
    }
}
