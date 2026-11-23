import AppKit
import Security

final class UpdateChecker {
    static let shared = UpdateChecker()
    private(set) var isChecking = false

    private let latestAPI = URL(string: "https://api.github.com/repos/simplife-tech/OpenSticker/releases/latest")!
    private let releasePage = URL(string: "https://github.com/simplife-tech/OpenSticker/releases/latest")!

    private struct Release: Decodable {
        let tag_name: String
    }

    func check(onFinish: @escaping () -> Void) {
        isChecking = true
        Task { @MainActor in
            defer {
                isChecking = false
                onFinish()
            }
            do {
                var token = readToken()
                var (data, status) = try await fetch(token: token)
                if [401, 403, 404].contains(status) {
                    guard let entered = requestToken(replacing: token != nil) else { return }
                    token = entered
                    (data, status) = try await fetch(token: token)
                    if status == 200 { try saveToken(entered) }
                }
                guard status == 200 else { throw URLError(.badServerResponse) }
                let tag = try JSONDecoder().decode(Release.self, from: data).tag_name
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
                guard let installed = Self.versionParts(current),
                      let latest = Self.versionParts(tag) else { throw URLError(.cannotParseResponse) }

                if installed.lexicographicallyPrecedes(latest) {
                    show(L10n.format("发现新版本 %@", tag), detail: L10n.format("当前版本为 %@。可以前往 GitHub 下载新版。", current),
                         offerDownload: true)
                } else {
                    show(L10n.text("当前已是最新版本"), detail: "OpenSticker \(current)")
                }
            } catch {
                show(L10n.text("无法检查更新"), detail: L10n.text("暂时无法获取 GitHub 发布信息，请稍后重试。"))
            }
        }
    }

    private func fetch(token: String?) async throws -> (Data, Int) {
        var request = URLRequest(url: latestAPI, timeoutInterval: 15)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private var keychainItem: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "tech.simplife.opensticker.github-updates",
            kSecAttrAccount as String: "simplife-tech/OpenSticker"
        ]
    }

    func readToken() -> String? {
        var query = keychainItem
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveToken(_ token: String) throws {
        let attributes = [kSecValueData as String: Data(token.utf8)]
        var status = SecItemUpdate(keychainItem as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = keychainItem
            item[kSecValueData as String] = Data(token.utf8)
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    @MainActor func requestToken(replacing: Bool, importing: Bool = false) -> String? {
        let alert = updateAlert()
        alert.messageText = importing ? L10n.text("访问私有插件仓库")
            : replacing ? L10n.text("GitHub 令牌无法读取版本") : L10n.text("检查私有仓库的版本")
        alert.informativeText = L10n.text("请输入对 simplife-tech/OpenSticker 有 Contents 读取权限的 GitHub 令牌。验证成功后会保存到系统钥匙串，供版本检查和该仓库的插件导入使用。")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 290, height: 24))
        field.placeholderString = L10n.text("GitHub 令牌")
        alert.accessoryView = field
        alert.addButton(withTitle: importing ? L10n.text("继续导入") : L10n.text("检查"))
        alert.addButton(withTitle: L10n.text("取消"))
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let token = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    static func versionParts(_ value: String) -> [Int]? {
        let version = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let fields = version.split(separator: ".", omittingEmptySubsequences: false)
        let parts = fields.compactMap { Int($0) }
        guard (1...3).contains(fields.count), fields.count == parts.count,
              parts.allSatisfy({ $0 >= 0 }) else { return nil }
        return parts + Array(repeating: 0, count: 3 - parts.count)
    }

    @MainActor private func updateAlert() -> NSAlert {
        let alert = NSAlert()
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            alert.icon = icon
        }
        return alert
    }

    @MainActor private func show(_ title: String, detail: String, offerDownload: Bool = false) {
        let alert = updateAlert()
        alert.messageText = title
        alert.informativeText = detail
        if offerDownload { alert.addButton(withTitle: L10n.text("前往下载")) }
        alert.addButton(withTitle: offerDownload ? L10n.text("稍后") : L10n.text("好"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, offerDownload {
            NSWorkspace.shared.open(releasePage)
        }
    }
}
