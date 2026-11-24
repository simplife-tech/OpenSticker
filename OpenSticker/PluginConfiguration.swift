import Combine
import CryptoKit
import Foundation
import Security

struct PluginConfigurationField: Codable, Equatable {
    enum Kind: String, Codable { case text, secret }

    let key: String
    let label: String?
    let type: Kind
    let localizations: [String: String]?

    var title: String { localizations?[L10n.language] ?? label ?? key }

    var isValid: Bool {
        key.utf8.count <= 128
            && key.range(of: #"^[a-z0-9][a-z0-9_.-]*(/[a-z0-9][a-z0-9_.-]*)+$"#,
                         options: .regularExpression) != nil
    }
}

final class PluginConfiguration: ObservableObject {
    static let shared = PluginConfiguration()
    @Published private(set) var grants: [String: String]
    @Published private(set) var networkGrants: [String: String]
    @Published private(set) var aiGrants: [String: String]
    private let aiGrantsKey = "StickerPluginAIGrants"
    private let networkGrantsKey = "StickerPluginNetworkGrants"
    private let grantsKey = "StickerPluginConfigurationGrants"

    private let keychainQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "tech.simplife.opensticker.plugin-configuration",
        kSecAttrAccount as String: "shared-values"
    ]

    private init() {
        aiGrants = UserDefaults.standard.dictionary(forKey: aiGrantsKey) as? [String: String] ?? [:]
        networkGrants = UserDefaults.standard.dictionary(forKey: networkGrantsKey) as? [String: String] ?? [:]
        grants = UserDefaults.standard.dictionary(forKey: grantsKey) as? [String: String] ?? [:]
    }

    func isAuthorized(_ plugin: StickerPlugin) -> Bool {
        guard let version = fingerprint(plugin) else { return false }
        return grants[plugin.id] == version
    }

    func setAuthorized(_ authorized: Bool, for plugin: StickerPlugin) {
        if authorized, let version = fingerprint(plugin) {
            grants[plugin.id] = version
        } else {
            grants.removeValue(forKey: plugin.id)
        }
        UserDefaults.standard.set(grants, forKey: grantsKey)
    }

    func isNetworkAuthorized(_ plugin: StickerPlugin) -> Bool {
        guard let version = fingerprint(plugin) else { return false }
        return networkGrants[plugin.id] == version
    }

    func setNetworkAuthorized(_ authorized: Bool, for plugin: StickerPlugin) {
        networkGrants[plugin.id] = authorized ? fingerprint(plugin) : nil
        if !authorized { PluginListenerRegistry.shared.stop(plugin.id) }
        UserDefaults.standard.set(networkGrants, forKey: networkGrantsKey)
    }

    func isAIAuthorized(_ plugin: StickerPlugin) -> Bool {
        guard let version = fingerprint(plugin) else { return false }
        return aiGrants[plugin.id] == version
    }

    func setAIAuthorized(_ authorized: Bool, for plugin: StickerPlugin) {
        aiGrants[plugin.id] = authorized ? fingerprint(plugin) : nil
        UserDefaults.standard.set(aiGrants, forKey: aiGrantsKey)
    }

    func reconcile(previous: [StickerPlugin], installed: [StickerPlugin]) {
        func retained(_ existing: [String: String],
                      covers: (StickerPlugin.Manifest, StickerPlugin.Manifest) -> Bool) -> [String: String] {
            var result: [String: String] = [:]
            for plugin in installed {
                guard let grant = existing[plugin.id],
                      let old = previous.first(where: { plugin.isUpdate(of: $0) }),
                      fingerprint(old) == grant,
                      covers(old.manifest, plugin.manifest),
                      let fingerprint = fingerprint(plugin) else { continue }
                result[plugin.id] = fingerprint
            }
            return result
        }

        let active = retained(grants) { old, new in
            let keys = Set((new.configuration ?? []).map(\.key))
            return !keys.isEmpty && keys.isSubset(of: Set((old.configuration ?? []).map(\.key)))
        }
        if active != grants {
            grants = active
            UserDefaults.standard.set(active, forKey: grantsKey)
        }

        let activeAI = retained(aiGrants) { old, new in
            old.usesLocalAI == true && new.usesLocalAI == true
        }
        if activeAI != aiGrants {
            aiGrants = activeAI
            UserDefaults.standard.set(activeAI, forKey: aiGrantsKey)
        }

        let activeNetwork = retained(networkGrants) { old, new in
            let hosts = Set(new.networkHosts ?? [])
            return new.requestsNetwork && hosts.isSubset(of: Set(old.networkHosts ?? []))
                && Set(new.loopbackProxyHosts ?? []).isSubset(of: Set(old.loopbackProxyHosts ?? []))
                && Set(new.reservedLoopbackKeys).isSubset(of: Set(old.reservedLoopbackKeys))
                && (new.listener == nil || new.listener == old.listener)
        }
        if activeNetwork != networkGrants {
            networkGrants = activeNetwork
            UserDefaults.standard.set(activeNetwork, forKey: networkGrantsKey)
        }
    }

    private func fingerprint(_ plugin: StickerPlugin) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(plugin) else { return nil }
        return Data(SHA256.hash(data: data)).base64EncodedString()
    }

    func configuredKeys() throws -> Set<String> {
        Set(try readValues().keys)
    }

    func value(for key: String) throws -> String? {
        try readValues()[key]
    }

    func apply(_ changes: [String: String], removing: Set<String>) throws {
        var values = try readValues()
        for key in removing { values.removeValue(forKey: key) }
        for (key, value) in changes { values[key] = value }
        let data = try JSONEncoder().encode(values)
        let attributes = [kSecValueData as String: data]
        var status = SecItemUpdate(keychainQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = keychainQuery
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw keychainError(status) }
    }

    private func readValues() throws -> [String: String] {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess, let data = result as? Data else { throw keychainError(status) }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func keychainError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
}
