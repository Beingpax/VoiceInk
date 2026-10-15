//! Decides what a shortcut event means for the current recording state.
//!
//! This is the policy behind toggle / push-to-talk / hybrid recording, kept
//! free of side effects: the application describes its [`Phase`], and gets a
//! [`Decision`] back to carry out.

use super::trigger::{HotkeyEvent, TriggerKind};
use crate::config::HotkeyMode;
use std::time::Duration;

/// What the application is doing when an event arrives.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Phase {
    Idle,
    Recording {
        kind: TriggerKind,
        /// The current key press started this recording (it may end on release).
        started_by_press: bool,
        elapsed: Duration,
    },
    /// Transcribing / enhancing.
    Processing,
}

/// The action to perform.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decision {
    Start(TriggerKind),
    Stop,
    /// A short tap in hybrid mode: keep recording until the next press.
    KeepRecording,
    /// Discard the recording; `audible` plays the cancel sound.
    CancelRecording {
        audible: bool,
    },
    CancelProcessing,
    PasteLast,
    Ignore,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RecordingPolicy {
    pub mode: HotkeyMode,
    /// In hybrid mode, holding longer than this turns a press into push-to-talk.
    pub hold_threshold: Duration,
}

impl RecordingPolicy {
    pub fn decide(&self, phase: Phase, event: HotkeyEvent) -> Decision {
        match (event, phase) {
            (HotkeyEvent::Down(kind), Phase::Idle) => Decision::Start(kind),
            // Either shortcut stops a running recording.
            (HotkeyEvent::Down(_), Phase::Recording { .. }) => Decision::Stop,
            (HotkeyEvent::Up(kind), Phase::Recording { kind: rec, started_by_press: true, elapsed }) if kind == rec => {
                self.on_release(elapsed)
            }
            (HotkeyEvent::Abort(kind), Phase::Recording { kind: rec, started_by_press: true, elapsed })
                if kind == rec && elapsed < self.hold_threshold =>
            {
                Decision::CancelRecording { audible: false }
            }
            (HotkeyEvent::Cancel, Phase::Recording { .. }) => Decision::CancelRecording { audible: true },
            (HotkeyEvent::Cancel, Phase::Processing) => Decision::CancelProcessing,
            (HotkeyEvent::PasteLast, Phase::Idle) => Decision::PasteLast,
            _ => Decision::Ignore,
        }
    }

    fn on_release(&self, elapsed: Duration) -> Decision {
        match self.mode {
            HotkeyMode::PushToTalk => Decision::Stop,
            HotkeyMode::Hybrid if elapsed >= self.hold_threshold => Decision::Stop,
            HotkeyMode::Hybrid | HotkeyMode::Toggle => Decision::KeepRecording,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const D: TriggerKind = TriggerKind::Dictation;
    const C: TriggerKind = TriggerKind::Command;

    fn policy(mode: HotkeyMode) -> RecordingPolicy {
        RecordingPolicy { mode, hold_threshold: Duration::from_millis(500) }
    }

    fn recording(kind: TriggerKind, by_press: bool, ms: u64) -> Phase {
        Phase::Recording { kind, started_by_press: by_press, elapsed: Duration::from_millis(ms) }
    }

    #[test]
    fn press_starts_and_second_press_stops() {
        let p = policy(HotkeyMode::Hybrid);
        assert_eq!(p.decide(Phase::Idle, HotkeyEvent::Down(C)), Decision::Start(C));
        assert_eq!(p.decide(recording(D, false, 3000), HotkeyEvent::Down(C)), Decision::Stop);
        assert_eq!(p.decide(Phase::Processing, HotkeyEvent::Down(D)), Decision::Ignore);
    }

    #[test]
    fn hybrid_tap_keeps_recording_and_hold_stops() {
        let p = policy(HotkeyMode::Hybrid);
        assert_eq!(p.decide(recording(D, true, 200), HotkeyEvent::Up(D)), Decision::KeepRecording);
        assert_eq!(p.decide(recording(D, true, 800), HotkeyEvent::Up(D)), Decision::Stop);
        // The release of the press that stopped the recording is ignored.
        assert_eq!(p.decide(recording(D, false, 800), HotkeyEvent::Up(D)), Decision::Ignore);
        // Releasing the other shortcut doesn't stop this one.
        assert_eq!(p.decide(recording(D, true, 800), HotkeyEvent::Up(C)), Decision::Ignore);
    }

    #[test]
    fn push_to_talk_stops_on_release_and_toggle_never_does() {
        assert_eq!(policy(HotkeyMode::PushToTalk).decide(recording(D, true, 50), HotkeyEvent::Up(D)), Decision::Stop);
        assert_eq!(
            policy(HotkeyMode::Toggle).decide(recording(D, true, 5000), HotkeyEvent::Up(D)),
            Decision::KeepRecording
        );
    }

    #[test]
    fn abort_only_discards_fresh_recordings() {
        let p = policy(HotkeyMode::Hybrid);
        assert_eq!(
            p.decide(recording(D, true, 100), HotkeyEvent::Abort(D)),
            Decision::CancelRecording { audible: false }
        );
        assert_eq!(p.decide(recording(D, true, 900), HotkeyEvent::Abort(D)), Decision::Ignore);
        assert_eq!(p.decide(recording(D, false, 100), HotkeyEvent::Abort(D)), Decision::Ignore);
    }

    #[test]
    fn cancel_and_paste_last_depend_on_phase() {
        let p = policy(HotkeyMode::Hybrid);
        assert_eq!(p.decide(recording(C, false, 1), HotkeyEvent::Cancel), Decision::CancelRecording { audible: true });
        assert_eq!(p.decide(Phase::Processing, HotkeyEvent::Cancel), Decision::CancelProcessing);
        assert_eq!(p.decide(Phase::Idle, HotkeyEvent::Cancel), Decision::Ignore);
        assert_eq!(p.decide(Phase::Idle, HotkeyEvent::PasteLast), Decision::PasteLast);
        assert_eq!(p.decide(Phase::Processing, HotkeyEvent::PasteLast), Decision::Ignore);
    }
}
