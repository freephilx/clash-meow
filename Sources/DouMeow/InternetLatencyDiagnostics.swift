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
