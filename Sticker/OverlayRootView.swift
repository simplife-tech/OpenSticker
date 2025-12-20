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

    @State private var draggingID: UUID?
    @State private var isOverDeleteBar = false
    
    private let deleteBarRatio: CGFloat = 0.08
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Delete Bar
                if draggingID != nil {
                    DeleteBarView(active: isOverDeleteBar)
                        .frame(height: geo.size.height * deleteBarRatio)
                        .transition(.opacity)
                }
                
                // Stickers
                ForEach(store.visibleStickers(in: contextController.context)) { sticker in
                    StickerView(
                        sticker: binding(for: sticker),
                        draggingID: $draggingID,
                        isOverDeleteBar: $isOverDeleteBar,
                        deleteBarRatio: deleteBarRatio,
                        screenSize: geo.size,
                        onDelete: deleteSticker
                    )
                }
            }
            .background(Color.clear)
            .onChange(of: draggingID) { oldValue, newValue in
                if newValue == nil {
                    StickerStore.shared.save(StickerStore.shared.stickers)
                }
            }
        }
    }
    
    private func binding(for sticker: Sticker) -> Binding<Sticker> {
        guard let index = store.stickers.firstIndex(where: { $0.id == sticker.id }) else {
            fatalError("Sticker not found")
        }
        return $store.stickers[index]
    }
    
    private func deleteSticker(id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            store.stickers.removeAll { $0.id == id }
        }
    }
}
