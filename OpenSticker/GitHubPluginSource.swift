import Foundation

struct GitHubPluginSource {
    let sourceURL: URL
    let owner: String
    let repository: String
    let ref: String
    let folder: [String]

    var usesStickerCredentials: Bool {
        ["simplife-tech/opensticker", "simplife-tech/sticker"].contains("\(owner)/\(repository)".lowercased())
    }

    init(_ link: String) throws {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host?.lowercased() == "github.com",
              url.user == nil, url.password == nil, url.port == nil else { throw Failure.invalidLink }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 5, parts[2] == "tree",
              parts.prefix(2).allSatisfy({ $0.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil }),
              parts.dropFirst(3).allSatisfy({ $0 != "." && $0 != ".." && !$0.contains("/") }) else {
            throw Failure.invalidLink
        }
        sourceURL = url
        owner = parts[0]
        repository = parts[1]
        ref = parts[3]
        folder = Array(parts.dropFirst(4))
    }

    private struct Entry: Decodable {
        let name: String
        let type: String
        let sha: String
        let size: Int
    }

    func download(token: String?) async throws -> (Data, Data, Data) {
        let directory = try await request(path: ["contents"] + folder, ref: ref, token: token)
        let entries = try JSONDecoder().decode([Entry].self, from: directory)
        @Sendable func file(_ name: String, limit: Int) async throws -> Data {
            guard let entry = entries.first(where: { $0.name == name && $0.type == "file" }),
                  entry.sha.range(of: #"^[a-f0-9]{40}$"#, options: .regularExpression) != nil else {
                throw Failure.missingFile(name)
            }
            guard (1...limit).contains(entry.size) else { throw CocoaError(.fileReadTooLarge) }
            let data = try await request(path: ["git", "blobs", entry.sha], raw: true, token: token)
            guard data.count == entry.size else { throw URLError(.cannotDecodeContentData) }
            return data
        }
        async let manifest = file("manifest.json", limit: 16_384)
        async let html = file("index.html", limit: 128_000)
        async let script = file("plugin.js", limit: 512_000)
        return try await (manifest, html, script)
    }

    private func request(path: [String], ref: String? = nil, raw: Bool = false, token: String?) async throws -> Data {
        let base = URL(string: "https://api.github.com")!
        let url = (["repos", owner, repository] + path).reduce(base) { $0.appendingPathComponent($1) }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if let ref { components.queryItems = [URLQueryItem(name: "ref", value: ref)] }
        guard let requestURL = components.url else { throw Failure.invalidLink }
        var request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(raw ? "application/vnd.github.raw+json" : "application/vnd.github+json",
                         forHTTPHeaderField: "Accept")
        if usesStickerCredentials, let token {
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.http(status) }
        return data
    }

    enum Failure: LocalizedError {
        case invalidLink, missingFile(String), http(Int)

        var errorDescription: String? {
            switch self {
            case .invalidLink: return L10n.text("请输入 GitHub 上的插件文件夹链接，例如 github.com/组织/仓库/tree/main/插件目录。")
            case .missingFile(let name): return L10n.format("插件目录中缺少 %@。", name)
            case .http(404): return L10n.text("找不到插件目录，或当前没有读取权限。")
            case .http(let status): return L10n.format("GitHub 下载失败（HTTP %lld）。", status)
            }
        }

        var mayNeedCredentials: Bool {
            if case .http(let status) = self { return [401, 403, 404].contains(status) }
            return false
        }
    }
}
