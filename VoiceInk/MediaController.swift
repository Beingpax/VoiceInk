import Foundation
import CoreAudio

final class MediaController: ObservableObject {

    static let shared = MediaController()

    private enum DuckingMode {
        case none
        case mute
        case volume(savedVolume: Float)
    }

    private var didMuteAudio = false
    private var wasAudioMutedBeforeRecording = false
    private var activeDuckingMode: DuckingMode = .none
    private var unmuteTask: Task<Void, Never>?
    private var muteGeneration: Int = 0

    @Published var isSystemMuteEnabled: Bool = UserDefaults.standard.bool(forKey: "isSystemMuteEnabled") {
        didSet { UserDefaults.standard.set(isSystemMuteEnabled, forKey: "isSystemMuteEnabled") }
    }

    @Published var audioResumptionDelay: Double = UserDefaults.standard.double(forKey: "audioResumptionDelay") {
        didSet { UserDefaults.standard.set(audioResumptionDelay, forKey: "audioResumptionDelay") }
    }

    @Published var audioDuckingPercent: Int = UserDefaults.standard.integer(forKey: "audioDuckingPercent") {
        didSet { UserDefaults.standard.set(audioDuckingPercent, forKey: "audioDuckingPercent") }
    }

    private init() {}

    func muteSystemAudio() async -> Bool {
        guard isSystemMuteEnabled else { return false }

        unmuteTask?.cancel()
        unmuteTask = nil
        muteGeneration += 1

        let percent = max(0, min(100, audioDuckingPercent))

        // Full mute path preserves the original behavior and the macOS
        // volume-slider state. Use volume scalar only for partial ducking.
        if percent >= 100 {
            return await applyFullMute()
        } else if percent > 0 {
            return applyVolumeDucking(percent: percent)
        } else {
            // 0% reduction means "do nothing".
            return false
        }
    }

    private func applyFullMute() async -> Bool {
        let currentlyMuted = isSystemAudioMuted()

        if currentlyMuted {
            if didMuteAudio {
                wasAudioMutedBeforeRecording = false
            } else {
                wasAudioMutedBeforeRecording = true
                didMuteAudio = false
            }
            activeDuckingMode = .mute
            return true
        }

        wasAudioMutedBeforeRecording = false
        let success = setSystemMuted(true)
        didMuteAudio = success
        activeDuckingMode = success ? .mute : .none
        return success
    }

    private func applyVolumeDucking(percent: Int) -> Bool {
        guard let currentVolume = getSystemVolume() else { return false }

        let factor = Float(100 - percent) / 100.0
        let targetVolume = max(0.0, min(1.0, currentVolume * factor))

        guard setSystemVolume(targetVolume) else { return false }

        activeDuckingMode = .volume(savedVolume: currentVolume)
        return true
    }

    func unmuteSystemAudio() async {
        guard isSystemMuteEnabled else { return }

        let delay = audioResumptionDelay
        let mode = activeDuckingMode
        let shouldUnmute = didMuteAudio && !wasAudioMutedBeforeRecording
        let myGeneration = muteGeneration

        let task = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard let self = self else { return }
            guard !Task.isCancelled else { return }
            guard self.muteGeneration == myGeneration else { return }

            switch mode {
            case .mute:
                if shouldUnmute {
                    _ = self.setSystemMuted(false)
                }
            case .volume(let savedVolume):
                _ = self.setSystemVolume(savedVolume)
            case .none:
                break
            }

            self.didMuteAudio = false
            self.activeDuckingMode = .none
        }

        unmuteTask = task
        await task.value
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

        return status == noErr ? deviceID : nil
    }

    private func isSystemAudioMuted() -> Bool {
        guard let deviceID = getDefaultOutputDevice() else { return false }

        var muted: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 0
            if !AudioObjectHasProperty(deviceID, &address) { return false }
        }

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &muted)
        return status == noErr && muted != 0
    }

    private func setSystemMuted(_ muted: Bool) -> Bool {
        guard let deviceID = getDefaultOutputDevice() else { return false }

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

    private func getSystemVolume() -> Float? {
        guard let deviceID = getDefaultOutputDevice() else { return nil }

        var volume: Float = 0
        var propertySize = UInt32(MemoryLayout<Float>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if !AudioObjectHasProperty(deviceID, &address) {
            // Some devices expose volume only on the master channel.
            address.mElement = 0
            if !AudioObjectHasProperty(deviceID, &address) { return nil }
        }

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &volume)
        return status == noErr ? volume : nil
    }

    private func setSystemVolume(_ volume: Float) -> Bool {
        guard let deviceID = getDefaultOutputDevice() else { return false }

        var newValue = max(0.0, min(1.0, volume))
        let propertySize = UInt32(MemoryLayout<Float>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
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

        status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, propertySize, &newValue)
        return status == noErr
    }
}
