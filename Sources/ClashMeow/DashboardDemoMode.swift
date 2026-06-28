import AppKit
import Foundation
import SwiftUI

enum DashboardDemoMode {
    static let launchFlag = "-dashboardDemo"
    static let screenshotFlag = "-exportDashboardScreenshot"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchFlag)
    }

    static var screenshotURL: URL? {
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: screenshotFlag),
              index + 1 < ProcessInfo.processInfo.arguments.count else {
            return nil
        }
        return URL(fileURLWithPath: ProcessInfo.processInfo.arguments[index + 1])
    }

    @MainActor
    static func exportRenderedScreenshot(to url: URL, state: AppState) -> Bool {
        let content = RootView()
            .environmentObject(state)
            .frame(width: 1040, height: 720)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

enum DashboardDemoData {
    static let mockProfileID = "debug-mock-overview"
    static let mockProfileName = "Clash Meow"
    static let mockSubscriptionUserInfo = SubscriptionUserInfo(
        upload: 0,
        download: 520 * 1_024 * 1_024 * 1_024,
        total: 1_000 * 1_024 * 1_024 * 1_024,
        expire: nil
    )

    static let mockProfileYAML = """
    mixed-port: 7890
    allow-lan: true
    mode: rule
    log-level: info
    ipv6: false
    find-process-mode: always
    external-controller: 127.0.0.1:9090
    secret: ""

    tun:
      enable: true
      stack: system
      device: utun10

    proxies:
      - name: Tokyo-01
        type: vmess
        server: jp.example.com
        port: 443
      - name: Singapore-02
        type: trojan
        server: sg.example.com
        port: 443
      - name: Los Angeles-03
        type: ss
        server: us.example.com
        port: 8388
      - name: Hong Kong-04
        type: hysteria2
        server: hk.example.com
        port: 443

    proxy-groups:
      - name: Proxy
        type: select
        proxies:
          - Tokyo-01
          - Singapore-02
          - Los Angeles-03
          - Hong Kong-04
          - DIRECT
      - name: GLOBAL
        type: select
        proxies:
          - Tokyo-01
          - Singapore-02
          - Los Angeles-03
          - Hong Kong-04
          - DIRECT

    rules:
      - DOMAIN-SUFFIX,apple.com,DIRECT
      - DOMAIN-SUFFIX,openai.com,Proxy
      - GEOIP,CN,DIRECT
      - MATCH,Proxy
    """

    @MainActor
    static func apply(to state: AppState) {
        state.core.applyDemoPresentation()

        state.version = MihomoVersion(version: "1.19.0", premium: true, meta: true)
        state.config = demoConfig
        state.activeProfileConfig = demoConfig
        state.forwardingMode = .rule
        state.allowLan = true
        state.setDemoPresentationFlags(systemProxyEnabled: true)

        state.toggles = [
            .init(id: "dns", title: "DNS", subtitle: "DNS 解析与 nameserver 配置状态。", systemImage: "network", isOn: true),
            .init(id: "allowLan", title: "允许局域网访问", subtitle: "允许局域网设备连接本机混合端口。", systemImage: "rectangle.connected.to.line.below", isOn: true),
            .init(id: "proxy", title: "系统代理", subtitle: "将系统网络设置指向本机混合端口。", systemImage: "globe", isOn: true),
            .init(id: "tun", title: "TUN", subtitle: "系统栈、自动路由与虚拟网卡。", systemImage: "antenna.radiowaves.left.and.right", isOn: true)
        ]

        state.traffic = TrafficSnapshot(
            up: 18_432,
            down: 57_344,
            upTotal: 52_428_800,
            downTotal: 472_408_422
        )
        state.trafficHistory = makeTrafficHistory()
        state.connections = makeConnections()
        state.profiles = [demoProfile]
        state.activeProfileProxyGroups = demoProxyGroups
        state.activeProfileNodes = demoNodes
        state.proxyGroups = demoProxyGroups
        state.proxyNodeStatuses = demoProxyStatuses
    }

    private static let clientTraffic: [(name: String, bytes: Int)] = [
        ("codex", 316_416),
        ("Telegram", 287_232),
        ("mihomo", 198_656),
        ("Lark Helper", 145_408),
        ("Google Chrome Helper", 101_376)
    ]

    private static let extraProcesses = [
        "Cursor Helper",
        "WeChat",
        "Safari",
        "Music",
        "Spotify",
        "Slack Helper",
        "Docker",
        "node",
        "Python",
        "backupd"
    ]

    private static let totalTrafficBytes = 524_837_222

    private static var demoConfig: MihomoConfig {
        MihomoConfig(
            port: 7890,
            socksPort: 7891,
            mixedPort: 7890,
            redirPort: nil,
            tproxyPort: nil,
            mode: "rule",
            logLevel: "info",
            allowLan: true,
            ipv6: false,
            interfaceName: nil,
            tun: TunConfig(enable: true, stack: "system", device: "utun10"),
            externalController: "127.0.0.1:9090",
            secret: nil
        )
    }

    private static var demoProfile: ClashMeowProfileSummary {
        ClashMeowProfileSummary(
            id: "demo-premium",
            name: "Premium Subscription",
            fileURL: URL(fileURLWithPath: "/tmp/clash-meow/demo-config.yaml"),
            sourceDescription: "https://example.com/subscription",
            updatedAt: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 28)),
            isCurrent: true,
            kind: .remote,
            remoteURL: URL(string: "https://example.com/subscription"),
            useProxy: false,
            subscriptionUserInfo: SubscriptionUserInfo(
                upload: 52_428_800,
                download: 472_408_422,
                total: 1_073_741_824,
                expire: 1_787_155_200
            )
        )
    }

    private static var demoNodes: [ProxyNodeInfo] {
        [
            ProxyNodeInfo(name: "Tokyo-01", type: "vmess", server: "jp.example.com", port: 443),
            ProxyNodeInfo(name: "Singapore-02", type: "trojan", server: "sg.example.com", port: 443),
            ProxyNodeInfo(name: "Los Angeles-03", type: "shadowsocks", server: "us.example.com", port: 8388),
            ProxyNodeInfo(name: "Hong Kong-04", type: "hysteria2", server: "hk.example.com", port: 443)
        ]
    }

    private static var demoProxyGroups: [ProxyGroupItem] {
        [
            ProxyGroupItem(
                id: "GLOBAL",
                name: "GLOBAL",
                type: "select",
                now: "Tokyo-01",
                all: demoNodes.map(\.name),
                nodes: demoNodes.map {
                    ProxyGroupNode(
                        name: $0.name,
                        type: $0.type,
                        delay: demoProxyStatuses[$0.name]?.delay,
                        alive: demoProxyStatuses[$0.name]?.alive
                    )
                },
                aliveCount: demoNodes.count,
                testURL: "http://www.gstatic.com/generate_204"
            )
        ]
    }

    private static var demoProxyStatuses: [String: ProxyNodeRuntimeStatus] {
        [
            "Tokyo-01": ProxyNodeRuntimeStatus(delay: 47, alive: true),
            "Singapore-02": ProxyNodeRuntimeStatus(delay: 63, alive: true),
            "Los Angeles-03": ProxyNodeRuntimeStatus(delay: 182, alive: true),
            "Hong Kong-04": ProxyNodeRuntimeStatus(delay: 58, alive: true)
        ]
    }

    private static func makeTrafficHistory() -> [TrafficSample] {
        let samples = [12, 18, 24, 31, 28, 36, 42, 38, 45, 52, 48, 55, 50, 44, 39, 33, 27, 22, 18, 24, 30, 36, 41, 47]
        let now = Date()
        return samples.enumerated().map { index, total in
            TrafficSample(
                timestamp: now.addingTimeInterval(TimeInterval(index - samples.count) * 2),
                upload: max(1, total / 4),
                download: max(2, total)
            )
        }
    }

    private static func makeConnections() -> ConnectionsSnapshot {
        var connections: [MihomoConnection] = []
        var identifier = 0

        func appendConnection(process: String, upload: Int, download: Int) {
            identifier += 1
            connections.append(
                MihomoConnection(
                    id: "demo-\(identifier)",
                    metadata: ConnectionMetadata(
                        host: "example.com",
                        destinationIP: "198.51.100.\(identifier % 200 + 1)",
                        destinationPort: "443",
                        network: "tcp",
                        process: process,
                        processPath: "/Applications/\(process).app/Contents/MacOS/\(process)",
                        sniffHost: nil,
                        type: "HTTP"
                    ),
                    chains: ["Tokyo-01", "GLOBAL"],
                    rule: "Match",
                    rulePayload: "",
                    upload: upload,
                    download: download
                )
            )
        }

        for (process, bytes) in clientTraffic {
            appendConnection(process: process, upload: bytes / 5, download: bytes)
        }

        let fillerProcesses = extraProcesses + clientTraffic.map(\.name)
        while connections.count < 64 {
            let process = fillerProcesses[connections.count % fillerProcesses.count]
            appendConnection(process: process, upload: 4_096, download: 12_288)
        }

        return ConnectionsSnapshot(
            downloadTotal: totalTrafficBytes,
            uploadTotal: totalTrafficBytes / 10,
            connections: connections
        )
    }
}
