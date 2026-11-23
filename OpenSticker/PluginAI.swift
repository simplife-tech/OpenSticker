import Foundation
import Security

@MainActor
enum PluginAI {
    enum Failure: Error {
        case unavailable, busy, timedOut, invalidResponse, http(Int)
    }

    static let modelPreferenceKey = "StickerAIModel"
    static let baseURLPreferenceKey = "StickerAIBaseURL"
    private static var running = false
    private static let keychainQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "tech.simplife.opensticker.ai",
        kSecAttrAccount as String: "api-key"
    ]

    static func endpoint(_ baseURL: String) -> URL? {
        guard let parts = URLComponents(string: baseURL), let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, let url = parts.url else { return nil }
        return url.appendingPathComponent("chat").appendingPathComponent("completions")
    }

    static func apiKey() throws -> String {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func saveAPIKey(_ key: String) throws {
        var status: OSStatus
        if key.isEmpty {
            status = SecItemDelete(keychainQuery as CFDictionary)
            if status == errSecItemNotFound { return }
        } else {
            let data = Data(key.utf8)
            status = SecItemUpdate(keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = keychainQuery
                item[kSecValueData as String] = data
                status = SecItemAdd(item as CFDictionary, nil)
            }
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func run(prompt: String, schema: Data) async throws -> Data {
        guard !running else { throw Failure.busy }
        let defaults = UserDefaults.standard
        let model = defaults.string(forKey: modelPreferenceKey) ?? ""
        guard let url = endpoint(defaults.string(forKey: baseURLPreferenceKey) ?? ""),
              !model.isEmpty, let key = try? apiKey(), !key.isEmpty else {
            throw Failure.unavailable
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [
                ["role": "system", "content": "Return only a JSON object conforming to this schema:\n" + String(decoding: schema, as: UTF8.self)],
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"]
        ])

        running = true
        defer { running = false }
        let response: [String: Any]
        do { response = try await PluginNetwork.send(request) }
        catch let error as URLError where error.code == .timedOut { throw Failure.timedOut }
        try Task.checkCancellation()
        guard let status = response["status"] as? Int else { throw Failure.invalidResponse }
        guard (200..<300).contains(status) else { throw Failure.http(status) }
        guard let body = response["body"] as? String,
              let envelope = try? JSONDecoder().decode(Completion.self, from: Data(body.utf8)),
              let content = envelope.choices.first?.message.content,
              content.utf8.count <= 32_768,
              (try? JSONSerialization.jsonObject(with: Data(content.utf8))) is [String: Any] else {
            throw Failure.invalidResponse
        }
        return Data(content.utf8)
    }

    private struct Completion: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }
}
