import CoreAudio
import Foundation
import os

extension Recorder {
    func setupRecordingDeviceChangeObserver() {
        recordingDeviceChangeObserver = NotificationCenter.default.addObserver(
            forName: .recordingDeviceChangeRequired,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task {
                await self?.handleRecordingDeviceChange(notification)
            }
        }
    }

    func startHardwareRecording(
        _ recorder: CoreAudioRecorder,
        to url: URL,
        deviceID: AudioDeviceID
    ) async throws {
        let selectedChannels = deviceManager.selectedInputChannels(for: deviceID)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            audioSetupQueue.async {
                do {
                    try recorder.startRecording(
                        toOutputFile: url, deviceID: deviceID, selectedInputChannels: selectedChannels
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func showRecordingDeviceNotification(
        for deviceID: AudioDeviceID,
        isDeviceSwitch: Bool = false
    ) {
        guard let device = deviceManager.availableDevices.first(where: { $0.id == deviceID }) else {
            return
        }

        // Core Audio object IDs can change on reconnect, or be reused for another input.
        // Compare the stable UID for every route, including closed-lid fallbacks.
        let lastDeviceUID = UserDefaults.standard.string(forKey: "lastUsedMicrophoneDeviceUID")
        guard device.uid != lastDeviceUID else { return }

        recordingDeviceNotificationTask?.cancel()
        // Let the caller finish recording startup before constructing the notification window.
        recordingDeviceNotificationTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled,
                self.deviceManager.isRecordingActive,
                self.deviceManager.activeRecordingDeviceID == deviceID
            else { return }

            let title = isDeviceSwitch ? String(localized: "Switched to: %@") : String(localized: "Using: %@")
            NotificationManager.shared.showNotification(
                title: String(format: title, device.name),
                type: .info
            )
            UserDefaults.standard.set(device.uid, forKey: "lastUsedMicrophoneDeviceUID")
            self.recordingDeviceNotificationTask = nil
        }
    }

    private func handleRecordingDeviceChange(_ notification: Notification) async {
        guard let request = notification.object as? RecordingDeviceChangeRequest else { return }
        guard let fallbackDeviceID = request.fallbackDeviceID else {
            deviceManager.recordingDeviceChangeFinished()
            showNoFallbackNotification(reason: request.reason)
            return
        }
        guard let recorder else {
            deviceManager.recordingDeviceChangeFinished()
            return
        }
        let selectedChannels = deviceManager.selectedInputChannels(for: fallbackDeviceID)

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                audioSetupQueue.async {
                    do {
                        try recorder.switchDevice(to: fallbackDeviceID, selectedInputChannels: selectedChannels)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            deviceManager.recordingDeviceChangeFinished(activeDeviceID: fallbackDeviceID)
            showRecordingDeviceNotification(for: fallbackDeviceID, isDeviceSwitch: true)
        } catch {
            deviceManager.recordingDeviceChangeFinished()
            logger.error("Failed to switch recording devices: \(error, privacy: .public)")
            NotificationManager.shared.showNotification(
                title: String(localized: "VoiceInk could not switch to another microphone."),
                type: .error,
                duration: 7.0
            )
        }
    }

    private func showNoFallbackNotification(reason: RecordingDeviceChangeReason) {
        let presentation = AudioInputFailurePresentation.noUsableMicrophone(
            internalMicrophoneBlockedByClosedLid: reason == .closedLid
        )
        NotificationManager.shared.showNotification(
            title: presentation.title,
            type: .error,
            duration: 7.0,
            actionButton: (presentation.actionLabel, presentation.action)
        )
    }

}
