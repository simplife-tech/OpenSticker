//
//  StickerStore.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//


import Foundation
import AppKit

final class StickerStore: ObservableObject {

    static let shared = StickerStore()

    @Published var stickers: [Sticker] = []

    private init() {
        stickers = load()
    }

    private var fileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let dir = base.appendingPathComponent("Sticker", isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }

        return dir.appendingPathComponent("stickers.json")
    }

    private func load() -> [Sticker] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            save(defaultStickers())
            return defaultStickers()
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([Sticker].self, from: data)
        } catch {
            print("❌ Failed to load stickers:", error)
            return defaultStickers()
        }
    }

    func save(_ stickers: [Sticker]) {
        do {
            let data = try JSONEncoder().encode(stickers)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("❌ Failed to save stickers:", error)
        }
    }

    private func defaultStickers() -> [Sticker] {
        [
            Sticker(
                id: UUID(),
                text: "灵感\n桌面贴纸 = 按住即现",
                normalizedPosition: CGPoint(x: 0.55, y: 0.22)
            )
        ]
    }
    
    func addSticker(text: String) {
        let screen = screenAtMouse()

        let mouse = NSEvent.mouseLocation

        let frame = screen.frame

        // 转换为当前屏幕内的 normalized 坐标
        let normalizedX = (mouse.x - frame.minX) / frame.width
        // ⭐️ 翻转 Y 坐标：macOS 坐标系 Y 轴向上，需要转换为向下
        let normalizedY = 1.0 - (mouse.y - frame.minY) / frame.height

        let position = CGPoint(
            x: max(0, min(1, normalizedX)),
            y: max(0, min(1, normalizedY))
        )

        let sticker = Sticker(
            id: UUID(),
            text: text,
            normalizedPosition: position
        )

        stickers.append(sticker)
        save(stickers)
    }


}
