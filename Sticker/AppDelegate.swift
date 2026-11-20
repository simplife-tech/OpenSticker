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
    lazy var overlay = OverlayWindowController(store: store, contextController: contextController) { [weak self] in
        self?.showStickerLibrary()
    }

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

        hotKey.onStepGroup = { [weak self] offset in
            guard let self, self.overlay.isVisible else { return }
            self.store.stepGroup(by: offset)
        }
        overlay.onGroupShortcutAvailability = { [weak self] enabled in
            self?.hotKey.setGroupShortcutsEnabled(enabled)
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
        menu.addItem(menuItem(L10n.text("新建贴纸…"), icon: "plus.square", action: #selector(newSticker),
                              key: "n", modifiers: .option))
        menu.addItem(menuItem(L10n.text("显示贴纸"), icon: "rectangle.on.rectangle", action: #selector(toggleStickers),
                              key: "\t", modifiers: .option))
        menu.addItem(menuItem(L10n.text("管理贴纸…"), icon: "note.text", action: #selector(showStickerLibrary)))
        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.text("插件管理…"), icon: "puzzlepiece.extension", action: #selector(managePlugins)))
        menu.addItem(resourceMenuItem())
        menu.addItem(.separator())
        menu.addItem(languageMenuItem())
        menu.addItem(menuItem(L10n.text("检查更新…"), icon: "arrow.down.circle", action: #selector(checkForUpdates)))
        menu.addItem(menuItem(L10n.text("退出 Sticker"), icon: "power", action: #selector(NSApplication.terminate(_:)),
                              key: "q", target: NSApp))
        return menu
    }

    private func languageMenuItem() -> NSMenuItem {
        let item = menuItem(L10n.text("语言"), icon: "globe")
        let submenu = NSMenu()
        for choice in L10n.Choice.allCases {
            let option = NSMenuItem(title: choice.title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = choice.rawValue
            option.state = choice == L10n.shared.choice ? .on : .off
            submenu.addItem(option)
        }
        item.submenu = submenu
        return item
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let choice = L10n.Choice(rawValue: value) else { return }
        L10n.shared.select(choice)
        libraryWindow?.title = L10n.text("贴纸管理")
        pluginWindow?.title = L10n.text("插件管理")
        refreshMenu()
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
            toggle.title = overlay.isVisible ? L10n.text("隐藏贴纸") : L10n.text("显示贴纸")
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
        sender.title = L10n.text("正在检查更新…")
        UpdateChecker.shared.check {
            sender.title = L10n.text("检查更新…")
        }
    }

    @objc private func managePlugins() {
        if pluginWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 690, height: 440),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.title = L10n.text("插件管理")
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 530, height: 320)
            window.contentView = NSHostingView(rootView: StickerPluginManagerView())
            window.center()
            pluginWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        pluginWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showStickerLibrary() {
        if libraryWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.text("贴纸管理")
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
        let item = menuItem(L10n.text("资源文件"), icon: "folder")
        let submenu = NSMenu()

        let useDefault = NSMenuItem(
            title: L10n.text("使用默认位置"),
            action: #selector(useDefaultLocation),
            keyEquivalent: ""
        )
        useDefault.state = isUsingDefault() ? .on : .off

        let chooseOther = NSMenuItem(
            title: L10n.text("选择其他文件夹…"),
            action: #selector(chooseCustomLocation),
            keyEquivalent: ""
        )

        let current = NSMenuItem(
            title: L10n.format("当前：%@", location.rootURL.lastPathComponent),
            action: nil,
            keyEquivalent: ""
        )
        current.isEnabled = false
        current.toolTip = location.rootURL.path

        submenu.addItem(menuItem(L10n.text("在访达中打开"), icon: "folder", action: #selector(openResourceFolder)))
        submenu.addItem(menuItem(L10n.text("重新读取贴纸"), icon: "arrow.clockwise", action: #selector(reloadStickers), key: "r"))
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
        panel.prompt = L10n.text("选择资源文件夹")

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
        alert.messageText = L10n.text("需要辅助功能权限")
        alert.informativeText = """
    Sticker 需要辅助功能权限才能监听快捷键和显示贴纸。
    请在系统设置中开启后，重新启动应用。
    """
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("打开系统设置"))
        alert.addButton(withTitle: L10n.text("退出"))

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
