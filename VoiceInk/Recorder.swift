import Foundation
import AVFoundation
import CoreAudio
import os

@MainActor
class Recorder: NSObject, ObservableObject {
    private var recorder: AudioEngineRecorder?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "Recorder")
    private let deviceManager = AudioDeviceManager.shared
    private var deviceObserver: NSObjectProtocol?
    private var isReconfiguring = false
    private let mediaController = MediaController.shared
    private let playbackController = PlaybackController.shared
    @Published var audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
    private var audioLevelCheckTask: Task<Void, Never>?
    private var audioMeterUpdateTask: Task<Void, Never>?
    private var audioRestorationTask: Task<Void, Never>?
    private var hasDetectedAudioInCurrentSession = false
    
    enum RecorderError: Error {
        case couldNotStartRecording
    }
    
    override init() {
        super.init()
        setupDeviceChangeObserver()
    }
    
    private func setupDeviceChangeObserver() {
        deviceObserver = AudioDeviceConfiguration.createDeviceChangeObserver { [weak self] in
            Task {
                await self?.handleDeviceChange()
            }
        }
    }
    
    private func handleDeviceChange() async {
        guard !isReconfiguring else { return }
        guard recorder != nil else { return }
        
        isReconfiguring = true
        
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        await MainActor.run {
            NotificationCenter.default.post(name: .toggleMiniRecorder, object: nil)
        }
        
        isReconfiguring = false
    }
    
    func startRecording(toOutputFile url: URL) async throws {
        deviceManager.isRecordingActive = true

        let deviceID = deviceManager.getCurrentDevice()
        let lastDeviceID = UserDefaults.standard.string(forKey: "lastUsedMicrophoneDeviceID")

        if String(deviceID) != lastDeviceID {
            if let deviceName = deviceManager.availableDevices.first(where: { $0.id == deviceID })?.name {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: "Using: \(deviceName)",
                        type: .info
                    )
                }
            }
        }
        UserDefaults.standard.set(String(deviceID), forKey: "lastUsedMicrophoneDeviceID")

        hasDetectedAudioInCurrentSession = false

        do {
            let engineRecorder = AudioEngineRecorder()
            recorder = engineRecorder

            // Set up error callback to handle runtime recording failures
            engineRecorder.onRecordingError = { [weak self] error in
                Task { @MainActor in
                    await self?.handleRecordingError(error)
                }
            }

            // Pass nil if no device found to fall back to system default
            try engineRecorder.startRecording(toOutputFile: url, deviceID: deviceID != 0 ? deviceID : nil)

            logger.info("✅ AudioEngineRecorder started successfully")

            audioRestorationTask?.cancel()
            audioRestorationTask = nil

            Task { [weak self] in
                guard let self = self else { return }
                await self.playbackController.pauseMedia()
                _ = await self.mediaController.muteSystemAudio()
            }

            audioLevelCheckTask?.cancel()
            audioMeterUpdateTask?.cancel()

            audioMeterUpdateTask = Task {
                while recorder != nil && !Task.isCancelled {
                    updateAudioMeter()
                    try? await Task.sleep(nanoseconds: 17_000_000)
                }
            }

            audioLevelCheckTask = Task {
                let notificationChecks: [TimeInterval] = [5.0, 12.0]

                for delay in notificationChecks {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                    if Task.isCancelled { return }

                    if self.hasDetectedAudioInCurrentSession {
                        return
                    }

                    await MainActor.run {
                        NotificationManager.shared.showNotification(
                            title: "No Audio Detected",
                            type: .warning
                        )
                    }
                }
            }

        } catch {
            logger.error("Failed to create audio recorder: \(error.localizedDescription)")
            stopRecording()
            throw RecorderError.couldNotStartRecording
        }
    }
    
    func stopRecording() {
        audioLevelCheckTask?.cancel()
        audioMeterUpdateTask?.cancel()
        recorder?.stopRecording()
        recorder = nil
        audioMeter = AudioMeter(averagePower: 0, peakPower: 0)

        audioRestorationTask = Task {
            await mediaController.unmuteSystemAudio()
            await playbackController.resumeMedia()
        }
        deviceManager.isRecordingActive = false
    }

    private func handleRecordingError(_ error: Error) async {
        logger.error("❌ Recording error occurred: \(error.localizedDescription)")

        // Stop the recording
        stopRecording()

        // Notify the user about the recording failure
        await MainActor.run {
            NotificationManager.shared.showNotification(
                title: "Recording Failed: \(error.localizedDescription)",
                type: .error
            )
        }
    }

    private func updateAudioMeter() {
        guard let recorder = recorder else { return }

        let averagePower = recorder.currentAveragePower
        let peakPower = recorder.currentPeakPower

        let minVisibleDb: Float = -60.0
        let maxVisibleDb: Float = 0.0

        let normalizedAverage: Float
        if averagePower < minVisibleDb {
            normalizedAverage = 0.0
        } else if averagePower >= maxVisibleDb {
            normalizedAverage = 1.0
        } else {
            normalizedAverage = (averagePower - minVisibleDb) / (maxVisibleDb - minVisibleDb)
        }

        let normalizedPeak: Float
        if peakPower < minVisibleDb {
            normalizedPeak = 0.0
        } else if peakPower >= maxVisibleDb {
            normalizedPeak = 1.0
        } else {
            normalizedPeak = (peakPower - minVisibleDb) / (maxVisibleDb - minVisibleDb)
        }

        let newAudioMeter = AudioMeter(averagePower: Double(normalizedAverage), peakPower: Double(normalizedPeak))

        if !hasDetectedAudioInCurrentSession && newAudioMeter.averagePower > 0.01 {
            hasDetectedAudioInCurrentSession = true
        }

        audioMeter = newAudioMeter
    }
    
    // MARK: - Cleanup

    deinit {
        audioLevelCheckTask?.cancel()
        audioMeterUpdateTask?.cancel()
        audioRestorationTask?.cancel()
        if let observer = deviceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

struct AudioMeter: Equatable {
    let averagePower: Double
    let peakPower: Double
}