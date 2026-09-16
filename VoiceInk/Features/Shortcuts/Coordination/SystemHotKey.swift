import Carbon
import Foundation
import os

final class SystemHotKey {
    private static let signature: OSType = 0x56496E6B
    private static var nextID: UInt32 = 0
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SystemHotKey")

    private let id: EventHotKeyID
    private let onChange: (Bool, TimeInterval) -> Void
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?

    init?(keyCode: UInt16, modifiers: UInt32, onChange: @escaping (Bool, TimeInterval) -> Void) {
        precondition(Thread.isMainThread)
        Self.nextID += 1
        id = EventHotKeyID(signature: Self.signature, id: Self.nextID)
        self.onChange = onChange

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                return Unmanaged<SystemHotKey>.fromOpaque(context).takeUnretainedValue().handle(event)
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard handlerStatus == noErr else {
            Self.logger.error("Failed to install system hot key handler: \(handlerStatus)")
            return nil
        }

        let status = RegisterEventHotKey(
            UInt32(keyCode), modifiers, id, GetApplicationEventTarget(), 0, &hotKey
        )
        guard status == noErr else {
            Self.logger.error("Failed to register system hot key: \(status)")
            return nil
        }
    }

    deinit {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let handler {
            RemoveEventHandler(handler)
        }
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var eventID = EventHotKeyID()
        let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &eventID
        )
        guard status == noErr, eventID.signature == id.signature, eventID.id == id.id else {
            return OSStatus(eventNotHandledErr)
        }

        onChange(GetEventKind(event) == UInt32(kEventHotKeyPressed), GetEventTime(event))
        return noErr
    }
}
