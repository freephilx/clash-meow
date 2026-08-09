import Foundation

struct MihomoAPI {
    static let maximumLogEntryBytes = 1 * 1_024 * 1_024
    var baseURL = URL(string: "http://127.0.0.1:9090")!
    var secret = ""
    var urlSession: URLSession = MihomoAPI.makeDefaultSession()
    private static let defaultDelayTestURL = "https://www.gstatic.com/generate_204"
    static let fallbackProxyDelayTimeoutMs = 5_000
    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 10
        configuration.httpMaximumConnectionsPerHost = 32
        return URLSession(configuration: configuration)
    }

    static func makeMockSession(protocolClass: AnyClass) -> URLSession {
        URLProtocol.registerClass(protocolClass)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolClass]
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 10
        configuration.httpMaximumConnectionsPerHost = 32
        return URLSession(configuration: configuration)
    }

    static func recommendedGroupDelayTimeoutMs(nodeCount: Int) -> Int {
        min(60_000, max(8_000, nodeCount * 400))
    }

    func version() async throws -> MihomoVersion {
        try await get("version")
    }

    func configs() async throws -> MihomoConfig {
        try await get("configs")
    }

    func connections() async throws -> ConnectionsSnapshot {
        try await get("connections")
    }

    func traffic() async throws -> TrafficSnapshot {
        let object = try await getJSONObject("traffic")
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8),
              let snapshot = TrafficSnapshot.parsed(from: text) else {
            return TrafficSnapshot()
        }
        return snapshot
    }

    func trafficStream() -> AsyncThrowingStream<TrafficSnapshot, Error> {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = "ws"
        components.path = "/traffic"
        var request = URLRequest(url: components.url!)
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }

        return streamWebSocket(
            request: request,
            parser: { TrafficSnapshot.parsed(from: $0) },
            idleValue: TrafficSnapshot()
        )
    }

    func proxies() async throws -> ProxiesResponse {
        try await get("proxies")
    }

    func rules() async throws -> [RuleItem] {
        let root = try await getJSONObject("rules")
        if let rules = root["rules"] as? [[String: Any]] {
            return rules.enumerated().map { index, rule in
                Self.ruleItem(from: rule, index: index)
            }
        }
        if let rules = root["rules"] as? [String: Any] {
            return rules.compactMap { key, value in
                guard let rule = value as? [String: Any], let index = Int(key) else { return nil }
                return Self.ruleItem(from: rule, index: index)
            }
            .sorted { $0.index < $1.index }
        }
        return []
    }

    func ruleProviders() async throws -> [RuleProviderItem] {
        let root = try await getJSONObject("providers/rules")
        let providers = root["providers"] as? [String: Any] ?? [:]
        return providers.compactMap { name, value in
            guard let object = value as? [String: Any] else { return nil }
            return RuleProviderItem(
                name: object["name"] as? String ?? name,
                behavior: object["behavior"] as? String,
                vehicleType: object["vehicleType"] as? String ?? object["type"] as? String,
                format: object["format"] as? String,
                ruleCount: Self.intValue(object["ruleCount"]) ?? Self.intValue(object["size"]),
                updatedAt: object["updatedAt"] as? String ?? object["updated"] as? String,
                path: object["path"] as? String
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func updateMode(_ mode: MihomoMode) async throws {
        try await patchConfigs(["mode": EncodableValue(mode.mihomoValue)])
    }

    func updateAllowLan(_ isEnabled: Bool) async throws {
        try await patchConfigs(["allow-lan": EncodableValue(isEnabled)])
    }

    func reloadConfig(path: URL) async throws {
        var components = URLComponents(url: baseURL.appending(path: "configs"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "force", value: "true")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PUT"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(["path": path.path])
        let requestToSend = request
        let (_, response) = try await withTimeout(seconds: 8) {
            try await urlSession.data(for: requestToSend)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func selectProxy(groupName: String, proxyName: String) async throws {
        let url = controllerURL(pathComponents: ["proxies", groupName])
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(["name": EncodableValue(proxyName)])
        let requestToSend = request
        let (_, response) = try await withTimeout(seconds: 5) {
            try await urlSession.data(for: requestToSend)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    static func resolvedDelayTestURL(_ testURL: String?) -> String {
        let trimmed = testURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultDelayTestURL : trimmed
    }

    func proxyDelay(proxyName: String, testURL: String?, timeoutMs: Int = 5000) async throws -> Int? {
        let url = controllerURL(
            pathComponents: ["proxies", proxyName, "delay"],
            queryItems: [
                URLQueryItem(name: "url", value: Self.resolvedDelayTestURL(testURL)),
                URLQueryItem(name: "timeout", value: String(timeoutMs))
            ]
        )
        let requestTimeout = Double(timeoutMs) / 1000 + 3
        let object = try await getJSONObject(url, timeout: requestTimeout)
        return Self.intValue(object["delay"])
    }

    func groupDelay(groupName: String, testURL: String?, timeoutMs: Int = 5000) async throws -> [String: Int] {
        let url = controllerURL(
            pathComponents: ["group", groupName, "delay"],
            queryItems: [
                URLQueryItem(name: "url", value: Self.resolvedDelayTestURL(testURL)),
                URLQueryItem(name: "timeout", value: String(timeoutMs))
            ]
        )
        let requestTimeout = Double(timeoutMs) / 1000 + 8
        let object = try await getJSONObject(url, timeout: requestTimeout)
        return Self.parseDelayMap(object)
    }

    static func parseDelayMap(_ object: [String: Any]) -> [String: Int] {
        object.reduce(into: [:]) { result, entry in
            guard let delay = delayValue(entry.value) else { return }
            result[entry.key] = delay
        }
    }

    static func delayValue(_ value: Any?) -> Int? {
        if let int = intValue(value) {
            return int
        }
        if let object = value as? [String: Any] {
            return intValue(object["delay"])
        }
        return nil
    }

    func setRuleEnabled(index: Int, isEnabled: Bool) async throws {
        try await patchJSONObject(
            baseURL.appending(path: "rules").appending(path: "disable"),
            payload: [String(index): !isEnabled]
        )
    }

    func updateRuleProvider(name: String) async throws {
        try await sendEmpty(controllerURL(pathComponents: ["providers", "rules", name]), method: "PUT")
    }

    func closeConnection(id: String) async throws {
        let url = controllerURL(pathComponents: ["connections", id])
        try await sendEmpty(url, method: "DELETE")
    }

    func closeAllConnections() async throws {
        try await sendEmpty(baseURL.appending(path: "connections"), method: "DELETE")
    }

    func logStream(level: String?) -> AsyncThrowingStream<CoreLogEntry, Error> {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = "ws"
        components.path = "/logs"
        components.queryItems = [
            URLQueryItem(name: "level", value: level?.isEmpty == false ? level : "info"),
            URLQueryItem(name: "format", value: "structured")
        ]
        var request = URLRequest(url: components.url!)
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }

        return singleWebSocketStream(request: request, parser: { Self.logEntry(from: $0) })
    }

    private func singleWebSocketStream<T: Sendable>(
        request: URLRequest,
        parser: @escaping @Sendable (String) -> T?
    ) -> AsyncThrowingStream<T, Error> {
        let socket = urlSession.webSocketTask(with: request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                socket.resume()
                _ = await Self.consumeWebSocket(
                    socket,
                    parser: parser,
                    yield: { continuation.yield($0) }
                )
                socket.cancel(with: .goingAway, reason: nil)
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private func streamWebSocket<T: Sendable>(
        request: URLRequest,
        parser: @escaping @Sendable (String) -> T?,
        idleValue: T? = nil
    ) -> AsyncThrowingStream<T, Error> {
        let session = urlSession
        return AsyncThrowingStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let socket = session.webSocketTask(with: request)
                    socket.resume()

                    let receivedDuringConnection = await Self.consumeWebSocket(
                        socket,
                        parser: parser,
                        yield: { continuation.yield($0) }
                    )

                    socket.cancel(with: .goingAway, reason: nil)
                    if Task.isCancelled { break }

                    if let idleValue, receivedDuringConnection {
                        continuation.yield(idleValue)
                    }

                    guard receivedDuringConnection else { break }

                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch {
                        break
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func consumeWebSocket<T>(
        _ task: URLSessionWebSocketTask,
        parser: (String) -> T?,
        yield: (T) -> Void
    ) async -> Bool {
        var receivedAtLeastOne = false
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                let text: String?
                switch message {
                case .string(let value):
                    text = value
                case .data(let data):
                    text = String(data: data, encoding: .utf8)
                @unknown default:
                    text = nil
                }
                if let text, let parsed = parser(text) {
                    yield(parsed)
                    receivedAtLeastOne = true
                }
            } catch {
                return receivedAtLeastOne
            }
        }
        return receivedAtLeastOne
    }

    private func patchConfigs(_ payload: [String: EncodableValue]) async throws {
        let url = baseURL.appending(path: "configs")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(payload)
        let requestToSend = request
        let (_, response) = try await withTimeout(seconds: 5) {
            try await urlSession.data(for: requestToSend)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func patchJSONObject(_ url: URL, payload: [String: Any]) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let requestToSend = request
        let (_, response) = try await withTimeout(seconds: 5) {
            try await urlSession.data(for: requestToSend)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func sendEmpty(_ url: URL, method: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 5
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        let requestToSend = request
        let (_, response) = try await withTimeout(seconds: 5) {
            try await urlSession.data(for: requestToSend)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appending(path: path)
        return try await get(url)
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 5

        let requestToSend = request
        let (data, response) = try await withTimeout(seconds: 5) {
            try await urlSession.data(for: requestToSend)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func getJSONObject(_ path: String) async throws -> [String: Any] {
        try await getJSONObject(baseURL.appending(path: path))
    }

    private func getJSONObject(_ url: URL, timeout: Double = 2) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        if !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = timeout
        let requestToSend = request
        let (data, response) = try await withTimeout(seconds: timeout) {
            try await urlSession.data(for: requestToSend)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard !data.isEmpty else { return [:] }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    static func logEntry(from text: String) -> CoreLogEntry? {
        guard text.utf8.count <= maximumLogEntryBytes else { return nil }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return CoreLogEntry(level: "info", message: text, rawText: text)
        }
        let level = object["type"] as? String
            ?? object["level"] as? String
            ?? "info"
        let message = object["payload"] as? String
            ?? object["message"] as? String
            ?? text
        return CoreLogEntry(
            id: object["id"] as? String ?? UUID().uuidString,
            level: CoreLogSupport.normalizedLevel(level),
            message: message,
            rawText: text,
            time: LogTimeSupport.displayString(from: object["time"] as? String)
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func ruleItem(from rule: [String: Any], index: Int) -> RuleItem {
        let extra = rule["extra"] as? [String: Any] ?? [:]
        let type = rule["type"] as? String ?? "-"
        let payload = rule["payload"] as? String ?? ""
        return RuleItem(
            id: "\(index)-\(type)-\(payload)",
            index: index,
            type: type,
            payload: payload,
            proxy: rule["proxy"] as? String ?? "-",
            isEnabled: !(extra["disabled"] as? Bool ?? false),
            hitCount: Self.intValue(extra["hitCount"]) ?? 0,
            missCount: Self.intValue(extra["missCount"]) ?? 0,
            lastHit: extra["hitAt"] as? String,
            lastMiss: extra["missAt"] as? String,
            size: Self.intValue(rule["size"]) ?? Self.intValue(extra["size"]) ?? 0
        )
    }

    func controllerURL(pathComponents: [String], queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = "/" + pathComponents.map(Self.percentEncodedPathComponent).joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }

    private static func percentEncodedPathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func withTimeout<T>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: TimeoutResult<T>.self) { group in
            group.addTask {
                TimeoutResult(value: try await operation())
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw URLError(.timedOut)
            }
            let value = try await group.next()!
            group.cancelAll()
            return value.value
        }
    }
}

private struct TimeoutResult<Value>: @unchecked Sendable {
    let value: Value
}

enum EncodableValue: Encodable {
    case string(String)
    case bool(Bool)

    init(_ value: String) {
        self = .string(value)
    }

    init(_ value: Bool) {
        self = .bool(value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }
}
