import Foundation
import SwiftUI
import os

// MARK: - Recorder Manager
/// Manages the lifecycle and presentation of recorder UI
@MainActor
class RecorderManager: ObservableObject {
    @Published var isRecorderVisible = false {
        didSet {
            if isRecorderVisible {
                showRecorder()
            } else {
                hideRecorder()
            }
        }
    }

    @Published var recorderStyle: RecorderStyle {
        didSet {
            // Handle recorder type change while visible
            if isRecorderVisible {
                // Hide old style
                windowManager?.hide()
                windowManager = nil

                // Show new style after brief delay
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    showRecorder()
                }
            }
            // Persist preference
            UserDefaults.standard.set(recorderStyle.rawValue, forKey: "RecorderType")
        }
    }

    private var windowManager: RecorderWindowManager?
    private let whisperState: WhisperState
    private let recorder: Recorder
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "RecorderManager")

    init(whisperState: WhisperState, recorder: Recorder) {
        self.whisperState = whisperState
        self.recorder = recorder

        // Load saved preference
        let savedStyle = UserDefaults.standard.string(forKey: "RecorderType") ?? "mini"
        self.recorderStyle = RecorderStyle(rawValue: savedStyle) ?? .mini
    }

    func showRecorder() {
        logger.notice("📱 Showing \(self.recorderStyle.rawValue) recorder")

        if windowManager == nil {
            windowManager = RecorderWindowManager(
                whisperState: whisperState,
                recorder: recorder,
                style: recorderStyle
            )
        }
        windowManager?.show()
    }

    func hideRecorder() {
        windowManager?.hide()
    }

    func toggleRecorder() {
        isRecorderVisible.toggle()
    }

    /// Clean up resources
    func cleanup() {
        windowManager?.hide()
        windowManager = nil
    }
}
