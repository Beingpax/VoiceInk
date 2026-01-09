import Foundation
import os

class AudioDeviceConfiguration {
    /// Creates a device change observer
    /// - Parameters:
    ///   - handler: The closure to execute when device changes
    ///   - queue: The queue to execute the handler on (defaults to main queue)
    /// - Returns: The observer token
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
