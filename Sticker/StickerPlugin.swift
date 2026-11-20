import SwiftUI
import WebKit

struct StickerPlugin: Codable, Equatable, Identifiable {
    struct Manifest: Codable, Equatable {
        let formatVersion: Int
        let id: String
        let name: String
        let description: String?
        let author: String?
        let version: String?
        let previousIDs: [String]?
    }

    let manifest: Manifest
    let html: String
    let script: String
    var installedAt: Date? = nil

    var id: String { manifest.id }
    var name: String { manifest.name }
}

struct StickerPluginState: Codable, Equatable {
    let pluginID: String
    var values: [String: String] = [:]
}

final class StickerPluginRegistry: ObservableObject {
    static let shared = StickerPluginRegistry()
    @Published private(set) var plugins: [StickerPlugin]
    private let storageKey = "InstalledWebStickerPlugins"

    private init() {
        plugins = UserDefaults.standard.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([StickerPlugin].self, from: $0) } ?? []
    }

    func plugin(for id: String) -> StickerPlugin? {
        plugins.first { $0.id == id }
            ?? plugins.first { $0.manifest.previousIDs?.contains(id) == true }
    }

    @discardableResult
    func install(from folder: URL) throws -> String {
        func read(_ name: String, limit: Int) throws -> Data {
            let file = folder.appendingPathComponent(name)
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true else {
                throw CocoaError(.fileReadUnknown)
            }
            guard let size = info.fileSize, size <= limit else { throw CocoaError(.fileReadTooLarge) }
            return try Data(contentsOf: file)
        }

        return try install(manifestData: read("manifest.json", limit: 16_384),
                           htmlData: read("index.html", limit: 128_000),
                           scriptData: read("plugin.js", limit: 512_000))
    }

    func install(manifestData: Data, htmlData: Data, scriptData: Data) throws -> String {
        guard manifestData.count <= 16_384, htmlData.count <= 128_000,
              scriptData.count <= 512_000 else { throw CocoaError(.fileReadTooLarge) }
        guard let html = String(data: htmlData, encoding: .utf8), !html.isEmpty,
              let script = String(data: scriptData, encoding: .utf8), !script.isEmpty else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }

        let manifest = try JSONDecoder().decode(StickerPlugin.Manifest.self, from: manifestData)
        guard manifest.formatVersion == 1,
              manifest.id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#, options: .regularExpression) != nil,
              !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "StickerPlugin", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "插件清单无效或格式版本不受支持。"])
        }
        let replacedIDs = Set([manifest.id] + (manifest.previousIDs ?? []))
        let installedAt = plugins.first { replacedIDs.contains($0.id) }?.installedAt ?? Date()
        let plugin = StickerPlugin(manifest: manifest, html: html, script: script, installedAt: installedAt)
        try save((plugins.filter { !replacedIDs.contains($0.id) } + [plugin]).sorted { $0.name < $1.name })
        return plugin.id
    }

    func uninstall(_ id: String) throws {
        try save(plugins.filter { $0.id != id })
    }

    private func save(_ updated: [StickerPlugin]) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(updated), forKey: storageKey)
        plugins = updated
    }
}
