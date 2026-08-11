import Foundation

struct InternetLatencySnapshot: Equatable, Sendable {
    var internetMs: Int?
    var routerMs: Int?
    var dnsMs: Int?
    var entries: [InternetDiagnosticEntry]
    var measuredAt: Date?

    static let empty = InternetLatencySnapshot(
        internetMs: nil,
        routerMs: nil,
        dnsMs: nil,
        entries: [],
        measuredAt: nil
    )

    var internetText: String {
        Self.text(for: internetMs)
    }

    var routerText: String {
        Self.text(for: routerMs)
    }

    var dnsText: String {
        Self.text(for: dnsMs)
    }

    private static func text(for value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value) ms"
    }
}

struct InternetDiagnosticEntry: Equatable, Sendable, Identifiable {
    enum Level: String, Equatable, Sendable {
        case success
        case warning
        case info
    }

    let id: String
    let title: String
    let message: String
    let level: Level

    init(title: String, message: String, level: Level) {
        self.id = "\(title)-\(message)-\(level.rawValue)"
        self.title = title
        self.message = message
        self.level = level
    }
}

struct InternetLatencyConfiguration: Equatable, Sendable {
    var httpTestURLs: [URL]
    var dnsDomain: String
    var timeoutSeconds: Int

    init(httpTestURLs: [URL], dnsDomain: String, timeoutSeconds: Int) {
        self.httpTestURLs = httpTestURLs
        self.dnsDomain = dnsDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "bing.com" : dnsDomain
        self.timeoutSeconds = min(max(timeoutSeconds, 1), 10)
    }
}

enum InternetLatencyDiagnostics {
    static let defaultHTTPTestURLs = [
        URL(string: "https://www.apple.com/library/test/success.html")!,
        URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!,
        URL(string: "https://github.com/")!
    ]

    static func measure(configuration: InternetLatencyConfiguration) async -> InternetLatencySnapshot {
        async let internet = measureInternetLatency(
            urls: configuration.httpTestURLs,
            timeoutSeconds: TimeInterval(configuration.timeoutSeconds)
        )
        async let router = measureRouterDiagnostic(timeoutSeconds: configuration.timeoutSeconds)
        async let dns = measureDNSDiagnostic(domain: configuration.dnsDomain, timeoutSeconds: configuration.timeoutSeconds)
        async let direct = measureDirectHTTPDiagnostic(
            url: configuration.httpTestURLs.first ?? defaultHTTPTestURLs[0],
            timeoutSeconds: TimeInterval(configuration.timeoutSeconds)
        )

        let routerResult = await router
        let dnsResult = await dns
        let directResult = await direct
        let entries = [
            routerResult.entry,
            dnsResult.entry,
            directResult
        ]

        return await InternetLatencySnapshot(
            internetMs: internet,
            routerMs: routerResult.latency,
            dnsMs: dnsResult.latency,
            entries: entries,
            measuredAt: Date()
        )
    }

    static func measureInternetLatency(
        urls: [URL] = defaultHTTPTestURLs,
        timeoutSeconds: TimeInterval = 3
    ) async -> Int? {
        let results = await withTaskGroup(of: Int?.self) { group in
            for url in urls {
                group.addTask {
                    await measureHTTPHeadLatency(url: url, timeoutSeconds: timeoutSeconds)
                }
            }

            var values: [Int] = []
            for await value in group {
                if let value {
                    values.append(value)
                }
            }
            return values
        }

        guard !results.isEmpty else { return nil }
        return Int((Double(results.reduce(0, +)) / Double(results.count)).rounded())
    }

    static func measureHTTPHeadLatency(url: URL, timeoutSeconds: TimeInterval = 3) async -> Int? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeoutSeconds

        let start = ContinuousClock.now
        do {
            _ = try await URLSession.shared.data(for: request)
            let duration = start.duration(to: ContinuousClock.now)
            return Int(Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1.0e15)
        } catch {
            return nil
        }
    }

    static func measureRouterLatency(timeoutSeconds: Int = 3) -> Int? {
        measureRouterDiagnostic(timeoutSeconds: timeoutSeconds).latency
    }

    static func measureRouterDiagnostic(timeoutSeconds: Int = 3) -> (latency: Int?, entry: InternetDiagnosticEntry) {
        guard let routeOutput = try? runCapture(executable: "/sbin/route", arguments: ["-n", "get", "default"]),
              let gateway = parseDefaultGateway(from: routeOutput) else {
            return (nil, InternetDiagnosticEntry(title: "路由器", message: "未找到默认网关", level: .warning))
        }
        guard let pingOutput = try? runCapture(
                executable: "/sbin/ping",
                arguments: ["-c", "1", "-W", "\(timeoutSeconds * 1000)", gateway]
              ),
              let latency = parsePingLatency(from: pingOutput) else {
            return (nil, InternetDiagnosticEntry(title: "路由器", message: "Ping \(gateway) 失败", level: .warning))
        }
        return (
            latency,
            InternetDiagnosticEntry(title: "路由器", message: "Ping \(gateway): \(latency) ms", level: .success)
        )
    }

    static func measureDNSLatency(domain: String = "bing.com", timeoutSeconds: Int = 3) -> Int? {
        measureDNSDiagnostic(domain: domain, timeoutSeconds: timeoutSeconds).latency
    }

    static func measureDNSDiagnostic(domain: String = "bing.com", timeoutSeconds: Int = 3) -> (latency: Int?, entry: InternetDiagnosticEntry) {
        let domain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty,
              let output = try? runCapture(
                executable: "/usr/bin/dig",
                arguments: ["+time=\(timeoutSeconds)", "+tries=1", domain, "A"]
              ) else {
            return (nil, InternetDiagnosticEntry(title: "测试 DNS", message: "查询 \(domain.isEmpty ? "默认域名" : domain) 失败", level: .warning))
        }
        guard let latency = parseDigQueryTime(from: output) else {
            return (nil, InternetDiagnosticEntry(title: "测试 DNS", message: "未收到 \(domain) 的有效应答", level: .warning))
        }
        return (
            latency,
            InternetDiagnosticEntry(title: "测试 DNS", message: "收到 \(domain) 的应答: \(latency) ms", level: .success)
        )
    }

    static func measureDirectHTTPDiagnostic(url: URL, timeoutSeconds: TimeInterval = 3) async -> InternetDiagnosticEntry {
        if let latency = await measureHTTPHeadLatency(url: url, timeoutSeconds: timeoutSeconds) {
            return InternetDiagnosticEntry(
                title: "测试直连策略",
                message: "直接连接到 \(url.absoluteString): \(latency) ms",
                level: .success
            )
        }
        return InternetDiagnosticEntry(
            title: "测试直连策略",
            message: "直接连接到 \(url.absoluteString) 失败",
            level: .warning
        )
    }

    static func parseDefaultGateway(from output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.hasPrefix("gateway:") })?
            .split(separator: " ", maxSplits: 1)
            .last
            .map(String.init)
    }

    static func parsePingLatency(from output: String) -> Int? {
        guard let range = output.range(of: #"time=([0-9]+(?:\.[0-9]+)?)\s*ms"#, options: .regularExpression) else {
            return nil
        }
        let match = String(output[range])
        guard let valueRange = match.range(of: #"[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression),
              let value = Double(match[valueRange]) else {
            return nil
        }
        return Int(value.rounded())
    }

    static func parseDigQueryTime(from output: String) -> Int? {
        guard let range = output.range(of: #"Query time:\s*([0-9]+)\s*msec"#, options: .regularExpression) else {
            return nil
        }
        let match = String(output[range])
        guard let valueRange = match.range(of: #"[0-9]+"#, options: .regularExpression),
              let value = Int(match[valueRange]) else {
            return nil
        }
        return value
    }

    private static func runCapture(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw URLError(.cannotConnectToHost)
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct LocalDNSSnapshot: Equatable, Sendable {
    let summary: String
    let hasNameServers: Bool
}

private struct LocalDNSResolverInfo {
    var isScoped: Bool
    var interfaceName: String?
    var domains: [String] = []
    var searchDomains: [String] = []
    var servers: [String] = []

    func displayLabel(tailscaleInterfaceNames: Set<String>) -> String {
        let target: String
        if !domains.isEmpty {
            target = domains.joined(separator: ", ")
        } else if !searchDomains.isEmpty {
            target = "搜索域 \(searchDomains.joined(separator: ", "))"
        } else {
            target = "默认"
        }

        guard isScoped else { return "系统解析 \(target)" }
        guard let interfaceName else { return "接口 \(target)" }
        if tailscaleInterfaceNames.contains(interfaceName) {
            return "Tailscale（\(interfaceName)） \(target)"
        }
        return "接口 \(interfaceName) \(target)"
    }
}

enum LocalDNSDiagnostics {
    static func current() -> LocalDNSSnapshot {
        var summaries: [String] = []
        var hasNameServers = false

        if let service = try? SystemProxyController().activeNetworkService() {
            let output = try? runCapture(
                executable: "/usr/sbin/networksetup",
                arguments: ["-getdnsservers", service]
            )
            let servers = networkServiceDNSServers(from: output ?? "")
            hasNameServers = !servers.isEmpty
            summaries.append(
                servers.isEmpty
                    ? "\(service)：未设置 DNS"
                    : "\(service)：\(servers.joined(separator: ", "))"
            )
        }

        if let output = try? runCapture(executable: "/usr/sbin/scutil", arguments: ["--dns"]) {
            let resolverSummaries = resolverSummaries(
                from: output,
                tailscaleInterfaceNames: currentTailscaleInterfaceNames()
            )
            hasNameServers = hasNameServers || !resolverSummaries.isEmpty
            summaries.append(contentsOf: resolverSummaries)
        }

        let uniqueSummaries = summaries.reduce(into: [String]()) { result, summary in
            guard !result.contains(summary) else { return }
            result.append(summary)
        }
        return LocalDNSSnapshot(
            summary: uniqueSummaries.isEmpty ? "未找到当前设备的 DNS 信息" : uniqueSummaries.joined(separator: "\n"),
            hasNameServers: hasNameServers
        )
    }

    static func networkServiceDNSServers(from output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty
                    && !$0.hasPrefix("There aren't any DNS Servers set on")
            }
    }

    static func resolverSummaries(
        from output: String,
        tailscaleInterfaceNames: Set<String> = []
    ) -> [String] {
        var isScopedSection = false
        var current: LocalDNSResolverInfo?
        var resolvers: [LocalDNSResolverInfo] = []

        func finishCurrentResolver() {
            guard let current else { return }
            resolvers.append(current)
        }

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "DNS configuration (for scoped queries)" {
                finishCurrentResolver()
                current = nil
                isScopedSection = true
                continue
            }
            if line.hasPrefix("resolver #") {
                finishCurrentResolver()
                current = LocalDNSResolverInfo(isScoped: isScopedSection)
                continue
            }
            guard current != nil else { continue }

            if line.hasPrefix("domain") {
                if let value = valueAfterColon(in: line) {
                    current?.domains.append(value)
                }
            } else if line.hasPrefix("search domain[") {
                if let value = valueAfterColon(in: line) {
                    current?.searchDomains.append(value)
                }
            } else if line.hasPrefix("nameserver[") {
                if let value = valueAfterColon(in: line) {
                    current?.servers.append(value)
                }
            } else if line.hasPrefix("if_index") {
                current?.interfaceName = parenthesizedValue(in: line)
            }
        }
        finishCurrentResolver()

        var seen = Set<String>()
        return resolvers.compactMap { resolver in
            guard !resolver.servers.isEmpty else { return nil }
            let label = resolver.displayLabel(tailscaleInterfaceNames: tailscaleInterfaceNames)
            let summary = "\(label)：\(resolver.servers.joined(separator: ", "))"
            guard seen.insert(summary).inserted else { return nil }
            return summary
        }
    }

    private static func currentTailscaleInterfaceNames() -> Set<String> {
        guard let output = try? runCapture(executable: "/sbin/ifconfig", arguments: ["-l"]) else {
            return []
        }
        return Set(output.split(whereSeparator: \.isWhitespace).map(String.init).filter { interfaceName in
            guard interfaceName.hasPrefix("utun"),
                  let interface = try? runCapture(executable: "/sbin/ifconfig", arguments: [interfaceName]) else {
                return false
            }
            return interface.components(separatedBy: .newlines).contains { rawLine in
                let fields = rawLine.split(whereSeparator: \.isWhitespace)
                guard fields.count > 1 else { return false }
                let kind = fields[0]
                let address = String(fields[1]).lowercased()
                return (kind == "inet" && isTailscaleIPv4Address(address))
                    || (kind == "inet6" && address.hasPrefix("fd7a:115c:a1e0:"))
            }
        })
    }

    private static func isTailscaleIPv4Address(_ address: String) -> Bool {
        let octets = address.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 100 && (64...127).contains(octets[1])
    }

    private static func valueAfterColon(in line: String) -> String? {
        guard let range = line.range(of: ":") else { return nil }
        let value = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func parenthesizedValue(in line: String) -> String? {
        guard let start = line.firstIndex(of: "("),
              let end = line[start...].firstIndex(of: ")") else {
            return nil
        }
        let value = line[line.index(after: start)..<end]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func runCapture(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw URLError(.cannotConnectToHost)
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
