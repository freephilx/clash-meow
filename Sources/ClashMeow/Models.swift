import Foundation

enum CoreStatus: Equatable {
    case stopped
    case starting
    case running
    case missingBinary
    case failed(String)

    var title: String {
        switch self {
        case .stopped: "已停止"
        case .starting: "连接中"
        case .running: "已连接"
        case .missingBinary: "未安装内核"
        case .failed: "启动失败"
        }
    }

    var isHealthy: Bool {
        if case .running = self { return true }
        return false
    }

    var shouldReloadForProfileChange: Bool {
        switch self {
        case .running, .starting:
            true
        case .stopped, .missingBinary, .failed:
            false
        }
    }
}

enum MihomoMode: String, CaseIterable, Identifiable {
    case direct
    case rule
    case global

    var id: String { rawValue }

    var title: String {
        switch self {
        case .direct: "直连"
        case .rule: "规则"
        case .global: "全局"
        }
    }

    var detail: String {
        switch self {
        case .direct: "所有连接直接出站，不经过节点组规则。"
        case .rule: "按规则匹配节点组与出站线路。"
        case .global: "所有连接使用全局节点组选择。"
        }
    }

    var systemImage: String {
        switch self {
        case .direct: "arrow.right"
        case .rule: "list.bullet.rectangle"
        case .global: "globe"
        }
    }

    var mihomoValue: String { rawValue }
    var displayValue: String { rawValue.uppercased() }

    init(configValue: String?) {
        let value = configValue?.lowercased() ?? ""
        self = MihomoMode(rawValue: value) ?? .rule
    }
}

struct MihomoConfig: Codable, Equatable {
    let port: Int?
    let socksPort: Int?
    let mixedPort: Int?
    let redirPort: Int?
    let tproxyPort: Int?
    let externalController: String?
    let secret: String?
    let mode: String?
    let logLevel: String?
    let allowLan: Bool?
    let ipv6: Bool?
    let interfaceName: String?
    let tun: TunConfig?

    init(
        port: Int?,
        socksPort: Int?,
        mixedPort: Int?,
        redirPort: Int?,
        tproxyPort: Int?,
        mode: String?,
        logLevel: String?,
        allowLan: Bool?,
        ipv6: Bool?,
        interfaceName: String?,
        tun: TunConfig?,
        externalController: String? = nil,
        secret: String? = nil
    ) {
        self.port = port
        self.socksPort = socksPort
        self.mixedPort = mixedPort
        self.redirPort = redirPort
        self.tproxyPort = tproxyPort
        self.externalController = externalController
        self.secret = secret
        self.mode = mode
        self.logLevel = logLevel
        self.allowLan = allowLan
        self.ipv6 = ipv6
        self.interfaceName = interfaceName
        self.tun = tun
    }

    enum CodingKeys: String, CodingKey {
        case port
        case socksPort = "socks-port"
        case mixedPort = "mixed-port"
        case redirPort = "redir-port"
        case tproxyPort = "tproxy-port"
        case externalController = "external-controller"
        case secret
        case mode
        case logLevel = "log-level"
        case allowLan = "allow-lan"
        case ipv6
        case interfaceName = "interface-name"
        case tun
    }
}

extension MihomoConfig {
    var externalControllerURL: URL? {
        guard var value = externalController?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if value.hasPrefix(":") {
            value = "127.0.0.1\(value)"
        }
        if value.contains("://") {
            return URL(string: value)
        }
        return URL(string: "http://\(value)")
    }

    var listeningPorts: Set<Int> {
        var ports = Set<Int>()
        for candidate in [port, socksPort, mixedPort, redirPort, tproxyPort] {
            if let candidate {
                ports.insert(candidate)
            }
        }
        if let controllerPort = externalController.flatMap(Self.portFromHostPort) ?? externalControllerURL?.port {
            ports.insert(controllerPort)
        }
        return ports
    }

    static func listeningPorts(from yaml: String) -> Set<Int> {
        var ports = parsed(from: yaml).listeningPorts
        for listen in yaml.nestedScalarValues(section: "dns", key: "listen") {
            if let port = Self.portFromHostPort(listen) {
                ports.insert(port)
            }
        }
        if yaml.nestedBoolValue(section: "dns", key: "enable") == true,
           !ports.contains(where: { $0 == 53 || $0 == 1053 }),
           yaml.nestedScalarValues(section: "dns", key: "listen").isEmpty {
            ports.insert(1053)
        }
        return ports.filter { (1...65535).contains($0) }
    }

    static func portFromHostPort(_ value: String) -> Int? {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
        guard !trimmed.isEmpty else { return nil }
        if let schemeRange = trimmed.range(of: "://") {
            trimmed.removeSubrange(trimmed.startIndex..<schemeRange.upperBound)
        }
        if let slash = trimmed.firstIndex(of: "/") {
            trimmed = String(trimmed[..<slash])
        }
        if trimmed.hasPrefix(":") {
            return Int(trimmed.dropFirst())
        }
        if trimmed.hasPrefix("["),
           let close = trimmed.firstIndex(of: "]"),
           trimmed.indices.contains(trimmed.index(after: close)),
           trimmed[trimmed.index(after: close)] == ":" {
            return Int(trimmed[trimmed.index(close, offsetBy: 2)...])
        }
        if let colon = trimmed.lastIndex(of: ":") {
            return Int(trimmed[trimmed.index(after: colon)...])
        }
        return Int(trimmed)
    }
}

struct TunConfig: Codable, Equatable {
    let enable: Bool?
    let stack: String?
    let device: String?

    var deviceName: String {
        let value = device?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : "utun"
    }
}

struct MihomoVersion: Codable, Equatable {
    let version: String?
    let premium: Bool?
    let meta: Bool?
}

struct TrafficSnapshot: Equatable, Sendable {
    var up: Int
    var down: Int
    var upTotal: Int
    var downTotal: Int

    init(up: Int = 0, down: Int = 0, upTotal: Int = 0, downTotal: Int = 0) {
        self.up = up
        self.down = down
        self.upTotal = upTotal
        self.downTotal = downTotal
    }

    static func parsed(from text: String) -> TrafficSnapshot? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let uploadSpeed = intValue(object["up"]) ?? intValue(object["upSpeed"]) ?? intValue(object["uploadSpeed"]) ?? 0
        let downloadSpeed = intValue(object["down"]) ?? intValue(object["downSpeed"]) ?? intValue(object["downloadSpeed"]) ?? 0
        let uploadTotal = intValue(object["upTotal"]) ?? 0
        let downloadTotal = intValue(object["downTotal"]) ?? 0
        return TrafficSnapshot(
            up: uploadSpeed,
            down: downloadSpeed,
            upTotal: uploadTotal,
            downTotal: downloadTotal
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

struct ConnectionsSnapshot: Codable, Equatable {
    let downloadTotal: Int?
    let uploadTotal: Int?
    let connections: [MihomoConnection]
}

struct MihomoConnection: Codable, Equatable, Identifiable {
    let id: String
    let metadata: ConnectionMetadata?
    let chains: [String]?
    let rule: String?
    let rulePayload: String?
    let upload: Int?
    let download: Int?
}

struct ConnectionMetadata: Codable, Equatable {
    let host: String?
    let destinationIP: String?
    let destinationPort: String?
    let network: String?
    let process: String?
    let processPath: String?
    let sniffHost: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case host
        case destinationIP = "destinationIP"
        case destinationPort = "destinationPort"
        case network
        case process
        case processPath
        case sniffHost
        case type
    }

    var processName: String {
        if let process, !process.isEmpty {
            return process
        }
        if type == "Inner" {
            return "内核"
        }
        if let processPath, !processPath.isEmpty {
            return (processPath as NSString).lastPathComponent
        }
        return "未知"
    }
}

extension MihomoConnection {
    var displayHost: String {
        if let host = metadata?.host, !host.isEmpty {
            return host
        }
        if let ip = metadata?.destinationIP, !ip.isEmpty {
            if let port = metadata?.destinationPort, !port.isEmpty {
                return "\(ip):\(port)"
            }
            return ip
        }
        return id
    }
}

struct ActivityTrafficRow: Identifiable, Equatable {
    let id: String
    let name: String
    let bytes: Int
}

struct ProxyGroupItem: Identifiable, Equatable {
    let id: String
    let name: String
    let type: String
    let now: String
    let all: [String]
    let nodes: [ProxyGroupNode]
    let aliveCount: Int?
    let testURL: String?
}

struct ProxyGroupNode: Identifiable, Equatable {
    let name: String
    let type: String?
    let delay: Int?
    let alive: Bool?

    var id: String { name }

    var typeText: String {
        guard let type, !type.isEmpty else { return "NODE" }
        return type.uppercased()
    }

    var delayText: String {
        if alive == false {
            return "超时"
        }
        guard let delay else { return "--" }
        if delay <= 0 { return "超时" }
        return "\(delay) ms"
    }
}

struct EventItem: Identifiable, Equatable {
    let id = UUID()
    let time = Date()
    let source: String
    let title: String
    let detail: String
}

struct FeatureToggle: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    var isOn: Bool
}

struct ProxiesResponse: Codable, Equatable {
    let proxies: [String: ProxyNode]
}

struct ProxyNode: Codable, Equatable {
    let name: String?
    let type: String?
    let now: String?
    let all: [String]?
    let alive: Bool?
    let hidden: Bool?
    let testURL: String?
    let history: [ProxyHistory]?

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case now
        case all
        case alive
        case hidden
        case testURL = "testUrl"
        case history
    }
}

struct ProxyNodeInfo: Equatable, Identifiable {
    let name: String
    let type: String?
    let server: String?
    let port: Int?

    var id: String { name }

    var typeLabel: String {
        guard let type, !type.isEmpty else { return "NODE" }
        return type.uppercased()
    }

    var endpointText: String {
        switch (server, port) {
        case (.some(let server), .some(let port)):
            "\(server):\(port)"
        case (.some(let server), .none):
            server
        case (.none, .some(let port)):
            "port \(port)"
        case (.none, .none):
            "配置节点"
        }
    }
}

struct ProxyNodeRuntimeStatus: Equatable {
    let delay: Int?
    let alive: Bool?
}

struct OverviewProxyNode: Equatable, Identifiable {
    let node: ProxyNodeInfo
    let isSelected: Bool
    let delay: Int?

    var id: String {
        "\(node.id)-\(isSelected ? "selected" : "ranked")"
    }

    var detailText: String {
        if isSelected {
            return ["当前选择", delayText].compactMap { $0 }.joined(separator: " · ")
        }
        return [delayText, node.endpointText].compactMap { $0 }.joined(separator: " · ")
    }

    var delayText: String? {
        delay.map { "\($0) ms" }
    }
}

struct ProxyHistory: Codable, Equatable {
    let time: String?
    let delay: Int?
}

enum LogLevelFilter: String, CaseIterable, Identifiable {
    case all
    case error
    case warning
    case info
    case debug

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .error: "错误"
        case .warning: "警告"
        case .info: "信息"
        case .debug: "调试"
        }
    }

    var controllerValue: String? {
        self == .all ? nil : rawValue
    }
}

struct CoreLogEntry: Identifiable, Equatable, Sendable {
    let id: String
    let level: String
    let message: String
    let time: String?

    init(id: String = UUID().uuidString, level: String = "info", message: String, time: String? = nil) {
        self.id = id
        self.level = level
        self.message = message
        self.time = time
    }
}

struct RuleItem: Identifiable, Equatable {
    let id: String
    let index: Int
    let type: String
    let payload: String
    let proxy: String
    var isEnabled: Bool
    let hitCount: Int
    let missCount: Int
    let lastHit: String?
    let lastMiss: String?
    let size: Int

    var hitRate: Double? {
        let total = hitCount + missCount
        guard total > 0 else { return nil }
        return Double(hitCount) / Double(total)
    }
}

extension MihomoConfig {
    static func parsed(from yaml: String) -> MihomoConfig {
        MihomoConfig(
            port: yaml.intValue(for: "port"),
            socksPort: yaml.intValue(for: "socks-port"),
            mixedPort: yaml.intValue(for: "mixed-port"),
            redirPort: yaml.intValue(for: "redir-port"),
            tproxyPort: yaml.intValue(for: "tproxy-port"),
            mode: yaml.scalarValue(for: "mode"),
            logLevel: yaml.scalarValue(for: "log-level"),
            allowLan: yaml.boolValue(for: "allow-lan"),
            ipv6: yaml.boolValue(for: "ipv6"),
            interfaceName: yaml.scalarValue(for: "interface-name"),
            tun: TunConfig(
                enable: yaml.nestedBoolValue(section: "tun", key: "enable"),
                stack: yaml.nestedScalarValue(section: "tun", key: "stack"),
                device: yaml.nestedScalarValue(section: "tun", key: "device")
            ),
            externalController: yaml.scalarValue(for: "external-controller"),
            secret: yaml.scalarValue(for: "secret")
        )
    }
}

extension ProxyNodeInfo {
    static func parsed(from yaml: String) -> [ProxyNodeInfo] {
        var nodes: [ProxyNodeInfo] = []
        var isInsideTopLevelProxies = false
        var current: [String: String] = [:]

        func flushCurrentNode() {
            guard let name = current["name"], !name.isEmpty else {
                current = [:]
                return
            }
            nodes.append(
                ProxyNodeInfo(
                    name: name,
                    type: current["type"],
                    server: current["server"],
                    port: current["port"].flatMap(Int.init)
                )
            )
            current = [:]
        }

        for rawLine in yaml.split(whereSeparator: \.isNewline).map(String.init) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let isTopLevel = !rawLine.hasPrefix(" ") && !rawLine.hasPrefix("\t")

            if isTopLevel {
                if trimmed == "proxies:" {
                    isInsideTopLevelProxies = true
                    continue
                }
                if isInsideTopLevelProxies {
                    break
                }
            }

            guard isInsideTopLevelProxies else { continue }

            if trimmed.hasPrefix("- {"), trimmed.hasSuffix("}") {
                flushCurrentNode()
                current = MihomoInlineYAML.inlineMap(from: trimmed)
                flushCurrentNode()
                continue
            }

            if trimmed.hasPrefix("- name:") {
                flushCurrentNode()
                current["name"] = trimmed.yamlValue(after: "- name:")
                continue
            }

            if trimmed.hasPrefix("- ") {
                flushCurrentNode()
                current["name"] = trimmed.yamlValue(after: "- ")
                continue
            }

            guard let separator = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let valueStart = trimmed.index(after: separator)
            let value = String(trimmed[valueStart...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
            if ["name", "type", "server", "port"].contains(key), !value.isEmpty {
                current[key] = value
            }
        }

        flushCurrentNode()
        return nodes
    }
}

extension ProxyGroupItem {
    static func parsed(from yaml: String) -> [ProxyGroupItem] {
        var groups: [ProxyGroupItem] = []
        let nodeByName = Dictionary(uniqueKeysWithValues: ProxyNodeInfo.parsed(from: yaml).map { ($0.name, $0) })
        var isInsideProxyGroups = false
        var currentName: String?
        var currentType: String?
        var currentProxies: [String] = []
        var isInsideProxies = false

        func flushCurrentGroup() {
            guard let name = currentName else { return }
            let all = currentProxies.isEmpty ? ["DIRECT"] : currentProxies
            groups.append(
                ProxyGroupItem(
                    id: name,
                    name: name,
                    type: currentType ?? "select",
                    now: all.first ?? "DIRECT",
                    all: all,
                    nodes: all.map {
                        ProxyGroupNode(name: $0, type: nodeByName[$0]?.type, delay: nil, alive: nil)
                    },
                    aliveCount: nil,
                    testURL: nil
                )
            )
            currentName = nil
            currentType = nil
            currentProxies = []
            isInsideProxies = false
        }

        for rawLine in yaml.split(whereSeparator: \.isNewline).map(String.init) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            if !rawLine.hasPrefix(" "), !rawLine.hasPrefix("\t") {
                if isInsideProxyGroups, trimmed != "proxy-groups:" {
                    break
                }
                if trimmed == "proxy-groups:" {
                    isInsideProxyGroups = true
                }
                continue
            }

            guard isInsideProxyGroups else { continue }

            if trimmed.hasPrefix("- {"), trimmed.hasSuffix("}") {
                flushCurrentGroup()
                let group = inlineProxyGroup(from: trimmed, nodeByName: nodeByName)
                if let group {
                    groups.append(group)
                }
                continue
            }

            if trimmed.hasPrefix("- name:") {
                flushCurrentGroup()
                currentName = trimmed.yamlValue(after: "- name:")
                currentType = nil
                currentProxies = []
                isInsideProxies = false
                continue
            }

            if trimmed.hasPrefix("name:"), currentName == nil {
                currentName = trimmed.yamlValue(after: "name:")
                continue
            }

            if trimmed.hasPrefix("type:") {
                currentType = trimmed.yamlValue(after: "type:")
                isInsideProxies = false
                continue
            }

            if trimmed == "proxies:" || trimmed == "use:" {
                isInsideProxies = true
                continue
            }

            if isInsideProxies, trimmed.hasPrefix("- ") {
                let proxy = trimmed.yamlValue(after: "- ")
                if !proxy.isEmpty {
                    currentProxies.append(proxy)
                }
            }
        }

        flushCurrentGroup()
        return groups
    }

    private static func inlineProxyGroup(
        from line: String,
        nodeByName: [String: ProxyNodeInfo]
    ) -> ProxyGroupItem? {
        let values = MihomoInlineYAML.inlineMap(from: line)
        guard let name = values["name"], !name.isEmpty else { return nil }
        let all = MihomoInlineYAML.parseInlineArray(values["proxies"] ?? values["use"] ?? "")
        let proxies = all.isEmpty ? ["DIRECT"] : all
        return ProxyGroupItem(
            id: name,
            name: name,
            type: values["type"] ?? "select",
            now: proxies.first ?? "DIRECT",
            all: proxies,
            nodes: proxies.map {
                ProxyGroupNode(name: $0, type: nodeByName[$0]?.type, delay: nil, alive: nil)
            },
            aliveCount: nil,
            testURL: values["url"] ?? values["testUrl"]
        )
    }
}

private extension String {
    func scalarValue(for key: String) -> String? {
        split(whereSeparator: \.isNewline)
            .lazy
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("\(key):") }?
            .yamlValue(after: "\(key):")
    }

    func intValue(for key: String) -> Int? {
        scalarValue(for: key).flatMap(Int.init)
    }

    func boolValue(for key: String) -> Bool? {
        scalarValue(for: key)?.yamlBoolValue
    }

    func nestedScalarValue(section: String, key: String) -> String? {
        nestedScalarValues(section: section, key: key).first
    }

    func nestedScalarValues(section: String, key: String) -> [String] {
        var isInsideSection = false
        var values: [String] = []
        for rawLine in split(whereSeparator: \.isNewline).map(String.init) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(section):") {
                isInsideSection = true
                continue
            }
            if isInsideSection, !rawLine.hasPrefix(" "), !rawLine.hasPrefix("\t") {
                break
            }
            if isInsideSection, trimmed.hasPrefix("\(key):") {
                values.append(trimmed.yamlValue(after: "\(key):"))
            }
        }
        return values
    }

    func nestedBoolValue(section: String, key: String) -> Bool? {
        nestedScalarValue(section: section, key: key)?.yamlBoolValue
    }

    func yamlValue(after prefix: String) -> String {
        let rawValue = replacingOccurrences(of: prefix, with: "")
        let valueWithoutComment = rawValue.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? rawValue
        return valueWithoutComment
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
    }

    var yamlBoolValue: Bool? {
        switch lowercased() {
        case "true", "yes", "on":
            true
        case "false", "no", "off":
            false
        default:
            nil
        }
    }
}
