import Cocoa
import Carbon

final class HotKeyManager {
    var onToggleOverlay: (() -> Void)?
    var onOptionN: (() -> Void)?
    private var handler: EventHandlerRef?
    private var keys: [EventHotKeyRef] = []

    func start() {
        guard handler == nil else { return }
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                              EventParamType(typeEventHotKeyID), nil,
                                              MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard result == noErr else { return result }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
                if id.id == 1 { manager.onToggleOverlay?() }
                if id.id == 2 { manager.onOptionN?() }
                return noErr
            },
            1,
            [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))],
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard status == noErr else { return }
        for (id, code) in [(UInt32(1), UInt32(kVK_Tab)), (UInt32(2), UInt32(kVK_ANSI_N))] {
            var key: EventHotKeyRef?
            let result = RegisterEventHotKey(code, UInt32(optionKey),
                                             EventHotKeyID(signature: 0x53544B52, id: id),
                                             GetApplicationEventTarget(), 0, &key)
            if result == noErr, let key { keys.append(key) }
        }
    }

    deinit {
        for key in keys { UnregisterEventHotKey(key) }
        if let handler { RemoveEventHandler(handler) }
    }
}
