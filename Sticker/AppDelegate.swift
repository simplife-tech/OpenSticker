//
//  AppDelegate.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//

import AppKit
import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!

    private var pluginWindow: NSWindow?
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
        menu.delegate = self
        menu.addItem(menuItem("新建贴纸…", icon: "plus.square", action: #selector(newSticker),
                              key: "n", modifiers: .option))
        menu.addItem(menuItem("显示贴纸", icon: "rectangle.on.rectangle", action: #selector(toggleStickers),
                              key: "\t", modifiers: .option))
        menu.addItem(menuItem("管理贴纸…", icon: "note.text", action: #selector(showStickerLibrary)))
        menu.addItem(.separator())
        menu.addItem(menuItem("插件管理…", icon: "puzzlepiece.extension", action: #selector(managePlugins)))
        menu.addItem(resourceMenuItem())
        menu.addItem(.separator())
        menu.addItem(menuItem("检查更新…", icon: "arrow.down.circle", action: #selector(checkForUpdates)))
        menu.addItem(menuItem("退出 Sticker", icon: "power", action: #selector(NSApplication.terminate(_:)),
                              key: "q", target: NSApp))
        return menu
    }

    private func menuItem(_ title: String, icon: String, action: Selector? = nil,
                          key: String = "", modifiers: NSEvent.ModifierFlags = .command,
                          target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        item.keyEquivalentModifierMask = modifiers
        let image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        image?.isTemplate = true
        item.image = image
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let toggle = menu.items.first(where: { $0.action == #selector(toggleStickers) }) {
            toggle.title = overlay.isVisible ? "隐藏贴纸" : "显示贴纸"
        }
    }

    @objc private func newSticker() {
        PanelController.shared.toggle(on: screenAtMouse(), initialText: nil)
    }

    @objc private func toggleStickers() {
        overlay.toggle(on: screenAtMouse())
    }

    @objc private func checkForUpdates(_ sender: NSMenuItem) {
        guard !UpdateChecker.shared.isChecking else { return }
        sender.title = "正在检查更新…"
        UpdateChecker.shared.check {
            sender.title = "检查更新…"
        }
    }

    @objc private func managePlugins() {
        if pluginWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 690, height: 440),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.title = "插件管理"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 530, height: 320)
            window.contentView = NSHostingView(rootView: StickerPluginManagerView())
            window.center()
            pluginWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        pluginWindow?.makeKeyAndOrderFront(nil)
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
        let item = menuItem("资源文件", icon: "folder")
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
            title: "当前：\(location.rootURL.lastPathComponent)",
            action: nil,
            keyEquivalent: ""
        )
        current.isEnabled = false
        current.toolTip = location.rootURL.path

        submenu.addItem(menuItem("在访达中打开", icon: "folder", action: #selector(openResourceFolder)))
        submenu.addItem(menuItem("重新读取贴纸", icon: "arrow.clockwise", action: #selector(reloadStickers), key: "r"))
        submenu.addItem(.separator())
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
