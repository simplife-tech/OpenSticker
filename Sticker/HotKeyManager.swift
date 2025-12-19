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

    /// 防止 keyDown 连续触发
    private var isPressed = false

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onOptionN: (() -> Void)?

    func start() {
        print("🔐 AXIsProcessTrusted =", AXIsProcessTrusted())

        let mask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue)

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

                // 按下 Option + Tab
                if isOptionDown && isTabKey && type == .keyDown {
                    if !manager.isPressed {
                        manager.isPressed = true
                        manager.onKeyDown?()
                    }
                    return nil
                }

                // 松开（Option 或 Tab 任意一个）
                if manager.isPressed {
                    let optionReleased =
                        type == .flagsChanged && !isOptionDown
                    let tabReleased =
                        type == .keyUp && isTabKey

                    if optionReleased || tabReleased {
                        manager.isPressed = false
                        manager.onKeyUp?()
                    }
                    
                    if isTabKey || type == .flagsChanged {
                        return nil
                    }
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

