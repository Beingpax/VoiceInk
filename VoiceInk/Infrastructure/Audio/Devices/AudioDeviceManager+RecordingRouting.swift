import CoreAudio
import Foundation
import os

struct RecordingDeviceResolution {
    let deviceID: AudioDeviceID?
    let internalMicrophoneBlockedByClosedLid: Bool
    let fellBackFromClosedInternalMicrophone: Bool
}

struct RecordingDeviceSession {
    var isActive = false
    var activeDeviceID: AudioDeviceID?
    var isDeviceChangePending = false
}

enum RecordingDeviceChangeReason: Equatable {
    case closedLid
    case deviceUnavailable
}

struct RecordingDeviceChangeRequest {
    let fallbackDeviceID: AudioDeviceID?
    let reason: RecordingDeviceChangeReason
}

extension AudioDeviceManager {
    func setupRecordingDeviceRouting() {
        clamshellStateMonitor = ClamshellStateMonitor { [weak self] isClosed in
            self?.handleClamshellChange(isClosed: isClosed)
        }
    }

    func beginRecordingSetup(deviceID: AudioDeviceID) {
        recordingDeviceSession.isActive = true
        recordingDeviceSession.activeDeviceID = deviceID
    }

    func recordingDidStart(deviceID: AudioDeviceID) {
        recordingDeviceSession.isActive = true
        recordingDeviceSession.activeDeviceID = deviceID
    }

    func recordingDeviceChangeFinished(activeDeviceID: AudioDeviceID? = nil) {
        if let activeDeviceID {
            recordingDeviceSession.activeDeviceID = activeDeviceID
        }
        recordingDeviceSession.isDeviceChangePending = false
    }

    func recordingDidStop() {
        recordingDeviceSession = RecordingDeviceSession()
    }

    func resolveCurrentRecordingDevice(
        excluding excludedDeviceID: AudioDeviceID? = nil
    ) -> RecordingDeviceResolution {
        let preferredCandidates = preferredRecordingDeviceIDs()
        let preferredAvailableDevice = preferredCandidates.first(where: isOperationalInputDevice)
        let internalMicrophoneBlockedByClosedLid = isClamshellClosed
            && preferredAvailableDevice.map(isInternalMicrophone) == true

        var seen = Set<AudioDeviceID>()
        let candidates = (preferredCandidates + fallbackRecordingDeviceIDs()).filter { deviceID in
            guard deviceID != excludedDeviceID else { return false }
            return seen.insert(deviceID).inserted
        }
        let resolvedDeviceID = candidates.first(where: isDeviceUsableForRecording)

        return RecordingDeviceResolution(
            deviceID: resolvedDeviceID,
            internalMicrophoneBlockedByClosedLid: internalMicrophoneBlockedByClosedLid,
            fellBackFromClosedInternalMicrophone: internalMicrophoneBlockedByClosedLid
                && resolvedDeviceID != preferredAvailableDevice
        )
    }

    func getCurrentDevice() -> AudioDeviceID {
        resolveCurrentRecordingDevice().deviceID ?? 0
    }

    func findBestAvailableDevice() -> AudioDeviceID? {
        fallbackRecordingDeviceIDs().first(where: isDeviceUsableForRecording)
    }

    func isDeviceUsableForRecording(_ deviceID: AudioDeviceID) -> Bool {
        isOperationalInputDevice(deviceID)
            && !(isClamshellClosed && isInternalMicrophone(deviceID))
    }

    private func preferredRecordingDeviceIDs() -> [AudioDeviceID] {
        switch inputMode {
        case .systemDefault:
            return getSystemDefaultDevice().map { [$0] } ?? []
        case .custom:
            let savedUID = UserDefaults.standard.selectedAudioDeviceUID ?? ""
            let savedModelUID = UserDefaults.standard.selectedAudioDeviceModelUID
            var candidates = findAvailableDevice(uid: savedUID, modelUID: savedModelUID).map { [$0.id] } ?? []
            if let selectedDeviceID, !candidates.contains(selectedDeviceID) {
                candidates.append(selectedDeviceID)
            }
            return candidates
        case .prioritized:
            return prioritizedDevices.sorted { $0.priority < $1.priority }.compactMap { device in
                findAvailableDevice(uid: device.id, modelUID: device.modelUID)?.id
            }
        }
    }

    private func fallbackRecordingDeviceIDs() -> [AudioDeviceID] {
        let internalMicrophones = availableDevices.filter { isInternalMicrophone($0.id) }.map { $0.id }
        let otherInputs = availableDevices.filter { !isInternalMicrophone($0.id) }.map { $0.id }
        return isClamshellClosed ? otherInputs + internalMicrophones : internalMicrophones + otherInputs
    }

    func isOperationalInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        availableDevices.contains { $0.id == deviceID }
    }

    private func handleClamshellChange(isClosed: Bool) {
        logger.notice("Clamshell state changed: \(isClosed ? "closed" : "open", privacy: .public)")

        guard isRecordingActive else {
            notifyDeviceChange()
            return
        }
        guard isClosed,
            let activeRecordingDeviceID,
            isInternalMicrophone(activeRecordingDeviceID)
        else {
            return
        }

        requestRecordingDeviceChange(reason: .closedLid)
    }

    func requestRecordingDeviceChange(reason: RecordingDeviceChangeReason) {
        guard let activeDeviceID = activeRecordingDeviceID,
            !recordingDeviceSession.isDeviceChangePending
        else {
            return
        }

        recordingDeviceSession.isDeviceChangePending = true
        let request = RecordingDeviceChangeRequest(
            fallbackDeviceID: resolveCurrentRecordingDevice(excluding: activeDeviceID).deviceID,
            reason: reason
        )
        NotificationCenter.default.post(
            name: .recordingDeviceChangeRequired,
            object: request
        )
    }
}
