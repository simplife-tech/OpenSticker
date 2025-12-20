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
    
    let index = StickerIndex()


    private init() {
        stickers = load()
        rebuildIndex()
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
                content: .text("灵感\n桌面贴纸 = 按住即现"),
                scopes: [.global],
                normalizedPosition: CGPoint(x: 0.55, y: 0.22),
            )
        ]
    }
    
    func add(_ sticker: Sticker) {
        stickers.append(sticker)
        index.index(sticker)
        save(stickers)
    }
    
    func remove(_ sticker: Sticker) {
        stickers.removeAll { $0.id == sticker.id }
        index.remove(sticker)
        save(stickers)
    }
    
    private func rebuildIndex() {
        index.clear()
        for sticker in stickers {
            index.index(sticker)
        }
    }
    
    func visibleStickers(in context: StickerContext) -> [Sticker] {
        var candidateIds = Set<UUID>()
        print(context)
        candidateIds.formUnion(index.global)

        if let bundleId = context.resolvedBundleId,
           let set = index.byApp[bundleId] {
            candidateIds.formUnion(set)
        }

        if context.isBrowser {
            candidateIds.formUnion(index.browser)
        }

        if let domain = context.domain,
           let set = index.byDomain[domain] {
            candidateIds.formUnion(set)
        }

        if let url = context.url,
           let set = index.byUrl[url] {
            candidateIds.formUnion(set)
        }
            
        return stickers
            .filter { candidateIds.contains($0.id) }
            .filter { $0.isVisible(in: context) }
    }


}
