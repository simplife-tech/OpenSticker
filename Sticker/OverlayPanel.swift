//
//  OverlayPanel.swift
//  Sticker
//
//  Created by 周屹峰 on 2025/12/21.
//


import AppKit

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
