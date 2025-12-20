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
    
    func toggle(on screen: NSScreen, initialText: String?) {
        if isVisible {
            hide()
        } else {
            show(screen: screen, initialText: initialText)
        }
    }

    private var actions: [ActionItem] = []

    func show(screen: NSScreen, initialText: String?) {
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
        
        let size = panel!.frame.size
        let screenFrame = screen.visibleFrame

        // 居中在当前屏幕
        let origin = CGPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )

        panel?.setFrameOrigin(origin)

        if let hosting = panel?.contentView as? NSHostingView<StickerCommandView> {
            hosting.rootView.viewModel.text = initialText ?? ""
        }

        DispatchQueue.main.async {
            self.panel?.makeKeyAndOrderFront(nil)
        }
        panel?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true
    }

    func hide() {
        isVisible = false
        panel?.orderOut(nil)
    }
    
    private func scopesFromAction(_ action: ActionItem) -> Set<StickerScope> {
        switch action.scope {
        case .global:
            return [.global]

        case .browser:
            return [.browser]

        case .app:
            guard !currentAppBundleId.isEmpty else {
                return []
            }
            return [.app(bundleId: currentAppBundleId)]
        }
    }

    private func createPanel() -> NSPanel {

        let view = StickerCommandView(
            viewModel: viewModel,
            actions: actions,
            onAction: { action, text in
                if text.count <= 0 {
                    return
                }
                let sticker = Sticker(
                    id: UUID(),
                    content: .text(text),
                    scopes: self.scopesFromAction(action),
                    normalizedPosition: getMousePosition()
                )
                StickerStore.shared.add(sticker)
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
