//
//  AppDelegate.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//

import AppKit
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    let hotKey = HotKeyManager()
    let store = StickerStore.shared
    lazy var overlay = OverlayWindowController(store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        
        hotKey.onKeyDown = {
            let screen = screenAtMouse()
            self.overlay.show(on: screen)
        }

        hotKey.onKeyUp = {
            self.overlay.hide()
            // 这里保存 stickers 位置即可
        }
        
        hotKey.onOptionN = {
            if let text = getSelectedText() {
                self.store.addSticker(text: text)
            }
        }

        hotKey.start()
        // 不显示 Dock 图标
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
//        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(named: "StatusIcon")
        
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu

    }
}
