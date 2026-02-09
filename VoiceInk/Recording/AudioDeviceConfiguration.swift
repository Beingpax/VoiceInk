import Foundation
import AVFoundation
import CoreAudio
import os

/// Audio device configuration queries (does NOT modify system default device)
class AudioDeviceConfiguration {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AudioDeviceConfiguration")

    /// Gets the current system default input device (for reference only)
    static func getDefaultInputDevice() -> AudioDeviceID? {
        var defaultDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &defaultDeviceID
        )
        if status != noErr {
            logger.error("Failed to get current default input device: \(status)")
            return nil
        }
        return defaultDeviceID
    }

    /// Creates a device change observer that calls handler on the specified queue
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