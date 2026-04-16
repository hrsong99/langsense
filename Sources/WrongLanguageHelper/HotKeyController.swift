import Carbon
import Foundation

final class HotKeyController {
    private static var handlerInstalled = false
    private static var handlers: [UInt32: () -> Void] = [:]

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let callback: () -> Void
    private let hotKeyIDValue: UInt32
    private var hotKeyRef: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.callback = callback
        self.hotKeyIDValue = UInt32.random(in: 10_000...999_999)
    }

    func register() {
        Self.installHandlerIfNeeded()
        Self.handlers[hotKeyIDValue] = callback

        var hotKeyID = EventHotKeyID(signature: OSType(0x574C484B), id: hotKeyIDValue)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        Self.handlers.removeValue(forKey: hotKeyIDValue)
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return noErr }
            Self.handlers[hotKeyID.id]?()
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
