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
    var tunEnabled = false
    var reloadConfigShouldFail = false
    var versionFailureCount = 0
    var groupDelayShouldFail = false
    var proxyDelayResults: [String: Int] = [:]
    var disabledRuleIndexes = Set<Int>()
    var ruleDisableShouldFail = false

    func reset(
        mode: String = "rule",
        globalNow: String = "Tokyo-01",
        patchModeShouldFail: Bool = false,
        tunEnabled: Bool = false,
        reloadConfigShouldFail: Bool = false,
        versionFailureCount: Int = 0,
        groupDelayShouldFail: Bool = false,
        proxyDelayResults: [String: Int] = [:],
        disabledRuleIndexes: Set<Int> = [],
        ruleDisableShouldFail: Bool = false
    ) {
        lock.withLock {
            self.mode = mode
            self.globalNow = globalNow
            patchModeCalls = []
            selectProxyCalls = []
            handledRequests = []
            self.patchModeShouldFail = patchModeShouldFail
            self.tunEnabled = tunEnabled
            self.reloadConfigShouldFail = reloadConfigShouldFail
            self.versionFailureCount = versionFailureCount
            self.groupDelayShouldFail = groupDelayShouldFail
            self.proxyDelayResults = proxyDelayResults
            self.disabledRuleIndexes = disabledRuleIndexes
            self.ruleDisableShouldFail = ruleDisableShouldFail
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

    func setTunEnabled(_ enabled: Bool) {
        lock.withLock {
            tunEnabled = enabled
        }
    }

    func setRuleDisabled(index: Int, disabled: Bool) {
        lock.withLock {
            if disabled {
                disabledRuleIndexes.insert(index)
            } else {
                disabledRuleIndexes.remove(index)
            }
        }
    }

    func consumeVersionFailure() -> Bool {
        lock.withLock {
            guard versionFailureCount > 0 else { return false }
            versionFailureCount -= 1
            return true
        }
    }

    func snapshot() -> (
        mode: String,
        globalNow: String,
        patchModeCalls: [String],
        selectProxyCalls: [(group: String, name: String)],
        handledRequests: [(method: String, path: String)],
        patchModeShouldFail: Bool,
        tunEnabled: Bool,
        reloadConfigShouldFail: Bool,
        versionFailureCount: Int,
        groupDelayShouldFail: Bool,
        proxyDelayResults: [String: Int],
        disabledRuleIndexes: Set<Int>,
        ruleDisableShouldFail: Bool
    ) {
        lock.withLock {
            (
                mode,
                globalNow,
                patchModeCalls,
                selectProxyCalls,
                handledRequests,
                patchModeShouldFail,
                tunEnabled,
                reloadConfigShouldFail,
                versionFailureCount,
                groupDelayShouldFail,
                proxyDelayResults,
                disabledRuleIndexes,
                ruleDisableShouldFail
            )
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

    static var disabledRuleIndexes: Set<Int> {
        MockMihomoStore.shared.snapshot().disabledRuleIndexes
    }

    static func setRuntimeTunEnabled(_ enabled: Bool) {
        MockMihomoStore.shared.setTunEnabled(enabled)
    }

    static func reset(
        mode: String = "rule",
        globalNow: String = "Tokyo-01",
        patchModeShouldFail: Bool = false,
        tunEnabled: Bool = false,
        reloadConfigShouldFail: Bool = false,
        versionFailureCount: Int = 0,
        groupDelayShouldFail: Bool = false,
        proxyDelayResults: [String: Int] = [:],
        disabledRuleIndexes: Set<Int> = [],
        ruleDisableShouldFail: Bool = false
    ) {
        MockMihomoStore.shared.reset(
            mode: mode,
            globalNow: globalNow,
            patchModeShouldFail: patchModeShouldFail,
            tunEnabled: tunEnabled,
            reloadConfigShouldFail: reloadConfigShouldFail,
            versionFailureCount: versionFailureCount,
            groupDelayShouldFail: groupDelayShouldFail,
            proxyDelayResults: proxyDelayResults,
            disabledRuleIndexes: disabledRuleIndexes,
            ruleDisableShouldFail: ruleDisableShouldFail
        )
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
                if store.consumeVersionFailure() {
                    try respond(statusCode: 503, data: Data("controller not ready".utf8))
                    return
                }
                try respond(json: ["version": "test", "premium": true, "meta": true])
                return
            }
            if method == "GET", path.hasSuffix("/configs") || path == "/configs" {
                let snapshot = store.snapshot()
                try respond(json: Self.configPayload(mode: snapshot.mode, tunEnabled: snapshot.tunEnabled))
                return
            }
            if method == "PUT", path.hasSuffix("/configs") || path == "/configs" {
                if store.snapshot().reloadConfigShouldFail {
                    try respond(statusCode: 500, data: Data("config reload failed".utf8))
                    return
                }
                if let body = request.httpBody ?? request.httpBodyStream.flatMap(readBody(from:)),
                   let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                   let path = object["path"] as? String {
                    let yaml = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                    store.setTunEnabled(Self.yamlTunEnabled(yaml))
                }
                try respond(statusCode: 204, data: Data())
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
            if method == "GET", path.contains("/group/"), path.hasSuffix("/delay") {
                if store.snapshot().groupDelayShouldFail, path.contains("/group/GLOBAL/") {
                    try respond(statusCode: 404, data: Data("group delay unavailable".utf8))
                    return
                }
                try respond(json: [
                    "HK-01": 120,
                    "JP-02": ["delay": 88],
                    "timeout-node": ["message": "timeout"]
                ])
                return
            }
            if method == "GET", path.contains("/proxies/"), path.hasSuffix("/delay") {
                let encodedName = path
                    .replacingOccurrences(of: "/proxies/", with: "")
                    .replacingOccurrences(of: "/delay", with: "")
                let name = encodedName.removingPercentEncoding ?? encodedName
                let results = store.snapshot().proxyDelayResults
                guard let delay = results[name] else {
                    try respond(statusCode: 404, data: Data("proxy delay unavailable".utf8))
                    return
                }
                try respond(json: ["delay": delay])
                return
            }
            if method == "GET", path.hasSuffix("/connections") || path == "/connections" {
                try respond(json: ["downloadTotal": 0, "uploadTotal": 0, "connections": []])
                return
            }
            if method == "GET", path.hasSuffix("/providers/rules") || path == "/providers/rules" {
                try respond(json: Self.ruleProvidersPayload())
                return
            }
            if method == "PUT", path.contains("/providers/rules/") {
                try respond(statusCode: 204, data: Data())
                return
            }
            if method == "GET", path.hasSuffix("/rules") || path == "/rules" {
                try respond(json: Self.rulesPayload(disabledRuleIndexes: store.snapshot().disabledRuleIndexes))
                return
            }
            if method == "PATCH", path.hasSuffix("/rules/disable") || path == "/rules/disable" {
                if store.snapshot().ruleDisableShouldFail {
                    try respond(statusCode: 500, data: Data("rule disable failed".utf8))
                    return
                }
                if let body = request.httpBody ?? request.httpBodyStream.flatMap(readBody(from:)),
                   let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
                    for (key, value) in object {
                        guard let index = Int(key), let disabled = value as? Bool else { continue }
                        store.setRuleDisabled(index: index, disabled: disabled)
                    }
                }
                try respond(statusCode: 204, data: Data())
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

    private static func yamlTunEnabled(_ yaml: String) -> Bool {
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false)
        var inTun = false
        for line in lines {
            let text = String(line)
            if text == "tun:" {
                inTun = true
                continue
            }
            if inTun, !text.hasPrefix(" "), !text.hasPrefix("\t") {
                return false
            }
            if inTun {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed == "enable: true" {
                    return true
                }
                if trimmed == "enable: false" {
                    return false
                }
            }
        }
        return false
    }

    private static func configPayload(mode: String, tunEnabled: Bool) -> [String: Any] {
        [
            "port": 7890,
            "mixed-port": 7890,
            "mode": mode,
            "log-level": "info",
            "allow-lan": false,
            "external-controller": "127.0.0.1:9090",
            "tun": ["enable": tunEnabled]
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

    private static func rulesPayload(disabledRuleIndexes: Set<Int>) -> [String: Any] {
        [
            "rules": [
                [
                    "type": "DOMAIN-SUFFIX",
                    "payload": "example.com",
                    "proxy": "Proxy",
                    "size": 0,
                    "extra": [
                        "disabled": disabledRuleIndexes.contains(0),
                        "hitCount": 4,
                        "missCount": 1,
                        "hitAt": "2026-07-05T12:00:00+08:00",
                        "missAt": "2026-07-05T11:59:00+08:00"
                    ]
                ],
                [
                    "type": "MATCH",
                    "payload": "",
                    "proxy": "DIRECT",
                    "size": 0,
                    "extra": [
                        "disabled": disabledRuleIndexes.contains(1),
                        "hitCount": 0,
                        "missCount": 0
                    ]
                ]
            ]
        ]
    }

    private static func ruleProvidersPayload() -> [String: Any] {
        [
            "providers": [
                "RejectSet": [
                    "name": "RejectSet",
                    "behavior": "domain",
                    "vehicleType": "HTTP",
                    "format": "yaml",
                    "ruleCount": 12,
                    "updatedAt": "2026-07-05T12:00:00+08:00",
                    "path": "/tmp/reject.yaml"
                ]
            ]
        ]
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
