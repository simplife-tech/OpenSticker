import Cocoa
import Carbon

final class HotKeyManager {
    var onToggleOverlay: (() -> Void)?
    var onStepGroup: ((Int) -> Void)?
    var onOptionN: (() -> Void)?
    private var handler: EventHandlerRef?
    private var keys: [UInt32: EventHotKeyRef] = [:]
    private var groupShortcutsEnabled = false

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
                if id.id == 3 { manager.onStepGroup?(-1) }
                if id.id == 4 { manager.onStepGroup?(1) }
                return noErr
            },
            1,
            [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))],
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard status == noErr else { return }
        register(id: 1, keyCode: kVK_Tab)
        register(id: 2, keyCode: kVK_ANSI_N)
    }

    func setGroupShortcutsEnabled(_ enabled: Bool) {
        guard handler != nil, enabled != groupShortcutsEnabled else { return }
        groupShortcutsEnabled = enabled
        if enabled {
            register(id: 3, keyCode: kVK_UpArrow)
            register(id: 4, keyCode: kVK_DownArrow)
        } else {
            for id: UInt32 in [3, 4] {
                if let key = keys.removeValue(forKey: id) { UnregisterEventHotKey(key) }
            }
        }
    }

    private func register(id: UInt32, keyCode: Int) {
        var key: EventHotKeyRef?
        let result = RegisterEventHotKey(UInt32(keyCode), UInt32(optionKey),
                                         EventHotKeyID(signature: 0x53544B52, id: id),
                                         GetApplicationEventTarget(), 0, &key)
        if result == noErr, let key { keys[id] = key }
    }

    deinit {
        for key in keys.values { UnregisterEventHotKey(key) }
        if let handler { RemoveEventHandler(handler) }
    }
}
