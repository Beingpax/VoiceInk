import AVFoundation
import Combine
import CoreAudio
import Foundation
import os

@MainActor
class Recorder: NSObject, ObservableObject {
    var recorder: CoreAudioRecorder?
    let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "Recorder")
    let deviceManager = AudioDeviceManager.shared
    private var lifecycleCancellable: AnyCancellable?
    var recordingDeviceChangeObserver: NSObjectProtocol?
    private let mediaController = MediaController.shared
    private let playbackController = PlaybackController.shared
    /// Dedicated serial queue for hardware setup.
    let audioSetupQueue = DispatchQueue(label: "com.prakashjoshipax.voiceink.audioSetup", qos: .userInitiated)
    private let recordingAudioActionDelayNanoseconds: UInt64 = 220_000_000
    private var audioMuteTask: Task<Void, Never>?
    private var mediaPauseTask: Task<Void, Never>?
    private var audioRestorationTask: Task<Void, Never>?
    private let smoothedValuesLock = NSLock()
    private var smoothedAverage: Float = 0
    private var smoothedPeak: Float = 0

    /// Audio chunk callback for streaming. Can be updated while recording;
    /// changes are forwarded to the live CoreAudioRecorder.
    var onAudioChunk: ((_ data: Data) -> Void)? {
        didSet { recorder?.onAudioChunk = onAudioChunk }
    }

    enum RecorderError: Error {
        case couldNotStartRecording
        case noUsableMicrophone(internalMicrophoneBlockedByClosedLid: Bool)
    }

    override init() {
        super.init()
        lifecycleCancellable = LifecycleObserver.shared.publisher(
            for: [.audioDeviceChanged, .systemWillSleep, .systemDidWake]
        ).sink { [weak self] _ in
            Task { @MainActor in
                self?.invalidatePreparedAudioUnit()
            }
        }
        setupRecordingDeviceChangeObserver()
        schedulePrepareForCurrentDevice(reason: "init")
    }

    func startRecording(toOutputFile url: URL) async throws {
        RecordingDiagnostics.shared.mark(
            "recorder-start-entered",
            details: "file=\(url.lastPathComponent) inputMode=\(deviceManager.inputMode.rawValue) selectedDeviceID=\(deviceManager.selectedDeviceID.map(String.init) ?? "none") systemDefaultDeviceID=\(deviceManager.getSystemDefaultDevice().map(String.init) ?? "none") clamshellClosed=\(deviceManager.isClamshellClosed)"
        )
        var resolution = deviceManager.resolveCurrentRecordingDevice()
        guard var deviceID = resolution.deviceID else {
            RecordingDiagnostics.shared.mark(
                "recorder-device-resolution-failed",
                details: "internalMicrophoneBlockedByClosedLid=\(resolution.internalMicrophoneBlockedByClosedLid)"
            )
            onAudioChunk = nil
            throw RecorderError.noUsableMicrophone(
                internalMicrophoneBlockedByClosedLid: resolution.internalMicrophoneBlockedByClosedLid
            )
        }

        let initialDevice = deviceManager.availableDevices.first(where: { $0.id == deviceID })
        RecordingDiagnostics.shared.mark(
            "recorder-device-selected",
            details: "deviceID=\(deviceID) name=\(initialDevice?.name ?? "unknown") uid=\(initialDevice?.uid ?? "unknown") modelUID=\(deviceManager.getDeviceModelUID(deviceID: deviceID) ?? "unknown") fellBackFromClosedInternalMicrophone=\(resolution.fellBackFromClosedInternalMicrophone)"
        )

        deviceManager.beginRecordingSetup(deviceID: deviceID)

        audioRestorationTask?.cancel()
        audioRestorationTask = nil
        pauseMedia()
        muteSystemAudio()

        let coreAudioRecorder = recorder ?? CoreAudioRecorder()
        coreAudioRecorder.onAudioChunk = onAudioChunk
        recorder = coreAudioRecorder

        do {
            do {
                try await startHardwareRecording(coreAudioRecorder, to: url, deviceID: deviceID)
            } catch {
                RecordingDiagnostics.shared.mark(
                    "recorder-initial-device-start-failed",
                    details: "deviceID=\(deviceID) error=\(String(describing: error))"
                )
                let retryResolution = deviceManager.resolveCurrentRecordingDevice(excluding: deviceID)
                guard deviceManager.isClamshellClosed,
                    deviceManager.isInternalMicrophone(deviceID),
                    let fallbackDeviceID = retryResolution.deviceID
                else {
                    throw error
                }

                deviceID = fallbackDeviceID
                resolution = retryResolution
                RecordingDiagnostics.shared.mark(
                    "recorder-fallback-device-selected",
                    details: "deviceID=\(fallbackDeviceID)"
                )
                deviceManager.beginRecordingSetup(deviceID: fallbackDeviceID)
                try await startHardwareRecording(coreAudioRecorder, to: url, deviceID: fallbackDeviceID)
            }

            deviceManager.recordingDidStart(deviceID: deviceID)
            RecordingDiagnostics.shared.mark(
                "recorder-start-completed",
                details: "deviceID=\(deviceID)"
            )
            showRecordingDeviceNotification(for: deviceID, resolution: resolution)
            UserDefaults.standard.set(String(deviceID), forKey: "lastUsedMicrophoneDeviceID")
            resetAudioMeter()
        } catch {
            RecordingDiagnostics.shared.mark(
                "recorder-start-failed",
                details: "deviceID=\(deviceID) error=\(String(describing: error))"
            )
            logger.error(
                "Failed to start recording deviceID=\(deviceID, privacy: .public) file=\(url.lastPathComponent, privacy: .public) error=\(error, privacy: .public)"
            )
            await stopRecording()
            throw RecorderError.couldNotStartRecording
        }
    }

    func stopRecording() async {
        RecordingDiagnostics.shared.mark(
            "recorder-stop-entered",
            details: "coreAudioRecording=\(recorder?.isCurrentlyRecording ?? false)"
        )
        audioMuteTask?.cancel()
        audioMuteTask = nil
        mediaPauseTask?.cancel()
        mediaPauseTask = nil
        // Capture current recorder to stop it on the serial hardware queue.
        let currentRecorder = self.recorder

        await withCheckedContinuation { continuation in
            audioSetupQueue.async {
                RecordingDiagnostics.shared.mark("hardware-stop-queue-began")
                currentRecorder?.stopRecording()
                RecordingDiagnostics.shared.mark("hardware-stop-queue-completed")
                continuation.resume()
            }
        }
        onAudioChunk = nil

        resetAudioMeter()

        audioRestorationTask?.cancel()
        audioRestorationTask = Task {
            await mediaController.unmuteSystemAudio()
            await playbackController.resumeMedia()
        }
        deviceManager.recordingDidStop()
        RecordingDiagnostics.shared.mark("recorder-stop-completed")
    }

    private func muteSystemAudio() {
        RecordingDiagnostics.shared.mark(
            "system-audio-mute-scheduled",
            details: "delayMs=\(Double(recordingAudioActionDelayNanoseconds) / 1_000_000.0) enabled=\(UserDefaults.standard.bool(forKey: "isSystemMuteEnabled"))"
        )
        audioMuteTask?.cancel()
        audioMuteTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.recordingAudioActionDelayNanoseconds)
            guard !Task.isCancelled else { return }
            let result = await self.mediaController.muteSystemAudio()
            RecordingDiagnostics.shared.mark(
                "system-audio-mute-completed",
                details: "result=\(String(describing: result))"
            )
        }
    }

    private func pauseMedia() {
        RecordingDiagnostics.shared.mark(
            "media-pause-scheduled",
            details: "enabled=\(UserDefaults.standard.bool(forKey: "isPauseMediaEnabled"))"
        )
        mediaPauseTask?.cancel()
        mediaPauseTask = Task { [weak self] in
            guard let self else { return }
            await self.playbackController.pauseMedia()
            RecordingDiagnostics.shared.mark("media-pause-call-completed")
        }
    }

    private func schedulePrepareForCurrentDevice(reason: String) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            return
        }

        let deviceID = deviceManager.getCurrentDevice()
        guard deviceID != 0 else {
            recorder?.teardown()
            return
        }

        let coreAudioRecorder = recorder ?? CoreAudioRecorder()
        coreAudioRecorder.onAudioChunk = onAudioChunk
        recorder = coreAudioRecorder

        audioSetupQueue.async { [logger] in
            do {
                try coreAudioRecorder.prepare(deviceID: deviceID)
            } catch {
                logger.warning(
                    "Recorder prepare failed reason=\(reason, privacy: .public) deviceID=\(deviceID, privacy: .public) error=\(error, privacy: .public)"
                )
            }
        }
    }

    private func invalidatePreparedAudioUnit() {
        guard let coreAudioRecorder = recorder else { return }
        audioSetupQueue.async {
            coreAudioRecorder.invalidatePreparation()
        }
    }

    func audioMeterSnapshot() -> AudioMeter {
        guard let recorder else {
            return AudioMeter(averagePower: 0, peakPower: 0)
        }

        // Sample audio levels (thread-safe read)
        let averagePower = recorder.averagePower
        let peakPower = recorder.peakPower

        // Normalize values
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

        // Apply EMA smoothing with thread-safe access
        smoothedValuesLock.lock()
        smoothedAverage = smoothedAverage * 0.6 + normalizedAverage * 0.4
        smoothedPeak = smoothedPeak * 0.6 + normalizedPeak * 0.4
        let audioMeter = AudioMeter(
            averagePower: Double(smoothedAverage),
            peakPower: Double(smoothedPeak)
        )
        smoothedValuesLock.unlock()

        return audioMeter
    }

    private func resetAudioMeter() {
        smoothedValuesLock.lock()
        smoothedAverage = 0
        smoothedPeak = 0
        smoothedValuesLock.unlock()
    }

    // MARK: - Cleanup

    deinit {
        audioMuteTask?.cancel()
        mediaPauseTask?.cancel()
        audioRestorationTask?.cancel()
        if let observer = recordingDeviceChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        recorder?.teardown()
    }
}

struct AudioMeter: Equatable {
    let averagePower: Double
    let peakPower: Double
}
