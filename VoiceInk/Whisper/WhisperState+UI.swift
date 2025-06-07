import Foundation
import SwiftUI
import os

// MARK: - UI Management Extension
extension WhisperState {
    
    // MARK: - Recorder Panel Management
    
    func showRecorderPanel() {
        logger.notice("📱 Showing \(self.recorderType) recorder")
        if recorderType == "notch" {
            if notchWindowManager == nil {
                notchWindowManager = NotchWindowManager(whisperState: self, recorder: recorder)
                logger.info("Created new notch window manager")
            }
            notchWindowManager?.show()
        } else {
            if miniWindowManager == nil {
                miniWindowManager = MiniWindowManager(whisperState: self, recorder: recorder)
                logger.info("Created new mini window manager")
            }
            miniWindowManager?.show()
        }
    }
    
    func hideRecorderPanel() {
        if recorderType == "notch" {
            notchWindowManager?.hide()
        } else {
            miniWindowManager?.hide()
        }
    }
    
    // MARK: - Mini Recorder Management
    
    func toggleMiniRecorder() async {
        if isMiniRecorderVisible {
            if isRecording {
                await toggleRecord()
            } else {
                await cancelRecording()
            }
        } else {
            SoundManager.shared.playStartSound()

            await toggleRecord()

            await MainActor.run {
                isMiniRecorderVisible = true // This will call showRecorderPanel() via didSet
            }
        }
    }
    
    func dismissMiniRecorder() async {
        logger.notice("📱 Dismissing \(self.recorderType) recorder")
        
       
        
        shouldCancelRecording = true

        
        
        if isRecording {
            await recorder.stopRecording()
        }

         // Hide recorder panel first before doing anything else
        hideRecorderPanel()
        
        await MainActor.run {
            isRecording = false
            isVisualizerActive = false
            isProcessing = false
            isTranscribing = false
            canTranscribe = true
            isMiniRecorderVisible = false
        }


        
        try? await Task.sleep(nanoseconds: 150_000_000)
        await cleanupModelResources()
    }
    
    func cancelRecording() async {
        SoundManager.shared.playEscSound()
        shouldCancelRecording = true
        await dismissMiniRecorder()
    }
    
    // MARK: - Notification Handling
    
    func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleToggleMiniRecorder), name: .toggleMiniRecorder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePromptChange), name: .promptDidChange, object: nil)
    }
    
    @objc public func handleToggleMiniRecorder() {
        Task {
            await toggleMiniRecorder()
        }
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