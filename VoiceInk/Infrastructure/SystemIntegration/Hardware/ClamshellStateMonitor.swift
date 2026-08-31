import Foundation
import IOKit
import os

final class ClamshellStateMonitor {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ClamshellStateMonitor")
    private let onChange: (Bool) -> Void

    private var rootDomain: io_registry_entry_t = 0
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    private(set) var isClosed = false

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        startMonitoring()
    }

    private func startMonitoring() {
        rootDomain = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard rootDomain != 0 else {
            logger.warning("Unable to access IOPMrootDomain")
            return
        }

        refresh(notify: false)

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            logger.warning("Unable to create clamshell notification port")
            return
        }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)

        let status = IOServiceAddInterestNotification(
            port,
            rootDomain,
            kIOGeneralInterest,
            { userData, _, _, _ in
                guard let userData else { return }
                let monitor = Unmanaged<ClamshellStateMonitor>.fromOpaque(userData).takeUnretainedValue()
                monitor.refresh(notify: true)
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &notifier
        )

        if status != kIOReturnSuccess {
            logger.error("Failed to monitor clamshell state: \(status, privacy: .public)")
        }
    }

    private func refresh(notify: Bool) {
        guard rootDomain != 0,
            let value = IORegistryEntryCreateCFProperty(
                rootDomain,
                "AppleClamshellState" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? Bool,
            value != isClosed
        else {
            return
        }

        isClosed = value
        if notify {
            onChange(value)
        }
    }

    deinit {
        if notifier != 0 {
            IOObjectRelease(notifier)
        }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
        }
        if rootDomain != 0 {
            IOObjectRelease(rootDomain)
        }
    }
}
