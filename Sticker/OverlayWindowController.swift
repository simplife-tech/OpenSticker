//
//  OverlayWindowController.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//


import Cocoa
import SwiftUI

final class OverlayWindowController {
    private var window: NSWindow?
    private let store: StickerStore
    
    init(store: StickerStore) {
        self.store = store
    }

    func show(on screen: NSScreen) {
        if window == nil {
            let contentView = OverlayRootView(store: store)

            let hosting = NSHostingView(rootView: contentView)
            let win = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.contentView = hosting
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .screenSaver
            win.ignoresMouseEvents = false
            win.collectionBehavior = [.fullScreenAuxiliary]
            window = win
        }

        window?.setFrame(screen.frame, display: false)
        window?.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }
}
