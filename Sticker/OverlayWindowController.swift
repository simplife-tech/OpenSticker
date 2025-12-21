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
    private let contextController: ContextController

    
    init(store: StickerStore, contextController: ContextController) {
        self.store = store
        self.contextController = contextController
    }

    func show(on screen: NSScreen) {
        if window == nil {
            let contentView = OverlayRootView(
                store: store,
                contextController: contextController
            )

            let hosting = NSHostingView(rootView: contentView)

            let panel = OverlayPanel(
                contentRect: screen.frame,
                styleMask: [
                    .borderless,
                    .nonactivatingPanel   // ⭐ 生死线
                ],
                backing: .buffered,
                defer: false
            )

            panel.contentView = hosting
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .screenSaver   // 你现在这个层级 OK
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.fullScreenAuxiliary]
            panel.hidesOnDeactivate = false

            window = panel
        }

        window?.setFrame(screen.frame, display: false)
        window?.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }
}
