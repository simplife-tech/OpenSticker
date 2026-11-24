import Foundation

enum PluginNetwork {
    static func validHosts(_ hosts: [String]) -> Bool {
        hosts.count <= 16 && Set(hosts).count == hosts.count && hosts.allSatisfy { host in
            if let port = loopbackPort(host) { return (1024...65535).contains(port) }
            return host.utf8.count <= 253 && host.range(
                of: #"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$"#,
                options: .regularExpression
            ) != nil
        }
    }

    private static func loopbackPort(_ address: String) -> Int? {
        let prefix = "127.0.0.1:"
        guard address.hasPrefix(prefix), let port = Int(address.dropFirst(prefix.count)),
              address == prefix + String(port) else { return nil }
        return port
    }

    static func configuredLoopbackHost(_ address: String) -> String? {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = value.hasPrefix("http://") ? String(value.dropFirst(7)) : value
        let normalized = candidate.hasPrefix("localhost:") ? "127.0.0.1:" + candidate.dropFirst(10) : candidate
        guard let port = loopbackPort(normalized), (1024...65535).contains(port) else { return nil }
        return normalized
    }

    static func request(from input: [String: Any], hosts: [String]) -> URLRequest? {
        guard let address = input["url"] as? String, address.utf8.count <= 8192,
              let url = URL(string: address), let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        let method = input["method"] as? String ?? "GET"
        let remote = url.scheme == "https" && hosts.contains(host) && (url.port == nil || url.port == 443)
        let local = url.scheme == "http" && host == "127.0.0.1" && method == "GET"
            && url.port.map { hosts.contains("127.0.0.1:" + String($0)) } == true
        guard (remote || local), ["GET", "POST"].contains(method) else { return nil }
        if input["responseEncoding"] != nil && (input["responseEncoding"] as? String != "base64" || !local) {
            return nil
        }
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

    static func proxiedRequest(from input: [String: Any], hosts: [String], endpoints: [String])
        -> (URLRequest, Int)? {
        guard let endpoint = input["viaLoopbackProxy"] as? String, endpoints.contains(endpoint),
              let port = loopbackPort(endpoint), (1024...65535).contains(port),
              let address = input["url"] as? String, address.utf8.count <= 8192,
              let url = URL(string: address), url.scheme == "http",
              let host = url.host?.lowercased(), hosts.contains(host),
              url.port == nil, url.user == nil, url.password == nil, url.fragment == nil,
              (input["method"] as? String ?? "GET") == "GET",
              input["body"] == nil, input["responseEncoding"] == nil else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        if let headers = input["headers"] as? [String: String] {
            for (key, value) in headers {
                guard ["authorization", "accept"].contains(key.lowercased()),
                      value.utf8.count <= 8192,
                      value.unicodeScalars.allSatisfy({ (32...126).contains($0.value) }) else { return nil }
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        return (request, port)
    }

    static func send(_ request: URLRequest, base64: Bool = false, loopbackProxyPort: Int? = nil) async throws -> [String: Any] {
        let settings = URLSessionConfiguration.ephemeral
        settings.httpShouldSetCookies = false
        settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil
        settings.timeoutIntervalForResource = 30
        let loopback = request.url?.host == "127.0.0.1"
        if let port = loopbackProxyPort {
            settings.connectionProxyDictionary = ["HTTPEnable": true, "HTTPProxy": "127.0.0.1", "HTTPPort": port,
                                                  "ExcludeSimpleHostnames": false, "ExceptionsList": []]
        } else if loopback {
            settings.connectionProxyDictionary = ["HTTPEnable": false, "HTTPSEnable": false, "SOCKSEnable": false,
                                                  "ProxyAutoConfigEnable": false, "ProxyAutoDiscoveryEnable": false]
        }
        let session = URLSession(configuration: settings, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, let url = http.url else {
            throw URLError(.badServerResponse)
        }
        let limit = (loopback || loopbackProxyPort != nil) && !base64 ? 8_388_608 : 2_097_152
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
            "status": http.statusCode, "body": base64 ? data.base64EncodedString() : String(decoding: data, as: UTF8.self), "cookies": cookies
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
