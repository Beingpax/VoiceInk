import Foundation
import SwiftUI
import os

// ═══════════════════════════════════════════════════════════════════════════════
// RecordingSession — one in-flight "voice capture → transcription → paste" job.
// ═══════════════════════════════════════════════════════════════════════════════
//
// VoiceInkEngine used to be SINGLE-FLIGHT — exactly one recording lifecycle existed
// at a time, and the STOP press AWAITED the whole transcription pipeline INLINE on
// the MainActor before the mic could be used again. That inline await is what blocked
// the user from starting a new dictation while the previous one was still uploading /
// transcribing.
//
// We now model each capture as an independent RecordingSession object. The engine owns
// a COLLECTION of these (`@Published var sessions`). The mic (the single shared
// `Recorder`) is only ever owned by the ONE session that is currently `.recording`;
// every other session in the collection has already stopped capturing and is somewhere
// in the transcription pipeline. So the user can stop session A (mic frees instantly),
// start session B, and A keeps transcribing in the background on a serial queue.
//
// ── SESSION STATE MACHINE ──────────────────────────────────────────────────────
//
//        ┌───────────┐  stop press / key-up   ┌──────────────┐
//        │ .recording│ ─────────────────────► │ .transcribing│
//        └───────────┘  (mic released here)   └──────────────┘
//              ▲                                      │
//   start press│                                      │ transcription returns text,
//   (new sess) │                                      │ enhancement runs (if enabled)
//              │                                      ▼
//        (engine creates                       ┌──────────────┐
//         a fresh session)                     │  .delivering │  paste / respond / cmd
//                                              └──────────────┘
//                                                     │ delivery finished
//                                                     ▼
//                                              ┌──────────────┐
//                                              │    .done     │  → removed from `sessions`
//                                              └──────────────┘     (UI animates it out)
//
//   • .recording    — actively capturing audio. THE mic owner. At most ONE session is
//                     ever in this phase (the one-active-recording invariant below).
//   • .transcribing — audio captured, pipeline running (network upload / whisper /
//                     fluidaudio transcription). Mic already released.
//   • .delivering   — transcription (and optional AI enhancement) done; the result is
//                     being pasted / responded / sent to a custom command. The pipeline
//                     drives the recorder UI state through .enhancing then delivery.
//   • .done         — terminal. The engine removes the session from `sessions`; SwiftUI
//                     animates the card out and the stack collapses.
//
// NOTE: the pipeline internally also surfaces the legacy RecordingState (.transcribing
// / .enhancing) for the per-session status display; Phase here is the coarse lifecycle
// the engine + stack UI key off. We keep both: Phase for collection/stack management,
// the per-session liveRecordingState for the card's spinner/waveform rendering.
//
// ── ONE-ACTIVE-RECORDING INVARIANT (HARD RULE) ─────────────────────────────────
// At most ONE session in `sessions` may have phase == .recording at any time. This is
// enforced at the only two mutation sites:
//   1. VoiceInkEngine.toggleRecord START branch refuses to create a new .recording
//      session if `activeRecordingSession != nil` (defensive assert; the toggle path
//      already guarantees it because a press while one is recording STOPS it instead).
//   2. The STOP branch transitions the active session OUT of .recording (→.transcribing)
//      BEFORE any new session can be created.
// Why it matters: the shared `Recorder` is a single mic owner. Two `.recording` sessions
// would both think they own the mic and fight over start/stop + media pause/resume.
//
// ── ObservableObject ───────────────────────────────────────────────────────────
// Each card in the stacked recorder UI observes ITS OWN session, so phase /
// liveRecordingState / partialTranscript changes redraw only that card. The engine's
// `sessions` array is @Published for add/remove (stack grows/shrinks); the per-session
// @Published members drive each individual card's content.
@MainActor
final class RecordingSession: ObservableObject, Identifiable, RecorderStateProvider {
    enum Phase: Equatable {
        case recording
        case transcribing
        case delivering
        case done
    }

    // Stable identity for SwiftUI ForEach + per-card cancel routing (engine.cancelSession(id:)).
    let id = UUID()

    // Coarse lifecycle phase (drives stack membership / which card is the base). @Published
    // so the owning engine's array observers and this session's card both react.
    @Published var phase: Phase

    // Fine-grained recorder UI state for THIS card (idle/recording/transcribing/enhancing).
    // The pipeline pushes .enhancing here via onStateChange; the card's RecorderStatusDisplay
    // reads it to show the right spinner/waveform. Conforms to RecorderStateProvider so the
    // existing MiniRecorderView / NotchRecorderView can render a single session unchanged.
    @Published var liveRecordingState: RecordingState

    // Live streaming partial (only meaningful while .recording — only the recording session
    // streams partial transcripts from its realtime session).
    @Published var partialTranscript: String = ""

    // The recorded audio file for this session. Set at record-start, consumed by the pipeline.
    var audioURL: URL?

    // Final transcript text once the pipeline completes (kept for potential future use /
    // debugging; delivery already pastes it).
    var transcript: String?

    // ── Per-session bits migrated OFF the old engine singletons ──
    // Previously these were single-flight members on VoiceInkEngine; now each session
    // carries its own so two sessions (one recording, one transcribing) never share state.

    // Streaming/file transcription session prepared at record-start, used by the pipeline.
    var transcriptionSession: TranscriptionSession?
    // Mode-resolved transcription engine settings captured at record-start (so the pipeline
    // uses the config that was active WHEN this recording started, not whatever is active now).
    var transcriptionConfiguration: TranscriptionRuntimeConfiguration?
    // App/window context snapshot store for AI enhancement context.
    var contextStore: RecordingContextSnapshotStore?
    // Background tasks capturing the above context; cancelled when the session ends.
    var contextTasks: [Task<Void, Never>] = []

    // Whether this capture is a brand-new dictation or an assistant follow-up turn. Mirrors
    // the engine's old RecordingUseCase; kept per-session because two sessions could in
    // principle have different use cases.
    enum UseCase: Equatable {
        case newSession
        case assistantFollowUp

        var isAssistantFollowUp: Bool { self == .assistantFollowUp }
    }
    var useCase: UseCase

    // The Transcription model id this session's pipeline runs against. Used as the cancel
    // "poison" key (canceledPipelineTranscriptionIDs) so cancelling THIS session can't
    // discard another session's finished 200.
    var pipelineTranscriptionID: UUID?

    // Identity token for the record-start handshake (the async start path checks this is
    // still the live start before transitioning to .recording — guards against a re-press
    // cancelling a not-yet-started session). Replaces the old engine activeRecordingStartID.
    var startID: UUID

    // Per-session cancel flag. Replaces the old GLOBAL engine `shouldCancelRecording`. The
    // pipeline's shouldCancel() gate reads this for ITS session only, so cancelling session
    // A never poisons session B.
    var shouldCancel: Bool = false

    // Stable creation timestamp for deterministic stack ordering (oldest at the bottom/base
    // in mini; newest nearest the pill in notch). The `sessions` array is also kept in
    // creation order, but createdAt makes the intent explicit + survives any reordering.
    let createdAt: Date

    init(
        phase: Phase = .recording,
        useCase: UseCase = .newSession,
        startID: UUID = UUID()
    ) {
        self.phase = phase
        // A session is born recording, so its live UI state starts at .recording too.
        self.liveRecordingState = (phase == .recording) ? .recording : .idle
        self.useCase = useCase
        self.startID = startID
        self.createdAt = Date()
    }

    // RecorderStateProvider conformance: the card reads `recordingState` for its spinner/
    // waveform. We expose the fine-grained liveRecordingState under that protocol name.
    var recordingState: RecordingState {
        liveRecordingState
    }

    // Cancel + tear down this session's background context capture. Safe to call multiple times.
    func clearContext() {
        contextTasks.forEach { $0.cancel() }
        contextTasks.removeAll()
        contextStore = nil
    }
}
