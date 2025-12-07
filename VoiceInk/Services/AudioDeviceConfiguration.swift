import Foundation
import AVFoundation
import CoreAudio
import os

class AudioDeviceConfiguration {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioDeviceConfiguration")

    // MARK: - Per-App Device Selection (AVAudioEngine)

    // Sets the input device for an AVAudioEngine (per-app, doesn't affect system)
    static func setEngineInputDevice(_ deviceID: AudioDeviceID, for audioEngine: AVAudioEngine) throws {
        let inputNode = audioEngine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            logger.error("Audio unit not available for device configuration")
            throw AudioConfigurationError.audioUnitNotAvailable
        }

        var deviceIDCopy = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDCopy,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            logger.error("Failed to set audio engine input device: \(status)")
            throw AudioConfigurationError.failedToSetInputDevice(status: status)
        }

        logger.info("✅ Set audio engine input device to \(deviceID) - per-app only, no system changes")
    }

    // Gets the current input device for an AVAudioEngine
    static func getEngineInputDevice(for audioEngine: AVAudioEngine) -> AudioDeviceID? {
        let inputNode = audioEngine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            logger.warning("Audio unit not available for querying device")
            return nil
        }

        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            &propertySize
        )

        if status != noErr {
            logger.error("Failed to get audio engine input device: \(status)")
            return nil
        }

        return deviceID
    }
    
    // Creates a device change observer
    static func createDeviceChangeObserver(
        handler: @escaping () -> Void,
        queue: OperationQueue = .main
    ) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AudioDeviceChanged"),
            object: nil,
            queue: queue,
            using: { _ in handler() }
        )
    }
}

enum AudioConfigurationError: LocalizedError {
    case failedToSetInputDevice(status: OSStatus)
    case audioUnitNotAvailable

    var errorDescription: String? {
        switch self {
        case .failedToSetInputDevice(let status):
            return "Failed to set input device: \(status)"
        case .audioUnitNotAvailable:
            return "Audio unit not available for device configuration"
        }
    }
} 