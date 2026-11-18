//
//  AppDelegate.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//

import AppKit
import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    private var libraryWindow: NSWindow?

    let hotKey = HotKeyManager()
    let store = StickerStore.shared
    let contextController = ContextController()
    lazy var overlay = OverlayWindowController(store: store, contextController: contextController)

    private let location = StickerResourceLocation.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        
        hotKey.onToggleOverlay = {
            self.overlay.toggle(on: screenAtMouse())
        }

        hotKey.onOptionN = {
            DispatchQueue.main.async {
                PanelController.shared.toggle(on: screenAtMouse(), initialText: nil)
            }
        }

        hotKey.start()

        // 不显示 Dock 图标
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(named: "StatusIcon")
        statusItem.menu = buildMenu()
    }
    
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let library = NSMenuItem(title: "管理贴纸…", action: #selector(showStickerLibrary), keyEquivalent: "")
        library.target = self
        menu.addItem(library)
        menu.addItem(.separator())
        menu.addItem(resourceMenuItem())
        menu.addItem(.separator())
        menu.addItem(reloadItem())
        menu.addItem(openFolderItem())
        menu.addItem(.separator())
        menu.addItem(quitItem())

        return menu
    }
    
    @objc private func showStickerLibrary() {
        if libraryWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "贴纸管理"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 540, height: 360)
            window.contentView = NSHostingView(rootView: StickerLibraryView(store: store))
            window.center()
            libraryWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        libraryWindow?.makeKeyAndOrderFront(nil)
    }

    private func resourceMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "📂 资源位置", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let useDefault = NSMenuItem(
            title: "使用默认位置",
            action: #selector(useDefaultLocation),
            keyEquivalent: ""
        )
        useDefault.state = isUsingDefault() ? .on : .off

        let chooseOther = NSMenuItem(
            title: "选择其他文件夹…",
            action: #selector(chooseCustomLocation),
            keyEquivalent: ""
        )

        let current = NSMenuItem(
            title: "当前：\(location.rootURL)",
            action: nil,
            keyEquivalent: ""
        )
        current.isEnabled = false

        submenu.addItem(useDefault)
        submenu.addItem(chooseOther)
        submenu.addItem(.separator())
        submenu.addItem(current)

        item.submenu = submenu
        return item
    }

    private func isUsingDefault() -> Bool {
        location.rootURL == StickerResourceLocation.defaultURL()
    }

    // MARK: - Menu Actions

    @objc private func useDefaultLocation() {
        location.useDefault()
        storeReload()
        refreshMenu()
    }

    @objc private func chooseCustomLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择资源文件夹"

        if panel.runModal() == .OK, let url = panel.url {
            location.useCustom(url: url)
            storeReload()
            refreshMenu()
        }
    }

    @objc private func reloadStickers() {
        storeReload()
    }

    @objc private func openResourceFolder() {
        NSWorkspace.shared.open(location.rootURL)
    }

    private func reloadItem() -> NSMenuItem {
        NSMenuItem(
            title: "重载贴纸",
            action: #selector(reloadStickers),
            keyEquivalent: "r"
        )
    }

    private func openFolderItem() -> NSMenuItem {
        NSMenuItem(
            title: "打开资源文件夹",
            action: #selector(openResourceFolder),
            keyEquivalent: ""
        )
    }

    private func quitItem() -> NSMenuItem {
        NSMenuItem(
            title: "退出",
            action: #selector(NSApp.terminate(_:)),
            keyEquivalent: "q"
        )
    }

    private func storeReload() {
        StickerStore.shared.refreshAll()	
    }

    private func refreshMenu() {
        statusItem.menu = buildMenu()
    }
    
    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = """
    Sticker 需要辅助功能权限才能监听快捷键和显示贴纸。
    请在系统设置中开启后，重新启动应用。
    """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "退出")

        let result = alert.runModal()

        switch result {
        case .alertFirstButtonReturn:
            openAccessibilitySettings()
            NSApp.terminate(nil)

        default:
            NSApp.terminate(nil)
        }
    }

}
