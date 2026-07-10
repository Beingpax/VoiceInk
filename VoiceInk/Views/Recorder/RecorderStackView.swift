import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// RecorderStackView(s) — stacked recorder cards for record-while-transcribing.
// ═══════════════════════════════════════════════════════════════════════════════
//
// The engine now holds a COLLECTION of RecordingSession objects (`engine.sessions`), at
// most one of which is actively .recording (the mic owner). The recorder window used to
// host ONE card bound to the engine; it now hosts a STACK container that renders ONE card
// per session.
//
// LAYOUT MODEL (Mini):
//   • The ACTIVE recording session (or, if none is recording, the newest session) sits at
//     the BASE (bottom) — that's the "live" card with full record/stop/cancel/mode controls.
//   • Older in-flight transcribing sessions stack UPWARD above it: each is offset by
//     -cardHeight * indexFromBottom so they appear as a vertical pile growing up off-screen-
//     wards (the panel is bottom-anchored). Each upward card shows just a compact
//     "transcribing…" status + a per-card cancel "X".
//   • As each transcription completes its card animates out (opacity + move) and the stack
//     collapses — driven by SwiftUI's implicit animation on the `sessions` array plus the
//     per-index `.offset(y:)`.
//
// STACK OFFSET MATH (Mini):
//   sessions are ordered oldest→newest. We render so the BASE card is the active/newest one.
//   For a card at array index i (0 = oldest), let N = sessions.count. We want the
//   active/newest card (highest createdAt) at offset 0 and older ones stacked upward.
//   We compute `indexFromBottom` = (N-1 - i) when the newest is the base. Each card is
//   shifted up by `cardSpacing * indexFromBottom`. cardSpacing ≈ control-bar height + gap.
//
// The active/base card uses the FULL MiniRecorderView (with live waveform, controls,
// assistant panel). Background transcribing cards use a slim TranscribingChip to keep
// the pile compact.
//
// NOTE on which card is "base": the spec says the active .recording card is the base and
// transcribing cards stack upward. When NOTHING is recording (all sessions transcribing)
// we keep the NEWEST as the visual base for a stable anchor; controls on it are inert
// (it's not recording) but its TranscribingChip still shows + can be cancelled.

// MARK: - Mini Stack

struct MiniRecorderStackView: View {
    @ObservedObject var engine: VoiceInkEngine
    @ObservedObject var recorder: Recorder
    @ObservedObject var assistantSession: AssistantSession
    let onRecordButtonTapped: () -> Void
    let onCloseTapped: () -> Void
    let onCancelTapped: () -> Void
    let onAssistantFollowUp: (String) -> Void
    // Per-card cancel: cancels THAT specific session (engine.cancelSession(id:)).
    let onCancelSession: (UUID) -> Void

    // Approx vertical advance per stacked card. Matches the mini control-bar height (40)
    // plus a small gap so stacked chips read as a discrete pile, not overlapping.
    private let cardSpacing: CGFloat = 46

    // Sessions oldest→newest as stored by the engine.
    private var ordered: [RecordingSession] { engine.sessions }

    // The base (live) session: the active recording one if present, else the newest.
    private var baseSession: RecordingSession? {
        engine.activeRecordingSession ?? ordered.last
    }

    // Show an assistant-only base card when there are NO sessions left but the assistant is
    // still presenting a response/follow-up. The session that produced the response has
    // already been removed from `sessions` (its pipeline finished), but the AssistantPanelView
    // lives INSIDE MiniRecorderView and must keep rendering. We bind that card to the engine
    // (RecorderStateProvider → reports .idle) which is exactly the old single-card behaviour.
    private var showAssistantOnlyCard: Bool {
        ordered.isEmpty && assistantSession.isVisible
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if showAssistantOnlyCard {
                MiniRecorderView(
                    stateProvider: engine,
                    recorder: recorder,
                    assistantSession: assistantSession,
                    onRecordButtonTapped: onRecordButtonTapped,
                    onCloseTapped: onCloseTapped,
                    onCancelTapped: onCancelTapped,
                    onAssistantFollowUp: onAssistantFollowUp
                )
            }

            ForEach(ordered) { session in
                cardView(for: session)
                    // Each card is shifted UP by its distance from the base. The base card
                    // (indexFromBottom == 0) stays at offset 0; older transcribing cards
                    // climb upward in the bottom-anchored panel.
                    .offset(y: -cardSpacing * CGFloat(indexFromBottom(of: session)))
                    .zIndex(zIndex(for: session))
                    .transition(
                        .move(edge: .bottom).combined(with: .opacity)
                    )
            }
        }
        // Implicit animation keyed on the session id list so add/remove (and the resulting
        // offset shuffles) animate the pile growing/collapsing.
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: engine.sessions.map(\.id))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // Distance of a session from the base, in card units. Base = 0, next-older = 1, etc.
    // We pile by reverse-chronological position relative to the base. Sessions newer than
    // the base (shouldn't normally exist, but be safe) also pile upward.
    private func indexFromBottom(of session: RecordingSession) -> Int {
        guard let baseSession,
              let baseIdx = ordered.firstIndex(where: { $0.id == baseSession.id }),
              let myIdx = ordered.firstIndex(where: { $0.id == session.id }) else {
            return 0
        }
        // Older sessions have a SMALLER array index (oldest first). The base is usually the
        // newest (largest index). Distance upward = baseIdx - myIdx for older cards.
        return max(0, baseIdx - myIdx)
    }

    // Base card on top of the z-order so its controls are tappable; older cards behind.
    private func zIndex(for session: RecordingSession) -> Double {
        Double(ordered.count - indexFromBottom(of: session))
    }

    @ViewBuilder
    private func cardView(for session: RecordingSession) -> some View {
        if session.id == baseSession?.id {
            // BASE/live card — full mini recorder with controls. Bound to the session as
            // its state provider so it shows that session's live state (recording waveform,
            // partial transcript, etc.). Controls route to the engine-level closures.
            MiniRecorderView(
                stateProvider: session,
                recorder: recorder,
                assistantSession: assistantSession,
                onRecordButtonTapped: onRecordButtonTapped,
                onCloseTapped: onCloseTapped,
                onCancelTapped: onCancelTapped,
                onAssistantFollowUp: onAssistantFollowUp
            )
        } else {
            // Background transcribing card — slim chip with per-card cancel.
            TranscribingChip(
                session: session,
                style: .mini,
                onCancel: { onCancelSession(session.id) }
            )
        }
    }
}

// MARK: - Notch Stack

// LAYOUT MODEL (Notch):
//   The notch pill is anchored at the TOP center of the screen. "Upward" stacking makes no
//   sense there, so for the notch the ACTIVE session is the notch pill (full NotchRecorderView)
//   and in-flight transcribing sessions render as small "transcribing…" chips stacked BELOW
//   the pill (newest nearest the pill), animating in/out as they complete. The NotchRecorderPanel
//   window height was extended to fit up to a few stacked chips beneath the pill.
struct NotchRecorderStackView: View {
    @ObservedObject var engine: VoiceInkEngine
    @ObservedObject var recorder: Recorder
    @ObservedObject var assistantSession: AssistantSession
    let onRecordButtonTapped: () -> Void
    let onCloseTapped: () -> Void
    let onCancelTapped: () -> Void
    let onAssistantFollowUp: (String) -> Void
    let onCancelSession: (UUID) -> Void

    private var ordered: [RecordingSession] { engine.sessions }

    // The pill session: active recording one if present, else newest.
    private var pillSession: RecordingSession? {
        engine.activeRecordingSession ?? ordered.last
    }

    // Background (non-pill) in-flight sessions, newest first so the newest chip sits nearest
    // the pill directly beneath it.
    private var backgroundSessions: [RecordingSession] {
        ordered
            .filter { $0.id != pillSession?.id && ($0.phase == .transcribing || $0.phase == .delivering) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // Assistant-only fallback (see the mini stack's equivalent): when the producing session
    // is gone but the assistant is still visible, render the pill bound to the engine so the
    // AssistantPanelView inside NotchRecorderView keeps showing.
    private var showAssistantOnlyPill: Bool {
        pillSession == nil && assistantSession.isVisible
    }

    var body: some View {
        VStack(spacing: 6) {
            // The pill at the top (the notch itself).
            if let pillSession {
                NotchRecorderView(
                    stateProvider: pillSession,
                    recorder: recorder,
                    assistantSession: assistantSession,
                    onRecordButtonTapped: onRecordButtonTapped,
                    onCloseTapped: onCloseTapped,
                    onCancelTapped: onCancelTapped,
                    onAssistantFollowUp: onAssistantFollowUp
                )
            } else if showAssistantOnlyPill {
                NotchRecorderView(
                    stateProvider: engine,
                    recorder: recorder,
                    assistantSession: assistantSession,
                    onRecordButtonTapped: onRecordButtonTapped,
                    onCloseTapped: onCloseTapped,
                    onCancelTapped: onCancelTapped,
                    onAssistantFollowUp: onAssistantFollowUp
                )
            }

            // Stacked transcribing chips beneath the pill, newest nearest the pill.
            ForEach(backgroundSessions) { session in
                TranscribingChip(
                    session: session,
                    style: .notch,
                    onCancel: { onCancelSession(session.id) }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: engine.sessions.map(\.id))
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - Transcribing Chip

// Compact card for a background (non-base/non-pill) session that is transcribing. Shows a
// spinner + label + a per-card cancel "X" that discards THAT session's result. Observes the
// session so its label/spinner reflect its live state (transcribing → enhancing).
struct TranscribingChip: View {
    enum Style { case mini, notch }

    @ObservedObject var session: RecordingSession
    let style: Style
    let onCancel: () -> Void

    private var label: String {
        switch session.liveRecordingState {
        case .enhancing: return String(localized: "Enhancing…")
        default:         return String(localized: "Transcribing…")
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Reuse the existing spinning processing indicator for visual consistency.
            ProcessingIndicator(color: .white.opacity(0.86))
                .frame(width: 14, height: 14)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.82))
                .lineLimit(1)

            // Per-card cancel — discards THIS session only.
            RecorderCancelButton(action: onCancel)
                .scaleEffect(0.82)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(width: style == .mini ? 184 : 200)
        .background(Color.black.opacity(style == .mini ? 1.0 : 0.92))
        .clipShape(RoundedRectangle(cornerRadius: style == .mini ? 16 : 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: style == .mini ? 16 : 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
        )
    }
}
