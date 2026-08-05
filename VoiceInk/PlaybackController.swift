import AppKit
import Combine
import Foundation
import MediaRemoteAdapter
import SwiftUI
import os

class PlaybackController: ObservableObject {
    static let shared = PlaybackController()
    private var mediaController: MediaRemoteAdapter.MediaController
    private var wasPlayingWhenRecordingStarted = false
    private var isMediaPlaying = false
    private var lastKnownTrackInfo: TrackInfo?
    private var originalMediaAppBundleId: String?
    private var resumeTask: Task<Void, Never>?

    /// MediaRemote intermittently emits a full track event with no client identity
    /// (bundleIdentifier/applicationName/PID all absent) while still reporting
    /// isPlaying. Tracking the id separately keeps those events from erasing which
    /// app we are controlling.
    private var lastKnownBundleId: String?

    private var listenerRestartAttempts = 0
    private static let maxListenerRestartAttempts = 5

    /// Bumped whenever a pause or resume starts, so an in-flight pause retry loop
    /// can tell that it has been superseded and stop.
    private var pauseGeneration = 0

    /// Verification window after each pause attempt. The last one is longer on
    /// purpose: by then every attempt has already been sent, so the extra time does
    /// not make the pause more likely to land – it stops us reporting failure for a
    /// command that was about to take effect.
    private static let pauseConfirmationDelays: [UInt64] = [300_000_000, 300_000_000, 400_000_000]
    private static var maxPauseAttempts: Int { pauseConfirmationDelays.count }

    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink", category: "PlaybackController")

    @Published var isPauseMediaEnabled: Bool = UserDefaults.standard.bool(forKey: "isPauseMediaEnabled") {
        didSet {
            UserDefaults.standard.set(isPauseMediaEnabled, forKey: "isPauseMediaEnabled")

            if isPauseMediaEnabled {
                startMediaTracking()
            } else {
                stopMediaTracking()
            }
        }
    }

    private init() {
        mediaController = MediaRemoteAdapter.MediaController()

        setupMediaControllerCallbacks()

        if isPauseMediaEnabled {
            startMediaTracking()
        }
    }

    private func setupMediaControllerCallbacks() {
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            guard let self = self else { return }
            self.listenerRestartAttempts = 0
            self.isMediaPlaying = trackInfo?.payload.isPlaying ?? false
            self.lastKnownTrackInfo = trackInfo

            if trackInfo == nil {
                // Nothing is playing at all – forget the app we were tracking.
                self.lastKnownBundleId = nil
            } else if let bundleId = trackInfo?.payload.bundleIdentifier {
                self.lastKnownBundleId = bundleId
            }
            // else: identity-less event, keep the previously known bundle id.
        }

        mediaController.onListenerTerminated = { [weak self] in
            self?.handleListenerTermination()
        }
    }

    /// The listener is a child process. If it dies nothing else restarts it, and the
    /// feature goes silently dead until the app is relaunched.
    private func handleListenerTermination() {
        guard isPauseMediaEnabled else { return }

        listenerRestartAttempts += 1
        guard listenerRestartAttempts <= Self.maxListenerRestartAttempts else {
            logger.error("Media listener terminated; restart limit reached, giving up")
            return
        }

        let attempt = listenerRestartAttempts
        logger.warning("Media listener terminated; restarting (attempt \(attempt, privacy: .public))")

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt)) { [weak self] in
            guard let self = self, self.isPauseMediaEnabled else { return }
            self.mediaController.startListening()
        }
    }

    private func startMediaTracking() {
        listenerRestartAttempts = 0
        mediaController.startListening()
    }

    private func stopMediaTracking() {
        mediaController.stopListening()
        isMediaPlaying = false
        lastKnownTrackInfo = nil
        lastKnownBundleId = nil
        listenerRestartAttempts = 0
        wasPlayingWhenRecordingStarted = false
        originalMediaAppBundleId = nil
    }

    func pauseMedia() async {
        resumeTask?.cancel()
        resumeTask = nil
        pauseGeneration += 1
        let generation = pauseGeneration

        wasPlayingWhenRecordingStarted = false
        originalMediaAppBundleId = nil

        guard isPauseMediaEnabled else { return }

        // The pause command targets whatever macOS reports as Now Playing, so a known
        // bundle id is not required to issue it – only to verify the app on resume.
        guard isMediaPlaying, lastKnownTrackInfo?.payload.isPlaying == true else {
            logger.notice(
                "pauseMedia: nothing to pause (isMediaPlaying=\(self.isMediaPlaying, privacy: .public), lastKnownIsPlaying=\(String(describing: self.lastKnownTrackInfo?.payload.isPlaying), privacy: .public))"
            )
            return
        }

        wasPlayingWhenRecordingStarted = true
        originalMediaAppBundleId = lastKnownBundleId

        logger.notice("pauseMedia: pausing \(self.lastKnownBundleId ?? "unknown app", privacy: .public)")

        try? await Task.sleep(nanoseconds: 50_000_000)
        guard !Task.isCancelled, pauseGeneration == generation else { return }

        // MediaRemote reports success for a command it merely dispatched, not one the
        // player acted on, and the first command after an idle gap is routinely
        // dropped. So confirm the player actually stopped and re-issue if it did not.
        // `pause` is idempotent (unlike the play/pause toggle used to resume), so a
        // redundant retry is harmless.
        for attempt in 1...Self.maxPauseAttempts {
            mediaController.pause()

            try? await Task.sleep(nanoseconds: Self.pauseConfirmationDelays[attempt - 1])

            // A resume (or another recording) started while we were retrying – stop,
            // otherwise we would pause playback the user has already resumed.
            guard pauseGeneration == generation else {
                logger.notice("pauseMedia: superseded, abandoning retry")
                return
            }

            if lastKnownTrackInfo?.payload.isPlaying != true {
                if attempt > 1 {
                    logger.notice("pauseMedia: took \(attempt, privacy: .public) attempts to land")
                }
                return
            }

            logger.warning("pauseMedia: still playing after attempt \(attempt, privacy: .public)")
        }

        logger.error("pauseMedia: gave up after \(Self.maxPauseAttempts, privacy: .public) attempts")
    }

    func resumeMedia() async {
        // Supersede any pause retry still in flight, so a late retry cannot pause
        // playback again after we have decided to resume it.
        pauseGeneration += 1

        let shouldResume = wasPlayingWhenRecordingStarted
        let originalBundleId = originalMediaAppBundleId
        let delay = MediaController.shared.audioResumptionDelay

        defer {
            wasPlayingWhenRecordingStarted = false
            originalMediaAppBundleId = nil
        }

        guard isPauseMediaEnabled, shouldResume else { return }

        // If the app was identified when we paused, verify it is still the one we
        // would be resuming. If MediaRemote never told us who it was, fall back to
        // "we paused it and it is still paused" rather than silently doing nothing.
        if let bundleId = originalBundleId {
            guard isAppStillRunning(bundleId: bundleId) else {
                logger.notice("resumeMedia: \(bundleId, privacy: .public) is no longer running")
                return
            }

            if let currentBundleId = lastKnownBundleId, currentBundleId != bundleId {
                logger.notice(
                    "resumeMedia: now playing app changed (\(bundleId, privacy: .public) -> \(currentBundleId, privacy: .public))"
                )
                return
            }
        }

        guard lastKnownTrackInfo?.payload.isPlaying == false else {
            logger.notice("resumeMedia: media is not paused, nothing to resume")
            return
        }

        logger.notice("resumeMedia: resuming \(originalBundleId ?? "unknown app", privacy: .public)")

        let task = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            if Task.isCancelled {
                return
            }

            Self.sendMediaPlayPauseKey()
        }

        resumeTask = task
        await task.value
    }

    /// Simulate the hardware media Play/Pause key (NX_KEYTYPE_PLAY = 16).
    /// Some apps (e.g. Plexamp) ignore the MediaRemote `play` command but
    /// respond to the same HID key event the physical F8 key produces.
    private static func sendMediaPlayPauseKey() {
        func post(down: Bool) {
            let flags: UInt = down ? 0xa00 : 0xb00
            let data1 = Int((16 << 16) | ((down ? 0xa : 0xb) << 8))
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }

    private func isAppStillRunning(bundleId: String) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == bundleId }
    }
}
