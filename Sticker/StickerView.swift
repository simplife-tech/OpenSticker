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
    @State private var dragStartTime: Date?

    var body: some View {
        contentView
            .padding(12)
            .background(.ultraThinMaterial)
            .contentShape(Rectangle())
            .cornerRadius(12)
            .shadow(radius: draggingID == sticker.id ? 10 : 3)
            .position(pixelPosition)
            .gesture(dragGesture)
    }

    // MARK: - 内容渲染

    @ViewBuilder
    private var contentView: some View {
        switch sticker.content {
        case .text(let text):
            Text(text)
                .multilineTextAlignment(.leading)

        case .image(let payload):
            if let nsImage = NSImage(contentsOf: payload.fileURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 240)
            }
        }
    }

    // MARK: - 拖拽

    private var dragGesture: some Gesture {
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
                    handleTap()
                } else if isOverDeleteBar {
                    onDelete(sticker.id)
                }

                dragStartNormalized = nil
                dragStartTime = nil
                draggingID = nil
                isOverDeleteBar = false
            }
    }

    // MARK: - 行为

    private func handleTap() {
        switch sticker.content {
        case .text(let text):
            copyToClipboard(text)
        case .image:
            break // 以后可以做：复制图片
        }
    }

    // MARK: - 位置计算

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
