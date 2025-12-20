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
                StickerImageView(image: nsImage, size: $sticker.imageSize, sticker: $sticker)
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
        case .image(let payload):
            let url = ImageStore.shared.imageURL(for: payload.filename)
            if let image = NSImage(contentsOf: url) {
                copyImageToClipboard(image)
            }
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

struct StickerImageView: View {

    let image: NSImage
    @Binding var size: CGSize
    @Binding var sticker: Sticker

    @State private var startScale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
//                .padding(16)

            // 🔵 缩放手柄
            Circle()
                .fill(Color.white)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(Color.blue, lineWidth: 1)
                )
                .opacity(0.001)
                .padding(0)
                .onHover { hovering in
                    hovering
                    ? NSCursor.openHand.set()
                    : NSCursor.arrow.set()
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newWidth = max(40, sticker.imageSize.width + value.translation.width)
                            let newHeight = max(40, sticker.imageSize.height + value.translation.height)

                            sticker.imageSize = CGSize(width: newWidth, height: newHeight)
                        }
                )
        }
        .background(Color.clear)
    }
}
