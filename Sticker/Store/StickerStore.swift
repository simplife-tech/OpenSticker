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

    private let location = StickerResourceLocation.shared

    private init() {
        stickers = load()
        rebuildIndex()
    }
    

    private var fileURL: URL {
        location.stickersJSON
    }
    
    func refreshAll() {
        stickers = load()
        rebuildIndex()
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
    
    func edit(_ id: UUID, content: StickerContent, scopes: Set<StickerScope>) throws {
        guard let index = stickers.firstIndex(where: { $0.id == id }) else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        var updated = stickers
        updated[index].content = content
        updated[index].scopes = scopes
        let data = try JSONEncoder().encode(updated)
        try data.write(to: fileURL, options: .atomic)
        stickers = updated
        rebuildIndex()
    }

    func remove(_ id: UUID) {
        guard let sticker = stickers.first(where: { $0.id == id }) else { return }
        let remaining = stickers.filter { $0.id != id }

        do {
            try JSONEncoder().encode(remaining).write(to: fileURL, options: .atomic)
        } catch {
            NSApp.presentError(error)
            return
        }

        stickers = remaining
        index.remove(sticker)

        let candidates = imageFilenames(in: sticker.content)
        guard !candidates.isEmpty else { return }
        let referenced = Set(remaining.flatMap { imageFilenames(in: $0.content) }.map { $0.lowercased() })
        for filename in candidates where !referenced.contains(filename.lowercased()) {
            ImageStore.shared.remove(filename: filename)
        }
    }

    private func imageFilenames(in content: StickerContent) -> Set<String> {
        switch content {
        case .image(let payload):
            return [payload.filename]
        case .text(let text):
            let source = text as NSString
            let range = NSRange(location: 0, length: source.length)
            return Set(ImageStore.markdownImagePattern.matches(in: text, range: range).map {
                source.substring(with: $0.range(at: 1))
            })
        }
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
