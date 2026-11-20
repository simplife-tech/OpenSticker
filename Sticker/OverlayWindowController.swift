//
//  OverlayWindowController.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//


import Cocoa
import SwiftUI
import WebKit

final class OverlayWindowController {
    private var window: NSWindow?
    private let store: StickerStore
    private let contextController: ContextController
    var onGroupShortcutAvailability: ((Bool) -> Void)?
    private let onManageGroups: () -> Void

    
    init(store: StickerStore, contextController: ContextController, onManageGroups: @escaping () -> Void) {
        self.store = store
        self.contextController = contextController
        self.onManageGroups = onManageGroups
    }

    private var presentationID: UUID?
    var isVisible: Bool { presentationID != nil }
    private var mouseTimer: Timer?
    private var cardFrames: [CGRect] = []
    private var isDragging = false
    private var resizeRegions: [StickerResizeRegion] = []

    func toggle(on screen: NSScreen) {
        if presentationID != nil {
            hide()
            return
        }

        presentationID = UUID()
        show(on: screen)
    }

    func show(on screen: NSScreen) {
        if presentationID == nil { presentationID = UUID() }
        mouseTimer?.invalidate()
        let topInset = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY)
        if window == nil {
            let contentView = OverlayRootView(
                store: store,
                contextController: contextController,
                topInset: topInset,
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
                onEdit: { [weak self] in self?.window?.makeKey() },
                onManageGroups: { [weak self] in
                    guard let self else { return }
                    self.hide()
                    self.onManageGroups()
                }
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

        if let hosting = window?.contentView as? NSHostingView<OverlayRootView>,
           hosting.rootView.topInset != topInset {
            hosting.rootView.topInset = topInset
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
        onGroupShortcutAvailability?(false)
        presentationID = nil
        mouseTimer?.invalidate()
        mouseTimer = nil
        window?.close()
        window = nil
        cardFrames = []
        resizeRegions = []
        isDragging = false
    }

    private func allowsGroupShortcuts(in window: NSWindow) -> Bool {
        guard window.isVisible, !store.groups.isEmpty, !isDragging,
              !resizeRegions.contains(where: \.isResizing) else { return false }
        if let keyWindow = NSApp.keyWindow, keyWindow !== window { return false }
        if window.isKeyWindow {
            if window.firstResponder is NSTextView { return false }
            var view = window.firstResponder as? NSView
            while let current = view {
                if current is WKWebView { return false }
                view = current.superview
            }
        }
        return true
    }

    private func updateMouseInteraction() {
        guard let window else { return }
        onGroupShortcutAvailability?(allowsGroupShortcuts(in: window))
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
