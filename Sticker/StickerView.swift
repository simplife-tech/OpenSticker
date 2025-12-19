//
//  StickerView.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//


import SwiftUI

struct StickerView: View {

    @Binding var sticker: Sticker
    @Binding var draggingID: UUID?
    @Binding var isOverDeleteBar: Bool

    let deleteBarRatio: CGFloat  
    let screenSize: CGSize
    
    var onDelete: (UUID) -> Void

    @State private var dragStartNormalized: CGPoint?
    @State private var dragStartTime: Date?  // ⭐️ 记录拖动开始时间

    var body: some View {
        Text(sticker.text)
            .padding(12)
            .background(.ultraThinMaterial)
            .contentShape(Rectangle())
            .cornerRadius(12)
            .shadow(radius: draggingID == sticker.id ? 10 : 3)
            .position(pixelPosition)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartNormalized == nil {
                            dragStartNormalized = sticker.normalizedPosition
                            dragStartTime = Date()
                            draggingID = sticker.id
                        }

                        guard let start = dragStartNormalized else { return }

                        let dx = value.translation.width / screenSize.width
                        let dy = value.translation.height / screenSize.height

                        sticker.normalizedPosition = CGPoint(
                            x: clamp(start.x + dx),
                            y: clamp(start.y + dy)
                        )

                        isOverDeleteBar = sticker.normalizedPosition.y < deleteBarRatio
                    }
                    .onEnded { value in
                        let duration = Date().timeIntervalSince(dragStartTime ?? Date())
                        let distance = hypot(value.translation.width, value.translation.height)
                        
                        if duration < 0.3 && distance < 10 {
                            copyToClipboard(sticker.text)
                        } else {
                            if isOverDeleteBar {
                                onDelete(sticker.id)
                            }
                        }

                        dragStartNormalized = nil
                        dragStartTime = nil
                        draggingID = nil
                        isOverDeleteBar = false
                    }
            )
    }

    private var pixelPosition: CGPoint {
        CGPoint(
            x: sticker.normalizedPosition.x * screenSize.width,
            y: sticker.normalizedPosition.y * screenSize.height
        )
    }

    private func clamp(_ v: CGFloat) -> CGFloat {
        min(max(v, 0), 1)
    }
}
