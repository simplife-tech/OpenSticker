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
        let localizations: [String: Translation]?
        let configuration: [PluginConfigurationField]?
        let networkHosts: [String]?
        let loopbackAddressKey: String?
        let loopbackAddressKeys: [String]?
        let loopbackProxyHosts: [String]?
        let listener: PluginListenerDeclaration?
        let usesLocalAI: Bool?

        var reservedLoopbackKeys: [String] {
            (loopbackAddressKey.map { [$0] } ?? []) + (loopbackAddressKeys ?? [])
        }

        var requestsNetwork: Bool {
            !(networkHosts ?? []).isEmpty || !reservedLoopbackKeys.isEmpty || !(loopbackProxyHosts ?? []).isEmpty || listener != nil
        }

        struct Translation: Codable, Equatable {
            let name: String?
            let description: String?
            let author: String?
        }
    }

    let manifest: Manifest
    let html: String
    let script: String
    var installedAt: Date? = nil
    var sourceURL: URL? = nil
    var localSourceURL: URL? = nil

    func isUpdate(of previous: StickerPlugin) -> Bool {
        guard id == previous.id else { return false }
        switch (sourceURL, previous.sourceURL) {
        case (nil, nil):
            // Legacy local installs had no saved folder. Record it on the next import.
            return previous.localSourceURL == nil || localSourceURL == previous.localSourceURL
        case let (current?, old?):
            if current == old { return true }
            guard let lhs = try? GitHubPluginSource(current.absoluteString),
                  let rhs = try? GitHubPluginSource(old.absoluteString) else { return false }
            return lhs.owner.lowercased() == rhs.owner.lowercased()
                && lhs.repository.lowercased() == rhs.repository.lowercased()
                && lhs.ref == rhs.ref && lhs.folder == rhs.folder
        default:
            return false
        }
    }

    var id: String { manifest.id }
    private var translation: Manifest.Translation? { manifest.localizations?[L10n.language] }
    var name: String { translation?.name ?? manifest.name }
    var description: String? { translation?.description ?? manifest.description }
    var author: String? { translation?.author ?? manifest.author }
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
                           scriptData: read("plugin.js", limit: 512_000),
                           localSourceURL: folder.standardizedFileURL.resolvingSymlinksInPath())
    }

    func install(manifestData: Data, htmlData: Data, scriptData: Data,
                 sourceURL: URL? = nil, localSourceURL: URL? = nil, updating previous: StickerPlugin? = nil) throws -> String {
        guard manifestData.count <= 16_384, htmlData.count <= 128_000,
              scriptData.count <= 512_000 else { throw CocoaError(.fileReadTooLarge) }
        guard let html = String(data: htmlData, encoding: .utf8), !html.isEmpty,
              let script = String(data: scriptData, encoding: .utf8), !script.isEmpty else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }

        let manifest = try JSONDecoder().decode(StickerPlugin.Manifest.self, from: manifestData)
        let fields = manifest.configuration ?? []
        guard fields.count <= 32, Set(fields.map(\.key)).count == fields.count,
              fields.allSatisfy(\.isValid),
              manifest.reservedLoopbackKeys.count <= 8,
              Set(manifest.reservedLoopbackKeys).count == manifest.reservedLoopbackKeys.count,
              manifest.reservedLoopbackKeys.allSatisfy({ (1...128).contains($0.utf8.count) }),
              manifest.listener?.isValid ?? true,
              PluginNetwork.validHosts(manifest.networkHosts ?? []),
              PluginNetwork.validHosts(manifest.loopbackProxyHosts ?? []),
              (manifest.loopbackProxyHosts ?? []).allSatisfy({ !$0.contains(":") }), manifest.formatVersion == 1,
              manifest.id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#, options: .regularExpression) != nil,
              !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "StickerPlugin", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L10n.text("插件清单无效或格式版本不受支持。")])
        }
        if let previous {
            guard plugins.contains(previous),
                  manifest.id == previous.id || manifest.previousIDs?.contains(previous.id) == true,
                  !plugins.contains(where: { $0.id != previous.id && $0.id == manifest.id }),
                  let installed = previous.manifest.version.flatMap(UpdateChecker.versionParts),
                  let latest = manifest.version.flatMap(UpdateChecker.versionParts),
                  installed.lexicographicallyPrecedes(latest) else {
                throw NSError(domain: "StickerPlugin", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: L10n.text("插件已变化或来源不匹配，请重新检查。")])
            }
        }
        let replacedIDs = previous.map { Set([$0.id]) }
            ?? Set([manifest.id] + (manifest.previousIDs ?? []))
        let installedAt = plugins.first { replacedIDs.contains($0.id) }?.installedAt ?? Date()
        let plugin = StickerPlugin(manifest: manifest, html: html, script: script, installedAt: installedAt,
                                   sourceURL: sourceURL, localSourceURL: localSourceURL)
        try save((plugins.filter { !replacedIDs.contains($0.id) } + [plugin]).sorted { $0.name < $1.name })
        return plugin.id
    }

    func uninstall(_ id: String) throws {
        try save(plugins.filter { $0.id != id })
    }

    private func save(_ updated: [StickerPlugin]) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(updated), forKey: storageKey)
        PluginConfiguration.shared.reconcile(previous: plugins, installed: updated)
        ClipboardHistory.shared.reconcile(installed: updated)
        PluginListenerRegistry.shared.reconcile(installed: updated)
        plugins = updated
    }
}
