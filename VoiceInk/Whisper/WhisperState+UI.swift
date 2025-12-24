import Foundation
import SwiftUI
import os

// MARK: - UI Management Extension
extension WhisperState {

    // MARK: - Recorder Management

    func toggleRecorder() async {
        if isRecorderVisible {
            if recordingState == .recording {
                await toggleRecord()
            } else {
                await cancelRecording()
            }
        } else {
            SoundManager.shared.playStartSound()

            await MainActor.run {
                isRecorderVisible = true
            }

            await toggleRecord()
        }
    }

    func dismissRecorder() async {
        if recordingState == .busy { return }

        let wasRecording = recordingState == .recording
 
        await MainActor.run {
            self.recordingState = .busy
        }
        
        if wasRecording {
            await recorder.stopRecording()
        }

        await MainActor.run {
            recorderManager?.hideRecorder()
        }

        // Clear captured context when the recorder is dismissed
        if let enhancementService = enhancementService {
            await MainActor.run {
                enhancementService.clearCapturedContexts()
            }
        }
        
        await MainActor.run {
            isRecorderVisible = false
        }

        await cleanupModelResources()
        
        if UserDefaults.standard.bool(forKey: PowerModeDefaults.autoRestoreKey) {
            await PowerModeSessionManager.shared.endSession()
            await MainActor.run {
                PowerModeManager.shared.setActiveConfiguration(nil)
            }
        }
        
        await MainActor.run {
            recordingState = .idle
        }
    }
    
    func resetOnLaunch() async {
        logger.notice("🔄 Resetting recording state on launch")
        await recorder.stopRecording()
        await MainActor.run {
            recorderManager?.hideRecorder()
            isRecorderVisible = false
            shouldCancelRecording = false
            miniRecorderError = nil
            recordingState = .idle
        }
        await cleanupModelResources()
    }

    func cancelRecording() async {
        SoundManager.shared.playEscSound()
        shouldCancelRecording = true
        await dismissRecorder()
    }
    
    // MARK: - Notification Handling
    
    func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleToggleRecorder), name: .toggleRecorder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDismissRecorder), name: .dismissRecorder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLicenseStatusChanged), name: .licenseStatusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePromptChange), name: .promptDidChange, object: nil)
    }

    @objc public func handleToggleRecorder() {
        Task {
            await toggleRecorder()
        }
    }

    @objc public func handleDismissRecorder() {
        Task {
            await dismissRecorder()
        }
    }
    
    @objc func handleLicenseStatusChanged() {
        self.licenseViewModel = LicenseViewModel()
    }
    
    @objc func handlePromptChange() {
        // Update the whisper context with the new prompt
        Task {
            await updateContextPrompt()
        }
    }
    
    private func updateContextPrompt() async {
        // Always reload the prompt from UserDefaults to ensure we have the latest
        let currentPrompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? whisperPrompt.transcriptionPrompt
        
        if let context = whisperContext {
            await context.setPrompt(currentPrompt)
        }
    }
} 
