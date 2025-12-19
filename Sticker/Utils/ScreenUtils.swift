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

