//
//  StickerStore.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//


import Foundation
import AppKit

struct StickerGroup: Codable, Identifiable {
    let id: UUID
    var name: String
}

final class StickerStore: ObservableObject {

    static let shared = StickerStore()

    @Published private(set) var groups: [StickerGroup] = []
    @Published private(set) var activeGroupID: UUID?
    @Published var stickers: [Sticker] = []
    
    let index = StickerIndex()

    private let location = StickerResourceLocation.shared

    private init() {
        stickers = load()
        loadGroups()
        rebuildIndex()
    }
    

    private var fileURL: URL {
        location.stickersJSON
    }
    
    func refreshAll() {
        stickers = load()
        loadGroups()
        rebuildIndex()
    }

    private var groupsURL: URL { location.rootURL.appendingPathComponent("groups.json") }
    private let activeGroupKey = "StickerActiveGroup"

    private func loadGroups() {
        groups = (try? JSONDecoder().decode([StickerGroup].self, from: Data(contentsOf: groupsURL))) ?? []
        let saved = UserDefaults.standard.string(forKey: activeGroupKey).flatMap(UUID.init(uuidString:))
        activeGroupID = validGroupID(saved)
    }

    func validGroupID(_ id: UUID?) -> UUID? {
        guard let id, groups.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    func groupName(_ id: UUID?) -> String {
        groups.first { $0.id == id }?.name ?? L10n.text("默认")
    }

    func selectGroup(_ id: UUID?) {
        activeGroupID = validGroupID(id)
        UserDefaults.standard.set(activeGroupID?.uuidString, forKey: activeGroupKey)
    }

    func stepGroup(by offset: Int) {
        let ids: [UUID?] = [nil] + groups.map { Optional($0.id) }
        guard ids.count > 1, let index = ids.firstIndex(of: activeGroupID) else { return }
        let nextIndex = (index + offset % ids.count + ids.count) % ids.count
        selectGroup(ids[nextIndex])
    }

    func saveGroup(id: UUID? = nil, name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "默认", name.localizedCaseInsensitiveCompare("Default") != .orderedSame,
              !groups.contains(where: { $0.id != id && $0.name == name }) else {
            throw NSError(domain: "StickerGroup", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L10n.text("请输入一个未使用的分组名称。")])
        }
        var updated = groups
        if let id, let index = updated.firstIndex(where: { $0.id == id }) {
            updated[index].name = name
        } else {
            updated.append(StickerGroup(id: UUID(), name: name))
        }
        try writeGroups(updated)
    }

    func canMoveGroup(_ id: UUID, by offset: Int) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return false }
        return groups.indices.contains(index + offset)
    }

    func moveGroup(_ id: UUID, by offset: Int) throws {
        guard canMoveGroup(id, by: offset),
              let index = groups.firstIndex(where: { $0.id == id }) else { return }
        var updated = groups
        let group = updated.remove(at: index)
        updated.insert(group, at: index + offset)
        try writeGroups(updated)
    }

    func removeGroup(_ id: UUID) throws {
        try writeGroups(groups.filter { $0.id != id })
        if activeGroupID == id { selectGroup(nil) }
    }

    private func writeGroups(_ updated: [StickerGroup]) throws {
        try JSONEncoder().encode(updated).write(to: groupsURL, options: .atomic)
        groups = updated
    }

    func centerSticker(_ id: UUID) throws {
        guard let index = stickers.firstIndex(where: { $0.id == id }) else { return }
        var updated = stickers
        updated[index].normalizedPosition = CGPoint(x: 0.5, y: 0.5)
        try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
        stickers = updated
    }

    func moveSticker(_ stickerID: UUID, to groupID: UUID?) throws {
        guard let index = stickers.firstIndex(where: { $0.id == stickerID }) else { return }
        var updated = stickers
        updated[index].groupID = validGroupID(groupID)
        try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
        stickers = updated
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
                content: .text(L10n.text("灵感\n桌面贴纸 = 按住即现")),
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
        if sticker.plugin?.pluginID == ClipboardHistory.pluginID,
           !remaining.contains(where: { $0.plugin?.pluginID == ClipboardHistory.pluginID }) {
            ClipboardHistory.shared.reset()
        }

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
