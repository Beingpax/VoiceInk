import CoreAudio
import Foundation

@MainActor
final class MediaController: ObservableObject {

    static let shared = MediaController()

    // Keep responsibility across rapid recordings, including output-device changes.
    private var mutedDevices: Set<AudioDeviceID> = []
    private var recordingSessionID = UUID()

    @Published var isSystemMuteEnabled: Bool = UserDefaults.standard.bool(forKey: "isSystemMuteEnabled") {
        didSet { UserDefaults.standard.set(isSystemMuteEnabled, forKey: "isSystemMuteEnabled") }
    }

    @Published var audioResumptionDelay: Double = UserDefaults.standard.double(forKey: "audioResumptionDelay") {
        didSet { UserDefaults.standard.set(audioResumptionDelay, forKey: "audioResumptionDelay") }
    }

    private init() {}

    func beginRecordingSession(sessionID: UUID) {
        // Invalidate delayed restoration before the recorder's 220 ms mute delay.
        recordingSessionID = sessionID
    }

    func muteSystemAudio(sessionID: UUID) -> Bool {
        guard sessionID == recordingSessionID, !Task.isCancelled, isSystemMuteEnabled else { return false }
        guard let deviceID = getDefaultOutputDevice(),
            let currentlyMuted = isSystemAudioMuted(deviceID: deviceID) else {
            return false
        }
        // A device already muted by the user is never added to our ownership.
        guard !currentlyMuted else { return true }
        guard setSystemMuted(true, deviceID: deviceID) else {
            return false
        }
        mutedDevices.insert(deviceID)
        return true
    }

    func unmuteSystemAudio(sessionID: UUID) async {
        guard sessionID == recordingSessionID, !Task.isCancelled, !mutedDevices.isEmpty else { return }
        let delay = audioResumptionDelay
        if delay > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
        }
        guard sessionID == recordingSessionID, !Task.isCancelled else { return }

        // Restore the devices we actually muted, rather than the current default.
        // Restore ownership even if the preference was disabled during recording.
        for deviceID in Array(mutedDevices) {
            if setSystemMuted(false, deviceID: deviceID) {
                mutedDevices.remove(deviceID)
            }
        }
    }

    private func getDefaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    private func isSystemAudioMuted(deviceID: AudioDeviceID) -> Bool? {
        var muted: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 0
            if !AudioObjectHasProperty(deviceID, &address) { return nil }
        }

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &muted)
        return status == noErr ? muted != 0 : nil
    }

    private func setSystemMuted(_ muted: Bool, deviceID: AudioDeviceID) -> Bool {
        var muteValue: UInt32 = muted ? 1 : 0
        let propertySize = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 0
            if !AudioObjectHasProperty(deviceID, &address) { return false }
        }

        var isSettable: DarwinBoolean = false
        var status = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        if status != noErr || !isSettable.boolValue { return false }

        status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, propertySize, &muteValue)
        return status == noErr
    }
}
