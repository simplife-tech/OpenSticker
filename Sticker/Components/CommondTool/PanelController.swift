//
//  PanelController.swift
//  Sticker
//
//  Created by 周屹峰 on 2025/12/20.
//

import AppKit
import SwiftUI

final class PanelController: NSObject, NSWindowDelegate {

    static let shared = PanelController()

    private let viewModel = StickerCommandViewModel()
    private var panel: NSPanel?
    private var currentAppBundleId = ""
    private var currentAppName = ""
    
    private(set) var isVisible = false
    
    func toggle(initialText: String?) {
        if isVisible {
            hide()
        } else {
            show(initialText: initialText)
        }
    }

    private var actions: [ActionItem] = []

    func show(initialText: String?) {
        if let info = getCurrentAppInfo() {
            currentAppBundleId = info.bundleId
            currentAppName = info.name
        }
        
        actions = [
            .init(title: "添加到 全局", subtitle: "所有应用可用", scope: .global),
            .init(title: "添加到 浏览器", subtitle: "Chrome / Safari", scope: .browser),
            .init(title: "添加到 当前应用", subtitle: "仅当前 App(\(currentAppName) \(currentAppBundleId))", scope: .app)
        ]
        
        panel = createPanel()

        if let hosting = panel?.contentView as? NSHostingView<StickerCommandView> {
            hosting.rootView.viewModel.text = initialText ?? ""
        }

        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        panel?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    private func createPanel() -> NSPanel {

        let view = StickerCommandView(
            viewModel: viewModel,
            actions: actions,
            onAction: { action, text in
                print("保存贴纸：\(text)，scope=\(action.scope)")
            },
            onClose: { self.hide() }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 520, height: 230)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hosting
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        return panel
    }
    
    func windowDidResignKey(_ notification: Notification) {
        // 点空白 / 切应用 / 点别的窗口
        hide()
    }
}
