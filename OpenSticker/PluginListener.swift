import Foundation
import Network

struct PluginListenerDeclaration: Codable, Equatable {
    let port: Int
    let path: String
    let upstream: URL
    let origins: [String]?

    var isValid: Bool {
        (1024...65535).contains(port)
            && path.range(of: #"^/[A-Za-z0-9._/-]{1,255}$"#, options: .regularExpression) != nil
            && upstream.scheme == "https"
            && upstream.host.map { PluginNetwork.validHosts([$0]) && !$0.contains(":") } == true
            && (upstream.port == nil || upstream.port == 443)
            && upstream.user == nil && upstream.password == nil && upstream.fragment == nil && upstream.query == nil
            && (origins ?? []).count <= 16
            && (origins ?? []).allSatisfy { origin in
                guard let url = URL(string: origin), let host = url.host else { return false }
                return (url.scheme == "https" || url.scheme == "http")
                    && PluginNetwork.validHosts([host]) && origin == "\(url.scheme!)://\(host)"
            }
    }
}

final class PluginListener {
    private struct Packet {
        let id: Int
        let time: Double
        let body: Data
    }

    private let rules: PluginListenerDeclaration
    private let queue: DispatchQueue
    private let listener: NWListener
    private let session: URLSession
    private let stream = UUID().uuidString
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var packets: [Packet] = []
    private var packetBytes = 0
    private var nextID = 0
    private var state = "starting"

    init(rules: PluginListenerDeclaration) throws {
        self.rules = rules
        queue = DispatchQueue(label: "app.opensticker.plugin-listener")
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(rules.port))!)
        listener = try NWListener(using: parameters)
        let settings = URLSessionConfiguration.ephemeral
        settings.httpCookieStorage = nil
        settings.httpShouldSetCookies = false
        settings.urlCredentialStorage = nil
        settings.timeoutIntervalForRequest = 12
        settings.timeoutIntervalForResource = 15
        settings.connectionProxyDictionary = ["HTTPEnable": false, "HTTPSEnable": false, "SOCKSEnable": false,
                                              "ProxyAutoConfigEnable": false, "ProxyAutoDiscoveryEnable": false]
        session = URLSession(configuration: settings, delegate: NoRedirect(), delegateQueue: nil)
        listener.stateUpdateHandler = { [weak self] status in
            switch status {
            case .ready: self?.state = "running"
            case .failed: self?.state = "failed"
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.accept(connection)
        }
        listener.start(queue: queue)
    }

    func snapshot(after: Int, stream previous: String?) -> [String: Any] {
        queue.sync {
            let cursor = previous == stream ? after : 0
            var size = 0
            let items = packets.filter { $0.id > cursor }.prefix(8).prefix { packet in
                size += packet.body.count
                return size <= 2_097_152
            }
            return ["state": state, "stream": stream, "received": nextID,
                    "packets": items.map { ["id": $0.id, "time": $0.time, "body": $0.body.base64EncodedString()] }]
        }
    }

    func stop() {
        queue.sync {
            listener.cancel()
            for connection in connections.values { connection.cancel() }
            connections.removeAll()
            session.invalidateAndCancel()
            packets.removeAll()
            packetBytes = 0
        }
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 16 else { connection.cancel(); return }
        let identifier = ObjectIdentifier(connection)
        connections[identifier] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.connections.removeValue(forKey: identifier)
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 20) { [weak self, weak connection] in
            if self?.connections[identifier] != nil { connection?.cancel() }
        }
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var bytes = buffer
            if let data { bytes.append(data) }
            guard bytes.count <= 2_195_456 else { self.reply(connection, status: 413); return }
            do {
                if let request = try PluginListenerRequest.parse(bytes, rules: self.rules) {
                    self.forward(request, on: connection)
                } else if complete || error != nil {
                    self.reply(connection, status: 400)
                } else {
                    self.receive(connection, buffer: bytes)
                }
            } catch {
                self.reply(connection, status: 400)
            }
        }
    }

    private func forward(_ request: URLRequest, on connection: NWConnection) {
        if let body = request.httpBody {
            nextID += 1
            packets.append(Packet(id: nextID, time: Date().timeIntervalSince1970, body: body))
            packetBytes += body.count
            while packets.count > 100 || packetBytes > 8_388_608 {
                packetBytes -= packets.removeFirst().body.count
            }
        }
        Task {
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.expectedContentLength <= 4_194_304 else {
                    throw URLError(.badServerResponse)
                }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < 4_194_304 else { throw URLError(.dataLengthExceedsMaximum) }
                    data.append(byte)
                }
                let headers = http.allHeaderFields.compactMap { key, value -> (String, String)? in
                    guard let name = key as? String, let text = value as? String else { return nil }
                    return (name, text)
                }
                self.reply(connection, status: http.statusCode, headers: headers, body: data)
            } catch {
                self.reply(connection, status: 502)
            }
        }
    }

    private func reply(_ connection: NWConnection, status: Int, headers: [(String, String)] = [], body: Data = Data()) {
        let excluded = PluginListenerRequest.hopHeaders.union(["content-length", "content-encoding"])
        let fields = headers.filter { !excluded.contains($0.0.lowercased()) && !$0.1.contains("\r") && !$0.1.contains("\n") }
        let reason = HTTPURLResponse.localizedString(forStatusCode: status)
        let head = (["HTTP/1.1 \(status) \(reason)", "Connection: close", "Content-Length: \(body.count)"]
                    + fields.map { "\($0.0): \($0.1)" }).joined(separator: "\r\n")
        var response = Data((head + "\r\n\r\n").utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}

enum PluginListenerRequest {
    static let hopHeaders: Set<String> = ["connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
                                          "proxy-connection", "te", "trailer", "transfer-encoding", "upgrade", "expect"]
    private static let limit = 2_097_152
    private static let newline = Data([13, 10])

    static func parse(_ bytes: Data, rules: PluginListenerDeclaration) throws -> URLRequest? {
        let invalid = URLError(.badServerResponse)
        guard let boundary = bytes.range(of: Data([13, 10, 13, 10])) else {
            if bytes.count > 32_768 { throw invalid }
            return nil
        }
        guard boundary.lowerBound <= 32_768,
              let text = String(data: bytes[..<boundary.lowerBound], encoding: .utf8) else { throw invalid }
        let lines = text.components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ")
        guard start.count == 3, start[0] == "POST", start[2] == "HTTP/1.1" || start[2] == "HTTP/1.0",
              let incoming = URLComponents(string: String(start[1])), incoming.scheme == nil, incoming.host == nil,
              incoming.percentEncodedPath == rules.path, incoming.fragment == nil else { throw invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw invalid }
            let name = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard name.range(of: #"^[a-z0-9!#$%&'*+.^_`|~-]+$"#, options: .regularExpression) != nil,
                  !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                  headers[name] == nil else { throw invalid }
            headers[name] = value
        }
        guard let host = headers["host"], ["127.0.0.1:\(rules.port)", "localhost:\(rules.port)"].contains(host),
              headers["origin"].map({ (rules.origins ?? []).contains($0) }) ?? true else { throw invalid }
        let content = Data(bytes[boundary.upperBound...])
        let body: Data
        if headers["transfer-encoding"]?.lowercased() == "chunked", headers["content-length"] == nil {
            guard let decoded = try chunks(content) else { return nil }
            body = decoded
        } else {
            guard headers["transfer-encoding"] == nil, let length = headers["content-length"].flatMap(Int.init),
                  (1...limit).contains(length) else { throw invalid }
            guard content.count >= length else { return nil }
            body = Data(content.prefix(length))
        }
        guard !body.isEmpty, var target = URLComponents(url: rules.upstream, resolvingAgainstBaseURL: false) else { throw invalid }
        target.percentEncodedQuery = incoming.percentEncodedQuery
        guard let url = target.url else { throw invalid }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        let connectionFields = (headers["connection"] ?? "").lowercased().split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let excluded = hopHeaders.union(connectionFields).union(["host", "content-length", "accept-encoding"])
        for (name, value) in headers where !excluded.contains(name) { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }

    private static func chunks(_ bytes: Data) throws -> Data? {
        var offset = 0
        var result = Data()
        while let line = bytes.range(of: newline, in: offset..<bytes.count) {
            let sizeText = String(decoding: bytes[offset..<line.lowerBound], as: UTF8.self)
            guard let raw = sizeText.split(separator: ";").first, let count = Int(raw, radix: 16),
                  (0...limit - result.count).contains(count) else { throw URLError(.badServerResponse) }
            offset = line.upperBound
            if count == 0 {
                if bytes.count - offset >= 2, bytes[offset..<offset + 2].elementsEqual(newline) { return result }
                if bytes.range(of: Data([13, 10, 13, 10]), in: offset..<bytes.count) != nil { return result }
                return nil
            }
            guard bytes.count - offset >= count + 2 else { return nil }
            guard bytes[offset + count..<offset + count + 2].elementsEqual(newline) else {
                throw URLError(.badServerResponse)
            }
            result.append(bytes[offset..<offset + count])
            offset += count + 2
        }
        return nil
    }
}

final class PluginListenerRegistry {
    static let shared = PluginListenerRegistry()
    private var listeners: [String: (PluginListenerDeclaration, PluginListener)] = [:]

    func snapshot(_ id: String, after: Int, stream: String?) -> [String: Any] {
        listeners[id]?.1.snapshot(after: after, stream: stream)
            ?? ["state": "stopped", "received": 0, "packets": []]
    }

    func start(_ id: String, rules: PluginListenerDeclaration) throws {
        if let current = listeners[id], current.0 == rules,
           current.1.snapshot(after: Int.max, stream: nil)["state"] as? String != "failed" { return }
        stop(id)
        listeners[id] = (rules, try PluginListener(rules: rules))
    }

    func stop(_ id: String) {
        listeners.removeValue(forKey: id)?.1.stop()
    }

    func reconcile(installed: [StickerPlugin]) {
        for id in Array(listeners.keys) {
            guard let plugin = installed.first(where: { $0.id == id }),
                  plugin.manifest.listener == listeners[id]?.0,
                  PluginConfiguration.shared.isNetworkAuthorized(plugin) else {
                stop(id)
                continue
            }
        }
    }
}
