import Cocoa
import SwiftUI
import WebKit

final class OverlayWindowController {
    private final class Surface {
        let panel: OverlayPanel
        var cardFrames: [CGRect] = []
        var resizeRegions: [StickerResizeRegion] = []
        var isDragging = false

        init(panel: OverlayPanel) { self.panel = panel }

        var isResizing: Bool { resizeRegions.contains(where: \.isResizing) }
    }

    private let store: StickerStore
    private let contextController: ContextController
    private let onManageGroups: () -> Void
    private var surfaces: [Surface] = []
    private var mouseTimer: Timer?
    var onGroupShortcutAvailability: ((Bool) -> Void)?

    var isVisible: Bool { !surfaces.isEmpty }

    init(store: StickerStore, contextController: ContextController, onManageGroups: @escaping () -> Void) {
        self.store = store
        self.contextController = contextController
        self.onManageGroups = onManageGroups
    }

    func toggle(on screen: NSScreen) {
        if isVisible { hide() }
        else { show(on: screen) }
    }

    func show(on screen: NSScreen) {
        if isVisible { hide() }
        let displays = NSScreen.screens.map(StickerDisplay.init)
        let preferred = displays.first { $0.id == screen.stickerDisplayID } ?? displays.first
        guard let preferred else { return }

        surfaces = displays.map { makeSurface(for: $0, displays: displays, preferredID: preferred.id) }
        for surface in surfaces {
            surface.panel.orderFrontRegardless()
        }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.updateMouseInteraction()
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
        updateMouseInteraction()
    }

    private func makeSurface(for display: StickerDisplay, displays: [StickerDisplay],
                             preferredID: String) -> Surface {
        let panel = OverlayPanel(contentRect: display.frame,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        let surface = Surface(panel: panel)
        let root = OverlayRootView(
            store: store,
            contextController: contextController,
            display: display,
            displays: displays,
            preferredDisplayID: preferredID,
            onFramesChanged: { [weak self, weak surface] frames in
                surface?.cardFrames = frames
                self?.updateMouseInteraction()
            },
            onResizeRegionsChanged: { [weak self, weak surface] regions in
                surface?.resizeRegions = regions
                self?.updateMouseInteraction()
            },
            onDraggingChanged: { [weak self, weak surface] dragging in
                surface?.isDragging = dragging
                self?.updateMouseInteraction()
            },
            onEdit: { [weak panel] in panel?.makeKey() },
            onManageGroups: { [weak self] in
                guard let self else { return }
                self.hide()
                self.onManageGroups()
            }
        )
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: root)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.setFrame(display.frame, display: false)
        return surface
    }

    func hide() {
        onGroupShortcutAvailability?(false)
        mouseTimer?.invalidate()
        mouseTimer = nil
        let closing = surfaces
        surfaces = []
        if closing.contains(where: { $0.isDragging }) { store.save(store.stickers) }
        store.draggingDisplayID = nil
        for surface in closing { surface.panel.close() }
    }

    private func allowsGroupShortcuts(gestureInProgress: Bool) -> Bool {
        guard isVisible, !store.groups.isEmpty, !gestureInProgress else { return false }
        guard let keyWindow = NSApp.keyWindow else { return true }
        guard surfaces.contains(where: { $0.panel === keyWindow }),
              !(keyWindow.firstResponder is NSTextView) else { return false }
        var view = keyWindow.firstResponder as? NSView
        while let current = view {
            if current is WKWebView { return false }
            view = current.superview
        }
        return true
    }

    private func updateMouseInteraction() {
        guard isVisible else { return }
        let activeSurface = surfaces.first { $0.isDragging || $0.isResizing }
        onGroupShortcutAvailability?(allowsGroupShortcuts(gestureInProgress: activeSurface != nil))
        let mouse = NSEvent.mouseLocation
        for surface in surfaces {
            let panel = surface.panel
            let point = CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)
            let capturesMouse = activeSurface.map { $0 === surface }
                ?? (panel.frame.contains(mouse) && surface.cardFrames.contains { $0.contains(point) })
            if panel.ignoresMouseEvents == capturesMouse {
                panel.ignoresMouseEvents = !capturesMouse
            }
        }
    }
}
