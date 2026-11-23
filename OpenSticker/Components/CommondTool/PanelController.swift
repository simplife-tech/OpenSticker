import AppKit
import SwiftUI

final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()
    private let viewModel = StickerCommandViewModel()
    private var panel: NSPanel?
    private(set) var isVisible = false
    private var creationScreen: NSScreen?
    var onStickerCreated: ((NSScreen) -> Void)?

    func toggle(on screen: NSScreen, initialText: String?) {
        if isVisible { hide() }
        else { show(screen: screen, initialText: initialText) }
    }

    func show(screen: NSScreen, initialText: String?) {
        creationScreen = screen
        viewModel.groupID = StickerStore.shared.activeGroupID
        let view = StickerCommandView(viewModel: viewModel, onCreate: { [weak self] in
            self?.create()
        }, onClose: { [weak self] in self?.hide() })
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = ComposerPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = hosting
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - size.width / 2,
                                     y: screen.visibleFrame.midY - size.height / 2))
        self.panel = panel
        isVisible = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        isVisible = false
        panel?.close()
        panel = nil
    }

    private func create() {
        let plugin = StickerPluginRegistry.shared.plugins.first { $0.id == viewModel.pluginID }
        guard plugin != nil || !viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let state = plugin.map { StickerPluginState(pluginID: $0.id, values: viewModel.pluginValues) }
        let store = StickerStore.shared
        let sticker = Sticker(id: UUID(), content: .text(plugin?.name ?? viewModel.text), scopes: [.global],
                              displayID: creationScreen?.stickerDisplayID,
                              groupID: store.validGroupID(viewModel.groupID),
                              plugin: state,
                              paperColor: viewModel.color,
                              textSize: plugin == nil ? nil : CGSize(width: 280, height: 350),
                              normalizedPosition: CGPoint(x: 0.5, y: 0.5))
        do {
            try store.add(sticker)
        } catch {
            NSApp.presentError(error)
            return
        }
        store.selectGroup(sticker.groupID)
        viewModel.text = ""
        viewModel.pluginID = ""
        viewModel.pluginValues = [:]
        hide()
        if let screen = creationScreen {
            onStickerCreated?(screen)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Keep the draft panel alive while interacting with its color menu.
    }
}


private final class ComposerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
