//
//  HotKeyManager.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//

import Cocoa

final class HotKeyManager {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onToggleOverlay: (() -> Void)?
    var onOptionN: (() -> Void)?

    func start() {
        print("🔐 AXIsProcessTrusted =", AXIsProcessTrusted())

        let mask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in

                let manager = Unmanaged<HotKeyManager>
                    .fromOpaque(userInfo!)
                    .takeUnretainedValue()

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags

                let isOptionDown = flags.contains(.maskAlternate)
                let isTabKey = keyCode == 48   // Tab
                let isNKey = keyCode == 45 //N
                
                if isOptionDown && isNKey && type == .keyDown {
                    manager.onOptionN?()
                    return nil
                }

                if isOptionDown && isTabKey {
                    if type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                        manager.onToggleOverlay?()
                    }
                    return nil
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: UnsafeMutableRawPointer(
                Unmanaged.passUnretained(self).toOpaque()
            )
        )

        guard let eventTap else {
            print("❌ EventTap 创建失败（检查辅助功能权限）")
            return
        }
        
        print("✅ EventTap 已创建")

        runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        )

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            runLoopSource,
            .commonModes
        )

        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    deinit {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
    }
}

