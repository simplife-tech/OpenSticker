//
//  OverlayRootView.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//


import SwiftUI

struct OverlayRootView: View {
    @ObservedObject var store: StickerStore
    @ObservedObject var contextController: ContextController

    let onFramesChanged: ([CGRect]) -> Void
    let onResizeRegionsChanged: ([StickerResizeRegion]) -> Void
    let onDraggingChanged: (Bool) -> Void
    let onEdit: () -> Void

    @State private var draggingID: UUID?
    @State private var isOverDeleteBar = false
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        GeometryReader { geo in
            let targetWidth = min(300, max(0, geo.size.width - 32))
            let target = CGRect(x: (geo.size.width - targetWidth) / 2, y: 14,
                                width: targetWidth, height: 48)
            ZStack(alignment: .top) {
                if draggingID != nil {
                    DeleteBarView(active: isOverDeleteBar)
                        .frame(width: target.width, height: target.height)
                        .position(x: target.midX, y: target.midY)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                // Stickers
                ForEach(store.stickers) { sticker in
                    StickerView(
                        sticker: binding(for: sticker),
                        draggingID: $draggingID,
                        isOverDeleteBar: $isOverDeleteBar,
                        deleteTarget: target,
                        screenSize: geo.size,
                        onDelete: deleteSticker,
                        onEdit: onEdit,
                        onSaveText: { text in
                            guard let current = store.stickers.first(where: { $0.id == sticker.id }) else {
                                throw CocoaError(.fileNoSuchFile)
                            }
                            try store.edit(sticker.id, content: .text(text), scopes: current.scopes)
                        }
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: draggingID != nil)
            .coordinateSpace(name: "stickerOverlay")
            .onPreferenceChange(StickerFramePreference.self, perform: onFramesChanged)
            .onPreferenceChange(StickerResizeRegionPreference.self, perform: onResizeRegionsChanged)
            .background(Color.clear)
            .onChange(of: draggingID) { oldValue, newValue in
                onDraggingChanged(newValue != nil)
                if newValue == nil {
                    StickerStore.shared.save(StickerStore.shared.stickers)
                }
            }
        }
    }
    
    private func binding(for sticker: Sticker) -> Binding<Sticker> {
        // SwiftUI can still read an outgoing card while its removal animates.
        Binding(
            get: { store.stickers.first(where: { $0.id == sticker.id }) ?? sticker },
            set: { updated in
                guard let index = store.stickers.firstIndex(where: { $0.id == sticker.id }) else { return }
                store.stickers[index] = updated
            }
        )
    }
    
    private func deleteSticker(id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            store.remove(id)
        }
    }
}


struct StickerFramePreference: PreferenceKey {
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}


struct StickerResizeRegion: Equatable {
    let frame: CGRect
    let isResizing: Bool
}

struct StickerResizeRegionPreference: PreferenceKey {
    static let defaultValue: [StickerResizeRegion] = []

    static func reduce(value: inout [StickerResizeRegion], nextValue: () -> [StickerResizeRegion]) {
        value.append(contentsOf: nextValue())
    }
}
