import Foundation
import AVFoundation
import CoreAudio
import os

@MainActor
class Recorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
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
            
            if let url = currentURL {
                do {
                    try await startRecording(toOutputFile: url)
                } catch {
                    logger.error("❌ Failed to restart recording after device change: \(error.localizedDescription)")
                }
            }
        }
        isReconfiguring = false
    }
    
    private func configureAudioSession(with deviceID: AudioDeviceID) async throws {
        try AudioDeviceConfiguration.setDefaultInputDevice(deviceID)
    }

    private func getDesiredChannelCount() -> Int {
        // Get channel mode from UserDefaults
        guard let modeString = UserDefaults.standard.audioChannelMode,
              let mode = AudioChannelMode(rawValue: modeString) else {
            return 1  // Default to mono
        }

        switch mode {
        case .mono:
            return 1
        case .stereo:
            return 2
        case .deviceMaximum:
            return Int(deviceManager.currentDeviceMaxChannels)
        case .custom:
            let customCount = UserDefaults.standard.audioCustomChannelCount
            // Clamp to device maximum
            let maxChannels = Int(deviceManager.currentDeviceMaxChannels)
            return min(customCount, maxChannels)
        }
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

        let deviceID = deviceManager.getCurrentDevice()
        if deviceID != 0 {
            do {
                try await configureAudioSession(with: deviceID)
            } catch {
                logger.warning("⚠️ Failed to configure audio session for device \(deviceID), attempting to continue: \(error.localizedDescription)")
            }
        }

        let desiredChannels = getDesiredChannelCount()
        logger.info("📼 Recording with \(desiredChannels) channel(s)")

        let recordSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: desiredChannels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        do {
            recorder = try AVAudioRecorder(url: url, settings: recordSettings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            
            if recorder?.record() == false {
                logger.error("❌ Could not start recording")
                throw RecorderError.couldNotStartRecording
            }
            
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
            logger.error("Failed to create audio recorder: \(error.localizedDescription)")
            stopRecording()
            throw RecorderError.couldNotStartRecording
        }
    }
    
    func stopRecording() {
        audioLevelCheckTask?.cancel()
        audioMeterUpdateTask?.cancel()
        recorder?.stop()
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

        let channelCount = Int(recorder.numberOfChannels)
        let minVisibleDb: Float = -60.0
        let maxVisibleDb: Float = 0.0

        var channelMeters: [AudioMeter.ChannelMeter] = []

        for channelIndex in 0..<channelCount {
            let averagePower = recorder.averagePower(forChannel: channelIndex)
            let peakPower = recorder.peakPower(forChannel: channelIndex)

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

            channelMeters.append(AudioMeter.ChannelMeter(
                averagePower: Double(normalizedAverage),
                peakPower: Double(normalizedPeak)
            ))
        }

        let newAudioMeter = AudioMeter(channels: channelMeters)

        if !hasDetectedAudioInCurrentSession && newAudioMeter.averagePower > 0.01 {
            hasDetectedAudioInCurrentSession = true
        }

        audioMeter = newAudioMeter
    }
    
    // MARK: - AVAudioRecorderDelegate
    
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
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
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
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
    let channels: [ChannelMeter]

    struct ChannelMeter: Equatable {
        let averagePower: Double
        let peakPower: Double
    }

    // Convenience initializer for backward compatibility (mono)
    init(averagePower: Double, peakPower: Double) {
        self.averagePower = averagePower
        self.peakPower = peakPower
        self.channels = [ChannelMeter(averagePower: averagePower, peakPower: peakPower)]
    }

    // Multi-channel initializer
    init(channels: [ChannelMeter]) {
        self.channels = channels
        // Use first channel for backward compatibility, or average if multiple
        if channels.count == 1 {
            self.averagePower = channels[0].averagePower
            self.peakPower = channels[0].peakPower
        } else if channels.count > 1 {
            self.averagePower = channels.map { $0.averagePower }.reduce(0, +) / Double(channels.count)
            self.peakPower = channels.map { $0.peakPower }.max() ?? 0
        } else {
            self.averagePower = 0
            self.peakPower = 0
        }
    }
}