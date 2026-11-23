//
//  ScreenUtils.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//
import AppKit

func screenAtMouse() -> NSScreen {
    let mouse = NSEvent.mouseLocation
    for screen in NSScreen.screens {
        if screen.frame.contains(mouse) {
            return screen
        }
    }
    return NSScreen.main!
}

func pixelPosition(
    normalized: CGPoint,
    screenSize: CGSize
) -> CGPoint {
    CGPoint(
        x: normalized.x * screenSize.width,
        y: normalized.y * screenSize.height
    )
}

func getMousePosition() -> CGPoint {
    let screen = screenAtMouse()

    let mouse = NSEvent.mouseLocation

    let frame = screen.frame

    // 转换为当前屏幕内的 normalized 坐标
    let normalizedX = (mouse.x - frame.minX) / frame.width
    // ⭐️ 翻转 Y 坐标：macOS 坐标系 Y 轴向上，需要转换为向下
    let normalizedY = 1.0 - (mouse.y - frame.minY) / frame.height

    let position = CGPoint(
        x: max(0, min(1, normalizedX)),
        y: max(0, min(1, normalizedY))
    )
    
    return position
}

extension NSScreen {
    var stickerDisplayID: String {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return localizedName
        }
        let id = CGDirectDisplayID(number.uint32Value)
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return String(id)
    }
}

struct StickerDisplay {
    let id: String
    let frame: CGRect
    let topInset: CGFloat

    init(_ screen: NSScreen) {
        id = screen.stickerDisplayID
        frame = screen.frame
        topInset = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY)
    }

    func desktopPoint(for position: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + position.x * frame.width,
                y: frame.maxY - position.y * frame.height)
    }

    func normalizedPosition(for point: CGPoint) -> CGPoint {
        CGPoint(x: min(max((point.x - frame.minX) / frame.width, 0), 1),
                y: min(max((frame.maxY - point.y) / frame.height, 0), 1))
    }
}
