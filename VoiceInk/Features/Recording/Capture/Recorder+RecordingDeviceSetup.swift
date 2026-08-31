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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            audioSetupQueue.async {
                do {
                    try recorder.startRecording(toOutputFile: url, deviceID: deviceID)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func showRecordingDeviceNotification(
        for deviceID: AudioDeviceID,
        resolution: RecordingDeviceResolution
    ) {
        guard let deviceName = deviceManager.availableDevices.first(where: { $0.id == deviceID })?.name else {
            return
        }

        if resolution.fellBackFromClosedInternalMicrophone {
            NotificationManager.shared.showNotification(
                title: String(format: String(localized: "Using: %@"), deviceName),
                type: .info
            )
            return
        }

        let lastDeviceID = UserDefaults.standard.string(forKey: "lastUsedMicrophoneDeviceID")
        guard String(deviceID) != lastDeviceID else { return }
        NotificationManager.shared.showNotification(
            title: String(format: String(localized: "Using: %@"), deviceName),
            type: .info
        )
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

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                audioSetupQueue.async {
                    do {
                        try recorder.switchDevice(to: fallbackDeviceID)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            deviceManager.recordingDeviceChangeFinished(activeDeviceID: fallbackDeviceID)
            UserDefaults.standard.set(
                String(fallbackDeviceID),
                forKey: "lastUsedMicrophoneDeviceID"
            )
            if let deviceName = deviceManager.availableDevices.first(where: { $0.id == fallbackDeviceID })?.name {
                NotificationManager.shared.showNotification(
                    title: String(format: String(localized: "Switched to: %@"), deviceName),
                    type: .info
                )
            }
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
