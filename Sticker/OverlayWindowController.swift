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

    private var presentationID: UUID?
    private var mouseTimer: Timer?
    private var cardFrames: [CGRect] = []
    private var isDragging = false
    private var resizeRegions: [StickerResizeRegion] = []

    func toggle(on screen: NSScreen) {
        if presentationID != nil {
            hide()
            return
        }

        let id = UUID()
        presentationID = id
        contextController.refresh { [weak self] _ in
            guard let self, self.presentationID == id else { return }
            self.show(on: screen)
        }
    }

    private func show(on screen: NSScreen) {
        if window == nil {
            let contentView = OverlayRootView(
                store: store,
                contextController: contextController,
                onFramesChanged: { [weak self] frames in
                    self?.cardFrames = frames
                    self?.updateMouseInteraction()
                },
                onResizeRegionsChanged: { [weak self] regions in
                    guard let self else { return }
                    self.resizeRegions = regions
                    self.updateMouseInteraction()
                },
                onDraggingChanged: { [weak self] dragging in
                    self?.isDragging = dragging
                    self?.updateMouseInteraction()
                },
                onEdit: { [weak self] in self?.window?.makeKey() }
            )

            let hosting = NSHostingView(rootView: contentView)

            let panel = OverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel.isReleasedWhenClosed = false
            panel.contentView = hosting
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.becomesKeyOnlyIfNeeded = true
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.fullScreenAuxiliary]
            panel.hidesOnDeactivate = false

            window = panel
        }

        window?.setFrame(screen.frame, display: false)
        window?.orderFrontRegardless()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.updateMouseInteraction()
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
        updateMouseInteraction()
    }

    func hide() {
        presentationID = nil
        mouseTimer?.invalidate()
        mouseTimer = nil
        window?.close()
        window = nil
        cardFrames = []
        resizeRegions = []
        isDragging = false
    }

    private func updateMouseInteraction() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x - window.frame.minX, y: window.frame.maxY - mouse.y)
        let isOverCard = cardFrames.contains { $0.contains(point) }
        let isResizing = resizeRegions.contains { $0.isResizing }
        let ignoresMouse = !isDragging && !isResizing && !isOverCard
        if window.ignoresMouseEvents != ignoresMouse {
            window.ignoresMouseEvents = ignoresMouse
        }
    }
}
