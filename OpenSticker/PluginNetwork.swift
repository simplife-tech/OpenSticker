import Foundation

enum PluginNetwork {
    static func validHosts(_ hosts: [String]) -> Bool {
        hosts.count <= 16 && Set(hosts).count == hosts.count && hosts.allSatisfy { host in
            host.utf8.count <= 253 && host.range(
                of: #"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$"#,
                options: .regularExpression
            ) != nil
        }
    }

    static func request(from input: [String: Any], hosts: [String]) -> URLRequest? {
        guard let address = input["url"] as? String, address.utf8.count <= 8192,
              let url = URL(string: address), url.scheme == "https",
              let host = url.host?.lowercased(), hosts.contains(host),
              url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443 else { return nil }
        let method = input["method"] as? String ?? "GET"
        guard ["GET", "POST"].contains(method) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        if let body = input["body"] as? String {
            guard method == "POST", body.utf8.count <= 262_144 else { return nil }
            request.httpBody = Data(body.utf8)
        }
        let headers = input["headers"] as? [String: String] ?? [:]
        guard headers.count <= 8 else { return nil }
        for (name, value) in headers {
            guard ["accept", "content-type", "origin", "cookie", "authorization"].contains(name.lowercased()),
                  value.utf8.count <= 8192,
                  value.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 127 }) else { return nil }
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    static func send(_ request: URLRequest) async throws -> [String: Any] {
        let settings = URLSessionConfiguration.ephemeral
        settings.httpShouldSetCookies = false
        settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil
        settings.timeoutIntervalForResource = 30
        let session = URLSession(configuration: settings, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, let url = http.url else {
            throw URLError(.badServerResponse)
        }
        let limit = 2_097_152
        guard response.expectedContentLength <= limit else { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        let headers = Dictionary(uniqueKeysWithValues: http.allHeaderFields.compactMap { key, value in
            guard let key = key as? String, let value = value as? String else { return nil as (String, String)? }
            return (key, value)
        })
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).map {
            ["name": $0.name, "value": $0.value]
        }
        var result: [String: Any] = [
            "status": http.statusCode, "body": String(decoding: data, as: UTF8.self), "cookies": cookies
        ]
        if (300..<400).contains(http.statusCode), let location = http.value(forHTTPHeaderField: "Location") {
            result["location"] = location
        }
        return result
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
