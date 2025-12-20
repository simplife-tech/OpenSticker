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
