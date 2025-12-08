import Foundation
import AVFoundation
import CoreAudio
import os

@MainActor
class Recorder: NSObject, ObservableObject, AudioEngineRecorderDelegate {
    private let audioEngine = AVAudioEngine()
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
        isReconfiguring = true

        if recorder != nil {
            let currentURL = recorder?.url

            stopRecording()
            audioEngine.reset()

            let deviceID = deviceManager.getCurrentDevice()

            guard deviceID != 0 else {
                await NotificationManager.shared.showNotification(
                    title: "Recording stopped - no audio input available",
                    type: .error
                )
                isReconfiguring = false
                return
            }

            if let deviceName = deviceManager.getDeviceName(deviceID: deviceID) {
                await NotificationManager.shared.showNotification(
                    title: "Switched to \(deviceName)",
                    type: .info
                )
            }

            if let url = currentURL {
                do {
                    try await startRecording(toOutputFile: url)
                } catch {
                    logger.error("Failed to restart recording: \(error.localizedDescription)")
                    await NotificationManager.shared.showNotification(
                        title: "Could not resume recording",
                        type: .error
                    )
                }
            }
        }

        isReconfiguring = false
    }
    
    func startRecording(toOutputFile url: URL) async throws {
        deviceManager.isRecordingActive = true

        let currentDeviceID = deviceManager.getCurrentDevice()
        let lastDeviceID = UserDefaults.standard.string(forKey: "lastUsedMicrophoneDeviceID")

        if String(currentDeviceID) != lastDeviceID {
            if let deviceName = deviceManager.availableDevices.first(where: { $0.id == currentDeviceID })?.name {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: "Using: \(deviceName)",
                        type: .info
                    )
                }
            }
        }
        UserDefaults.standard.set(String(currentDeviceID), forKey: "lastUsedMicrophoneDeviceID")

        hasDetectedAudioInCurrentSession = false

        if currentDeviceID != 0 {
            do {
                try AudioDeviceConfiguration.setEngineInputDevice(currentDeviceID, for: audioEngine)
            } catch {
                logger.warning("⚠️ Failed to set audio engine device \(currentDeviceID): \(error.localizedDescription)")
            }
        }

        guard currentDeviceID != 0 else {
            logger.error("Cannot start recording: no audio input device available")
            deviceManager.isRecordingActive = false
            throw RecorderError.couldNotStartRecording
        }

        do {
            recorder = AudioEngineRecorder(audioEngine: audioEngine)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true

            try recorder?.prepare(deviceID: currentDeviceID)
            try recorder?.startRecording(toOutputFile: url)

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
                    try? await Task.sleep(nanoseconds: 33_000_000)
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
            logger.error("Failed to start audio engine recording: \(error.localizedDescription)")
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

        Task {
            await mediaController.unmuteSystemAudio()
            try? await Task.sleep(nanoseconds: 100_000_000)
            await playbackController.resumeMedia()
        }
        deviceManager.isRecordingActive = false
    }

    private func updateAudioMeter() {
        guard let recorder = recorder else { return }
        recorder.updateMeters()
        
        let averagePower = recorder.averagePower(forChannel: 0)
        let peakPower = recorder.peakPower(forChannel: 0)
        
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
    
    // MARK: - AudioEngineRecorderDelegate

    nonisolated func audioEngineRecorderDidFinishRecording(_ recorder: AudioEngineRecorder, successfully flag: Bool) {
        if !flag {
            logger.error("❌ Recording finished unsuccessfully - file may be corrupted or empty")
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: "Recording failed - audio file corrupted",
                    type: .error
                )
            }
        }
    }

    nonisolated func audioEngineRecorderEncodeErrorDidOccur(_ recorder: AudioEngineRecorder, error: Error?) {
        if let error = error {
            logger.error("❌ Recording encode error during session: \(error.localizedDescription)")
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: "Recording error: \(error.localizedDescription)",
                    type: .error
                )
            }
        }
    }
    
    deinit {
        audioLevelCheckTask?.cancel()
        audioMeterUpdateTask?.cancel()
        if let observer = deviceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

struct AudioMeter: Equatable {
    let averagePower: Double
    let peakPower: Double
}