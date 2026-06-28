import Foundation
import Testing
@testable import ClashMeow

@MainActor
@Suite(.serialized)
struct AppStateModeProxyTests {
    private func makeConfiguredState(
        mode: String = "rule",
        globalNow: String = "Tokyo-01"
    ) -> AppState {
        MockMihomoURLProtocolSupport.reset(mode: mode, globalNow: globalNow)

        let session = MihomoAPI.makeMockSession(protocolClass: MockMihomoURLProtocol.self)
        var api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)
        api.urlSession = session

        let state = AppState()
        state.useAPIForTesting(api)
        state.core.applyDemoPresentation()
        state.config = MihomoConfig(
            port: 7890,
            socksPort: nil,
            mixedPort: 7890,
            redirPort: nil,
            tproxyPort: nil,
            mode: mode,
            logLevel: "info",
            allowLan: false,
            ipv6: false,
            interfaceName: nil,
            tun: nil,
            externalController: "127.0.0.1:9090",
            secret: nil
        )
        state.activeProfileNodes = Self.sampleNodes
        state.activeProfileProxyGroups = Self.sampleGroups(selected: globalNow)
        state.forwardingMode = MihomoMode(configValue: mode)
        return state
    }

    @Test func mockControllerHandlesModeAndProxyUpdates() async throws {
        MockMihomoURLProtocolSupport.reset()
        let session = MihomoAPI.makeMockSession(protocolClass: MockMihomoURLProtocol.self)
        var api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)
        api.urlSession = session

        try await api.updateMode(.global)
        try await api.selectProxy(groupName: "GLOBAL", proxyName: "Singapore-02")

        #expect(MockMihomoURLProtocolSupport.patchModeCalls.contains("global"))
        #expect(MockMihomoURLProtocolSupport.selectProxyCalls.contains(where: { $0.group == "GLOBAL" && $0.name == "Singapore-02" }))
        #expect(!MockMihomoURLProtocolSupport.handledRequests.isEmpty)
    }

    @Test func overviewProxyNodesPrefersGlobalGroupNow() {
        let overview = AppState.makeOverviewProxyNodes(
            mode: .global,
            groups: [
                ProxyGroupItem(
                    id: "Proxy",
                    name: "Proxy",
                    type: "select",
                    now: "DIRECT",
                    all: ["DIRECT", "Tokyo-01"],
                    nodes: [],
                    aliveCount: 1,
                    testURL: nil
                ),
                ProxyGroupItem(
                    id: "GLOBAL",
                    name: "GLOBAL",
                    type: "select",
                    now: "Singapore-02",
                    all: Self.sampleNodes.map(\.name),
                    nodes: [],
                    aliveCount: 2,
                    testURL: nil
                )
            ],
            profileNodes: Self.sampleNodes,
            statuses: [
                "Tokyo-01": ProxyNodeRuntimeStatus(delay: 47, alive: true),
                "Singapore-02": ProxyNodeRuntimeStatus(delay: 63, alive: true)
            ]
        )

        #expect(overview.first?.node.name == "Singapore-02")
        #expect(overview.first?.isSelected == true)
    }

    @Test func directModeOverviewOnlyShowsDirect() async throws {
        let state = makeConfiguredState(mode: "rule", globalNow: "Tokyo-01")
        #expect(state.overviewProxyNodes.first?.node.name == "Tokyo-01")

        state.setForwardingMode(.direct)
        try await waitForModeUpdate(.direct)

        #expect(state.forwardingMode == .direct)
        #expect(state.overviewProxyNodes.map(\.node.name) == ["DIRECT"])
        #expect(state.overviewProxyNodes.first?.isSelected == true)
    }

    @Test func overviewProxyNodesFollowRuleAndGlobalGroups() {
        let state = makeConfiguredState(mode: "rule", globalNow: "Tokyo-01")
        state.proxyGroups = Self.sampleGroups(selected: "Tokyo-01")
        state.proxyNodeStatuses = [
            "Tokyo-01": ProxyNodeRuntimeStatus(delay: 90, alive: true),
            "Singapore-02": ProxyNodeRuntimeStatus(delay: 0, alive: false),
            "Los Angeles-03": ProxyNodeRuntimeStatus(delay: 40, alive: true)
        ]

        state.forwardingMode = .rule
        #expect(state.overviewProxyNodes.map(\.node.name) == ["Tokyo-01", "Los Angeles-03", "Singapore-02"])
        #expect(state.overviewProxyNodes.first?.isSelected == true)
        #expect(state.overviewProxyNodes[1].delay == 40)

        state.forwardingMode = .global
        #expect(state.overviewProxyNodes.map(\.node.name) == ["Tokyo-01", "Los Angeles-03", "Singapore-02"])
        #expect(state.overviewProxyNodes.first?.isSelected == true)
    }

    @Test func visibleProxyGroupsMatchClashPartyModes() {
        let state = makeConfiguredState(mode: "rule", globalNow: "Tokyo-01")
        state.proxyGroups = Self.sampleGroups(selected: "Tokyo-01")

        state.forwardingMode = .rule
        #expect(!state.visibleProxyGroups.contains(where: { $0.name == "GLOBAL" }))
        #expect(state.visibleProxyGroups.map(\.name) == ["DoriyaNetwork", "Auto"])

        state.forwardingMode = .global
        state.config = state.config.map { config in
            MihomoConfig(
                port: config.port,
                socksPort: config.socksPort,
                mixedPort: config.mixedPort,
                redirPort: config.redirPort,
                tproxyPort: config.tproxyPort,
                mode: "global",
                logLevel: config.logLevel,
                allowLan: config.allowLan,
                ipv6: config.ipv6,
                interfaceName: config.interfaceName,
                tun: config.tun,
                externalController: config.externalController,
                secret: config.secret
            )
        }
        #expect(state.visibleProxyGroups.first?.name == "GLOBAL")
        #expect(state.visibleProxyGroups.map(\.name) == ["GLOBAL", "DoriyaNetwork", "Auto"])

        state.forwardingMode = .direct
        state.config = state.config.map { config in
            MihomoConfig(
                port: config.port,
                socksPort: config.socksPort,
                mixedPort: config.mixedPort,
                redirPort: config.redirPort,
                tproxyPort: config.tproxyPort,
                mode: "direct",
                logLevel: config.logLevel,
                allowLan: config.allowLan,
                ipv6: config.ipv6,
                interfaceName: config.interfaceName,
                tun: config.tun,
                externalController: config.externalController,
                secret: config.secret
            )
        }
        #expect(state.visibleProxyGroups.isEmpty)
    }

    @Test func visibleProxyGroupsFollowRuntimeControllerMode() {
        let state = makeConfiguredState(mode: "global", globalNow: "Tokyo-01")
        state.forwardingMode = .rule
        state.proxyGroups = Array(Self.sampleGroups(selected: "Tokyo-01").reversed())

        #expect(state.effectiveForwardingMode == .global)
        #expect(state.visibleProxyGroups.first?.name == "GLOBAL")
    }

    @Test func globalModeSynthesizesGlobalGroupWhenProfileDoesNotDeclareOne() {
        let state = makeConfiguredState(mode: "global", globalNow: "Tokyo-01")
        state.proxyGroups = Self.sampleGroupsWithoutGlobal(selected: "Singapore-02")
        state.activeProfileProxyGroups = state.proxyGroups

        #expect(state.visibleProxyGroups.first?.name == "GLOBAL")
        #expect(state.visibleProxyGroups.first?.now == "Singapore-02")
        #expect(state.visibleProxyGroups.first?.all == Self.sampleNodes.map(\.name))
        #expect(state.overviewProxyNodes.first?.node.name == "Singapore-02")
    }

    @Test func setForwardingModeUpdatesMockControllerAndConfig() async throws {
        AppDebugLog.resetModeMessagesForTesting()
        let state = makeConfiguredState(mode: "rule")
        state.setForwardingMode(.global)

        try await waitForModeUpdate()

        #expect(MockMihomoURLProtocolSupport.patchModeCalls.contains("global"))
        #expect(MockMihomoURLProtocolSupport.mode == "global")
        #expect(state.forwardingMode == .global)
        #expect(state.config?.mode == "global")
        #expect(AppState.verifyAppliedForwardingMode(expected: .global, configMode: state.config?.mode))
        #expect(AppDebugLog.recentModeMessages.contains(where: { $0.contains("出口模式切换成功") }))
    }

    @Test func setForwardingModeTestsOverviewProxyGroupDelay() async throws {
        let state = makeConfiguredState(mode: "rule")
        state.setForwardingMode(.global)

        try await waitForModeUpdate(.global)
        try await waitForDelayTest("GLOBAL")

        #expect(MockMihomoURLProtocolSupport.handledRequests.contains(where: { request in
            request.method == "GET" && request.path.contains("/group/GLOBAL/delay")
        }))
    }

    @Test func setForwardingModeLogsFailureWhenControllerRejectsPatch() async throws {
        AppDebugLog.resetModeMessagesForTesting()
        MockMihomoURLProtocolSupport.reset(mode: "rule", patchModeShouldFail: true)

        let session = MihomoAPI.makeMockSession(protocolClass: MockMihomoURLProtocol.self)
        var api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)
        api.urlSession = session

        let state = AppState()
        state.useAPIForTesting(api)
        state.core.applyDemoPresentation()
        state.config = MihomoConfig(
            port: 7890,
            socksPort: nil,
            mixedPort: 7890,
            redirPort: nil,
            tproxyPort: nil,
            mode: "rule",
            logLevel: "info",
            allowLan: false,
            ipv6: false,
            interfaceName: nil,
            tun: nil,
            externalController: "127.0.0.1:9090",
            secret: nil
        )
        state.forwardingMode = .rule

        state.setForwardingMode(.global)
        try await waitForModeFailureLog()

        #expect(MockMihomoURLProtocolSupport.patchModeCalls.isEmpty)
        #expect(state.forwardingMode == .rule)
        #expect(state.config?.mode == "rule")
        #expect(AppDebugLog.recentModeMessages.contains(where: { $0.contains("出口模式切换失败") }))
        #expect(state.events.contains(where: { $0.title == "模式切换失败" }))
    }

    @Test func selectProxyUpdatesMockControllerAndOverviewNodes() async throws {
        let state = makeConfiguredState(mode: "rule", globalNow: "Tokyo-01")
        state.forwardingMode = .global
        await state.selectProxy(groupID: "GLOBAL", proxyName: "Singapore-02")

        #expect(MockMihomoURLProtocolSupport.selectProxyCalls.contains(where: { $0.group == "GLOBAL" && $0.name == "Singapore-02" }))
        #expect(MockMihomoURLProtocolSupport.globalNow == "Singapore-02")
        #expect(state.proxyGroups.first(where: { $0.name == "GLOBAL" })?.now == "Singapore-02")
        #expect(state.overviewProxyNodes.first?.node.name == "Singapore-02")
        #expect(state.overviewProxyNodes.first?.isSelected == true)
    }

    @Test func synthesizedGlobalSelectionMapsToFirstRealGroup() async throws {
        let state = makeConfiguredState(mode: "global", globalNow: "Tokyo-01")
        state.proxyGroups = Self.sampleGroupsWithoutGlobal(selected: "Tokyo-01")
        state.activeProfileProxyGroups = state.proxyGroups

        await state.selectProxy(groupID: "GLOBAL", proxyName: "Singapore-02")

        #expect(MockMihomoURLProtocolSupport.selectProxyCalls.contains(where: { $0.group == "DoriyaNetwork" && $0.name == "Singapore-02" }))
    }

    private func waitForModeFailureLog() async throws {
        for _ in 0..<20 {
            if AppDebugLog.recentModeMessages.contains(where: { $0.contains("出口模式切换失败") }) {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("Timed out waiting for mode failure log")
    }

    private func waitForModeUpdate() async throws {
        try await waitForModeUpdate(.global)
    }

    private func waitForModeUpdate(_ mode: MihomoMode) async throws {
        for _ in 0..<20 {
            if MockMihomoURLProtocolSupport.patchModeCalls.contains(mode.mihomoValue) {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("Timed out waiting for mode update")
    }

    private func waitForDelayTest(_ group: String) async throws {
        for _ in 0..<40 {
            if MockMihomoURLProtocolSupport.handledRequests.contains(where: { request in
                request.method == "GET" && request.path.contains("/group/\(group)/delay")
            }) {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("Timed out waiting for overview delay test")
    }

    private static let sampleNodes: [ProxyNodeInfo] = [
        ProxyNodeInfo(name: "Tokyo-01", type: "vmess", server: "jp.example.com", port: 443),
        ProxyNodeInfo(name: "Singapore-02", type: "trojan", server: "sg.example.com", port: 443),
        ProxyNodeInfo(name: "Los Angeles-03", type: "shadowsocks", server: "us.example.com", port: 8388)
    ]

    private static func sampleGroups(selected: String) -> [ProxyGroupItem] {
        [
            ProxyGroupItem(
                id: "GLOBAL",
                name: "GLOBAL",
                type: "select",
                now: selected,
                all: sampleNodes.map(\.name),
                nodes: sampleNodes.map {
                    ProxyGroupNode(name: $0.name, type: $0.type, delay: 50, alive: true)
                },
                aliveCount: sampleNodes.count,
                testURL: "http://www.gstatic.com/generate_204"
            ),
            ProxyGroupItem(
                id: "DoriyaNetwork",
                name: "DoriyaNetwork",
                type: "select",
                now: "Tokyo-01",
                all: sampleNodes.map(\.name),
                nodes: sampleNodes.map {
                    ProxyGroupNode(name: $0.name, type: $0.type, delay: 50, alive: true)
                },
                aliveCount: sampleNodes.count,
                testURL: "http://www.gstatic.com/generate_204"
            ),
            ProxyGroupItem(
                id: "Auto",
                name: "Auto",
                type: "fallback",
                now: "Singapore-02",
                all: sampleNodes.map(\.name),
                nodes: sampleNodes.map {
                    ProxyGroupNode(name: $0.name, type: $0.type, delay: 50, alive: true)
                },
                aliveCount: sampleNodes.count,
                testURL: "http://www.gstatic.com/generate_204"
            )
        ]
    }

    private static func sampleGroupsWithoutGlobal(selected: String) -> [ProxyGroupItem] {
        [
            ProxyGroupItem(
                id: "DoriyaNetwork",
                name: "DoriyaNetwork",
                type: "select",
                now: selected,
                all: sampleNodes.map(\.name),
                nodes: sampleNodes.map {
                    ProxyGroupNode(name: $0.name, type: $0.type, delay: 50, alive: true)
                },
                aliveCount: sampleNodes.count,
                testURL: "http://www.gstatic.com/generate_204"
            ),
            ProxyGroupItem(
                id: "Auto",
                name: "Auto",
                type: "fallback",
                now: selected,
                all: sampleNodes.map(\.name),
                nodes: sampleNodes.map {
                    ProxyGroupNode(name: $0.name, type: $0.type, delay: 50, alive: true)
                },
                aliveCount: sampleNodes.count,
                testURL: "http://www.gstatic.com/generate_204"
            )
        ]
    }
}
