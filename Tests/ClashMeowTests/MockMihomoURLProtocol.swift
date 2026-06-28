import Foundation

private final class MockMihomoStore: @unchecked Sendable {
    static let shared = MockMihomoStore()

    private let lock = NSLock()
    var mode = "rule"
    var globalNow = "Tokyo-01"
    var patchModeCalls: [String] = []
    var selectProxyCalls: [(group: String, name: String)] = []
    var handledRequests: [(method: String, path: String)] = []
    var patchModeShouldFail = false

    func reset(mode: String = "rule", globalNow: String = "Tokyo-01", patchModeShouldFail: Bool = false) {
        lock.withLock {
            self.mode = mode
            self.globalNow = globalNow
            patchModeCalls = []
            selectProxyCalls = []
            handledRequests = []
            self.patchModeShouldFail = patchModeShouldFail
        }
    }

    func recordRequest(method: String, path: String) {
        lock.withLock {
            handledRequests.append((method: method, path: path))
        }
    }

    func recordModePatch(_ mode: String) {
        lock.withLock {
            self.mode = mode
            patchModeCalls.append(mode)
        }
    }

    func recordProxySelection(group: String, name: String) {
        lock.withLock {
            if group == "GLOBAL" {
                globalNow = name
            }
            selectProxyCalls.append((group: group, name: name))
        }
    }

    func snapshot() -> (mode: String, globalNow: String, patchModeCalls: [String], selectProxyCalls: [(group: String, name: String)], handledRequests: [(method: String, path: String)], patchModeShouldFail: Bool) {
        lock.withLock {
            (mode, globalNow, patchModeCalls, selectProxyCalls, handledRequests, patchModeShouldFail)
        }
    }
}

enum MockMihomoURLProtocolSupport {
    static var mode: String {
        get { MockMihomoStore.shared.snapshot().mode }
        set { MockMihomoStore.shared.recordModePatch(newValue) }
    }

    static var globalNow: String {
        MockMihomoStore.shared.snapshot().globalNow
    }

    static var patchModeCalls: [String] {
        MockMihomoStore.shared.snapshot().patchModeCalls
    }

    static var selectProxyCalls: [(group: String, name: String)] {
        MockMihomoStore.shared.snapshot().selectProxyCalls
    }

    static var handledRequests: [(method: String, path: String)] {
        MockMihomoStore.shared.snapshot().handledRequests
    }

    static func reset(mode: String = "rule", globalNow: String = "Tokyo-01", patchModeShouldFail: Bool = false) {
        MockMihomoStore.shared.reset(mode: mode, globalNow: globalNow, patchModeShouldFail: patchModeShouldFail)
    }
}

@objc(MockMihomoURLProtocol)
final class MockMihomoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let path = url.path
        let method = request.httpMethod ?? "GET"
        let store = MockMihomoStore.shared
        store.recordRequest(method: method, path: path)

        do {
            if method == "GET", path.hasSuffix("/version") || path == "/version" {
                try respond(json: ["version": "test", "premium": true, "meta": true])
                return
            }
            if method == "GET", path.hasSuffix("/configs") || path == "/configs" {
                try respond(json: Self.configPayload(mode: store.snapshot().mode))
                return
            }
            if method == "PATCH", path.hasSuffix("/configs") || path == "/configs" {
                if store.snapshot().patchModeShouldFail {
                    try respond(statusCode: 500, data: Data("mode patch failed".utf8))
                    return
                }
                if let body = request.httpBody ?? request.httpBodyStream.flatMap(readBody(from:)),
                   let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                   let mode = object["mode"] as? String {
                    store.recordModePatch(mode)
                }
                try respond(statusCode: 204, data: Data())
                return
            }
            if method == "GET", path.hasSuffix("/proxies") || path == "/proxies" {
                try respond(json: Self.proxiesPayload(globalNow: store.snapshot().globalNow))
                return
            }
            if method == "PUT", path.contains("/proxies/") {
                let group = String(path.split(separator: "/").last ?? "")
                if let body = request.httpBody ?? request.httpBodyStream.flatMap(readBody(from:)),
                   let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                   let name = object["name"] as? String {
                    store.recordProxySelection(group: group, name: name)
                }
                try respond(statusCode: 204, data: Data())
                return
            }
            if method == "GET", path.hasSuffix("/connections") || path == "/connections" {
                try respond(json: ["downloadTotal": 0, "uploadTotal": 0, "connections": []])
                return
            }
            if method == "GET", path.hasSuffix("/rules") || path == "/rules" {
                try respond(json: ["rules": []])
                return
            }
            if method == "GET", path.hasSuffix("/traffic") || path == "/traffic" {
                try respond(json: ["up": 0, "down": 0, "upTotal": 0, "downTotal": 0])
                return
            }
            try respond(statusCode: 404, data: Data("not found".utf8))
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func readBody(from stream: InputStream) -> Data? {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }

    override func stopLoading() {}

    private func respond(json: [String: Any], statusCode: Int = 200) throws {
        let data = try JSONSerialization.data(withJSONObject: json)
        try respond(statusCode: statusCode, data: data)
    }

    private func respond(statusCode: Int, data: Data) throws {
        guard let client, let url = request.url else { return }
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty {
            client.urlProtocol(self, didLoad: data)
        }
        client.urlProtocolDidFinishLoading(self)
    }

    private static func configPayload(mode: String) -> [String: Any] {
        [
            "port": 7890,
            "mixed-port": 7890,
            "mode": mode,
            "log-level": "info",
            "allow-lan": false,
            "external-controller": "127.0.0.1:9090"
        ]
    }

    private static func proxiesPayload(globalNow: String) -> [String: Any] {
        let nodeNames = ["Tokyo-01", "Singapore-02", "Los Angeles-03"]
        var proxies: [String: Any] = [
            "GLOBAL": [
                "type": "Selector",
                "name": "GLOBAL",
                "now": globalNow,
                "all": nodeNames
            ],
            "Proxy": [
                "type": "Selector",
                "name": "Proxy",
                "now": "DIRECT",
                "all": ["DIRECT"] + nodeNames
            ]
        ]

        for name in nodeNames {
            proxies[name] = [
                "type": "VMess",
                "name": name,
                "history": [["delay": 50]]
            ]
        }

        return ["proxies": proxies]
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
