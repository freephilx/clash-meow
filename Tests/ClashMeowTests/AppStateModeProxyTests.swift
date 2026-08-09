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

    @Test func coreUsesRuntimeDirectoryLayout() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clash-meow-runtime-layout-\(UUID().uuidString)", directoryHint: .isDirectory)
        AppPersistencePaths.configDirectoryOverrideForTesting = directory
        defer { AppPersistencePaths.configDirectoryOverrideForTesting = nil }

        let core = MihomoCoreManager()

        #expect(core.rootDirectory == directory)
        #expect(AppPersistencePaths.configsDirectory == directory.appending(path: "configs", directoryHint: .isDirectory))
        #expect(AppPersistencePaths.mihomoConfigsDirectory == Self.mihomoConfigsURL(in: directory))
        #expect(core.runtimeDirectory == directory.appending(path: "runtime", directoryHint: .isDirectory))
        #expect(core.configDirectory == directory
            .appending(path: "runtime", directoryHint: .isDirectory)
            .appending(path: "mihomo", directoryHint: .isDirectory))
        #expect(core.configFile == Self.runtimeConfigURL(in: directory))
        #expect(core.logsDirectory == directory
            .appending(path: "runtime", directoryHint: .isDirectory)
            .appending(path: "logs", directoryHint: .isDirectory))
        #expect(core.coreLogFile == core.configDirectory.appending(path: "mihomo.log"))
        #expect(core.appLogFile == core.logsDirectory.appending(path: "app.log"))
    }

    @Test func backgroundApplicationLogsPublishToMemoryBeforePageRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clashmeow-live-app-log-\(UUID().uuidString)", directoryHint: .isDirectory)
        AppPersistencePaths.configDirectoryOverrideForTesting = directory
        defer {
            AppPersistencePaths.configDirectoryOverrideForTesting = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let state = AppState()
        let logsDirectory = state.core.logsDirectory
        await Task.detached {
            AppLogSupport.info("live memory event", module: "Test", logsDirectory: logsDirectory)
        }.value
        try await Task.sleep(for: .milliseconds(50))

        #expect(state.appLogs.contains { $0.message == "[Test] live memory event" })
        AppLogSupport.flush()
        let persisted = try String(contentsOf: state.core.appLogFile, encoding: .utf8)
        #expect(persisted.contains("[Test] live memory event"))
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

    @Test func ruleToggleWritesProfileDeleteOverride() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clash-meow-rule-override-\(UUID().uuidString)", directoryHint: .isDirectory)
        AppPersistencePaths.configDirectoryOverrideForTesting = directory
        defer {
            AppPersistencePaths.configDirectoryOverrideForTesting = nil
            try? FileManager.default.removeItem(at: directory)
        }

        MockMihomoURLProtocolSupport.reset()
        let session = MihomoAPI.makeMockSession(protocolClass: MockMihomoURLProtocol.self)
        var api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)
        api.urlSession = session

        let mihomoConfigsDirectory = Self.mihomoConfigsURL(in: directory)
        try FileManager.default.createDirectory(at: mihomoConfigsDirectory, withIntermediateDirectories: true)
        let profileID = "selected-profile"
        let profileYAML = """
        mixed-port: 7890
        proxy-groups:
          - name: Proxy
            type: select
            proxies:
              - DIRECT
        rules:
          - DOMAIN-SUFFIX,example.com,Proxy
          - MATCH,DIRECT
        """
        try profileYAML.write(
            to: mihomoConfigsDirectory.appending(path: "\(profileID).yaml"),
            atomically: true,
            encoding: .utf8
        )

        let repository = ProfileRepository(
            configDirectory: directory,
            activeConfigFile: Self.runtimeConfigURL(in: directory)
        )
        try repository.activateProfile(id: profileID)
        let state = AppState()
        state.useAPIForTesting(api)
        state.core.applyDemoPresentation()
        state.refreshProfiles()
        let rule = RuleItem(
            id: "0-DOMAIN-SUFFIX-example.com",
            index: 0,
            type: "DOMAIN-SUFFIX",
            payload: "example.com",
            proxy: "Proxy",
            isEnabled: true,
            hitCount: 0,
            missCount: 0,
            lastHit: nil,
            lastMiss: nil,
            size: 0
        )

        await state.setRule(rule, isEnabled: false)
        let disabledMetadata = AppPreferenceStore.readMihomoSettings().profiles.first { $0.id == profileID }
        let disabledRuntimeYAML = try String(contentsOf: Self.runtimeConfigURL(in: directory), encoding: .utf8)
        #expect(disabledMetadata?.ruleOverrides.delete == ["DOMAIN-SUFFIX,example.com,Proxy"])
        #expect(!disabledRuntimeYAML.contains("DOMAIN-SUFFIX,example.com,Proxy"))
        #expect(MockMihomoURLProtocolSupport.handledRequests.contains { $0.method == "PATCH" && $0.path == "/rules/disable" })

        await state.setRule(rule, isEnabled: true)
        let enabledRuntimeYAML = try String(contentsOf: Self.runtimeConfigURL(in: directory), encoding: .utf8)
        let enabledMetadata = AppPreferenceStore.readMihomoSettings().profiles.first { $0.id == profileID }
        #expect(enabledMetadata?.ruleOverrides.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: mihomoConfigsDirectory.appending(path: "\(profileID).rules.yaml").path))
        #expect(enabledRuntimeYAML.contains("DOMAIN-SUFFIX,example.com,Proxy"))
        #expect(MockMihomoURLProtocolSupport.handledRequests.filter { $0.method == "PATCH" && $0.path == "/rules/disable" }.count == 2)
        #expect(!MockMihomoURLProtocolSupport.handledRequests.contains { $0.method == "PUT" && $0.path == "/configs" })
    }

    @Test func ruleToggleKeepsCurrentRulesWhenRuntimePatchAndReloadFail() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clash-meow-rule-reload-fail-\(UUID().uuidString)", directoryHint: .isDirectory)
        AppPersistencePaths.configDirectoryOverrideForTesting = directory
        defer {
            AppPersistencePaths.configDirectoryOverrideForTesting = nil
            try? FileManager.default.removeItem(at: directory)
        }

        MockMihomoURLProtocolSupport.reset(reloadConfigShouldFail: true, ruleDisableShouldFail: true)
        let session = MihomoAPI.makeMockSession(protocolClass: MockMihomoURLProtocol.self)
        var api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)
        api.urlSession = session

        let mihomoConfigsDirectory = Self.mihomoConfigsURL(in: directory)
        try FileManager.default.createDirectory(at: mihomoConfigsDirectory, withIntermediateDirectories: true)
        let profileID = "selected-profile"
        let profileYAML = """
        mixed-port: 7890
        proxy-groups:
          - name: Proxy
            type: select
            proxies:
              - DIRECT
        rules:
          - DOMAIN-SUFFIX,example.com,Proxy
          - MATCH,DIRECT
        """
        try profileYAML.write(
            to: mihomoConfigsDirectory.appending(path: "\(profileID).yaml"),
            atomically: true,
            encoding: .utf8
        )

        let repository = ProfileRepository(
            configDirectory: directory,
            activeConfigFile: Self.runtimeConfigURL(in: directory)
        )
        try repository.activateProfile(id: profileID)
        let state = AppState()
        state.useAPIForTesting(api)
        state.core.applyDemoPresentation()
        state.refreshProfiles()
        let rule = RuleItem(
            id: "0-DOMAIN-SUFFIX-example.com",
            index: 0,
            type: "DOMAIN-SUFFIX",
            payload: "example.com",
            proxy: "Proxy",
            isEnabled: true,
            hitCount: 0,
            missCount: 0,
            lastHit: nil,
            lastMiss: nil,
            size: 0
        )
        state.rules = [rule]

        await state.setRule(rule, isEnabled: false)

        #expect(!state.rules.isEmpty)
        #expect(state.rules.contains { $0.index == rule.index && $0.displayPayload == rule.displayPayload })
        #expect(state.toast?.message == "规则已保存，热更新失败")
        #expect(MockMihomoURLProtocolSupport.handledRequests.contains { $0.method == "PATCH" && $0.path == "/rules/disable" })
        #expect(MockMihomoURLProtocolSupport.handledRequests.contains { $0.method == "PUT" && $0.path == "/configs" })
    }

    @Test func ruleUpdateWritesReplacementOverrideAndHotReloads() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clash-meow-rule-update-\(UUID().uuidString)", directoryHint: .isDirectory)
        AppPersistencePaths.configDirectoryOverrideForTesting = directory
        defer {
            AppPersistencePaths.configDirectoryOverrideForTesting = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let (state, rule) = try Self.makeRuleEditingState(in: directory)
        await state.updateRule(rule, with: "DOMAIN-SUFFIX,new.example.com,DIRECT")

        let overrides = AppPreferenceStore.readMihomoSettings().profiles
            .first { $0.id == "selected-profile" }?.ruleOverrides
        let runtimeYAML = try String(contentsOf: Self.runtimeConfigURL(in: directory), encoding: .utf8)
        #expect(overrides?.prepend == ["DOMAIN-SUFFIX,new.example.com,DIRECT"])
        #expect(overrides?.delete == ["DOMAIN-SUFFIX,old.example.com,Proxy"])
        #expect(runtimeYAML.contains("DOMAIN-SUFFIX,new.example.com,DIRECT"))
        #expect(!runtimeYAML.contains("DOMAIN-SUFFIX,old.example.com,Proxy"))
        #expect(state.toast?.message == "已修改规则")
        #expect(MockMihomoURLProtocolSupport.handledRequests.contains { $0.method == "PUT" && $0.path == "/configs" })
    }

    @Test func ruleUpdateRestoresOverridesAndRuntimeWhenHotReloadFails() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clash-meow-rule-update-rollback-\(UUID().uuidString)", directoryHint: .isDirectory)
        AppPersistencePaths.configDirectoryOverrideForTesting = directory
        defer {
            AppPersistencePaths.configDirectoryOverrideForTesting = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let (state, rule) = try Self.makeRuleEditingState(in: directory, reloadConfigShouldFail: true)
        let previousRuntimeYAML = try String(contentsOf: Self.runtimeConfigURL(in: directory), encoding: .utf8)
        await state.updateRule(rule, with: "DOMAIN-SUFFIX,new.example.com,DIRECT")

        let overrides = AppPreferenceStore.readMihomoSettings().profiles
            .first { $0.id == "selected-profile" }?.ruleOverrides
        let restoredRuntimeYAML = try String(contentsOf: Self.runtimeConfigURL(in: directory), encoding: .utf8)
        #expect(overrides?.isEmpty == true)
        #expect(restoredRuntimeYAML == previousRuntimeYAML)
        #expect(state.toast?.message == "修改规则失败")
        #expect(MockMihomoURLProtocolSupport.handledRequests.filter { $0.method == "PUT" && $0.path == "/configs" }.count == 2)
    }

    @Test func refreshRulesLoadsAndUpdatesRuleProviders() async throws {
        let state = makeConfiguredState()

        await state.refreshRules()

        let provider = try #require(state.ruleProviders.first)
        #expect(provider.name == "RejectSet")
        #expect(provider.ruleCount == 12)

        await state.updateAllRuleProviders()

        #expect(MockMihomoURLProtocolSupport.handledRequests.contains {
            $0.method == "PUT" && $0.path == "/providers/rules/RejectSet"
        })
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

    @Test func runtimeProxyGroupsFollowConfiguredGroupOrder() {
        let response = ProxiesResponse(proxies: [
            "GLOBAL": ProxyNode(
                name: "GLOBAL",
                type: "Selector",
                now: "Singapore-02",
                all: Self.sampleNodes.map(\.name),
                alive: nil,
                hidden: nil,
                testURL: nil,
                history: nil
            ),
            "Auto": ProxyNode(
                name: "Auto",
                type: "Fallback",
                now: "Singapore-02",
                all: Self.sampleNodes.map(\.name),
                alive: nil,
                hidden: nil,
                testURL: nil,
                history: nil
            ),
            "DoriyaNetwork": ProxyNode(
                name: "DoriyaNetwork",
                type: "Selector",
                now: "Tokyo-01",
                all: Self.sampleNodes.map(\.name),
                alive: nil,
                hidden: nil,
                testURL: nil,
                history: nil
            ),
            "Tokyo-01": ProxyNode(name: "Tokyo-01", type: "VMess", now: nil, all: nil, alive: true, hidden: nil, testURL: nil, history: nil),
            "Singapore-02": ProxyNode(name: "Singapore-02", type: "Trojan", now: nil, all: nil, alive: true, hidden: nil, testURL: nil, history: nil),
            "Los Angeles-03": ProxyNode(name: "Los Angeles-03", type: "Shadowsocks", now: nil, all: nil, alive: true, hidden: nil, testURL: nil, history: nil)
        ])

        let configuredGroups = [
            Self.sampleGroups(selected: "Tokyo-01")[1],
            Self.sampleGroups(selected: "Tokyo-01")[2]
        ]
        let groups = AppState.makeProxyGroups(from: response, configuredGroups: configuredGroups)

        #expect(groups.map(\.name) == ["DoriyaNetwork", "Auto", "GLOBAL"])
        #expect(groups.first?.now == "Tokyo-01")
    }

    @Test func proxyPageRefreshUsesReachableControllerEvenWhenCoreStateIsStale() async {
        MockMihomoURLProtocolSupport.reset(mode: "rule", globalNow: "Tokyo-01")
        let session = MihomoAPI.makeMockSession(protocolClass: MockMihomoURLProtocol.self)
        var api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)
        api.urlSession = session

        let state = AppState()
        state.useAPIForTesting(api)
        state.forwardingMode = .rule
        state.activeProfileProxyGroups = [
            ProxyGroupItem(
                id: "koyun",
                name: "koyun",
                type: "select",
                now: "自动选择",
                all: Self.sampleNodes.map(\.name),
                nodes: [],
                aliveCount: nil,
                testURL: nil
            )
        ]

        #expect(state.core.status == .stopped)
        #expect(state.visibleProxyGroups.map(\.name) == ["koyun"])

        await state.refreshProxyGroupsFromControllerIfAvailable()

        #expect(MockMihomoURLProtocolSupport.handledRequests.contains(where: { $0.method == "GET" && $0.path == "/proxies" }))
        #expect(state.proxyGroups.map(\.name) == ["GLOBAL", "Proxy"])
        #expect(state.visibleProxyGroups.map(\.name) == ["Proxy"])
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

    @Test func savedSystemProxyPreferenceRestoresLastAppliedState() {
        let originalPreference = SystemProxyPreference.isEnabled
        defer { SystemProxyPreference.setEnabled(originalPreference) }

        SystemProxyPreference.setEnabled(true)
        let state = AppState()

        #expect(state.toggles.first(where: { $0.id == "proxy" })?.isOn == true)
        #expect(state.systemProxyEnabled == true)
    }

    @Test func enablingSystemProxyWhileCoreStoppedRollsBackPreference() {
        let originalPreference = SystemProxyPreference.isEnabled
        let originalUserPreference = SystemProxyUserPreference.isEnabled
        defer {
            SystemProxyPreference.setEnabled(originalPreference)
            SystemProxyUserPreference.setEnabled(originalUserPreference)
        }

        SystemProxyPreference.setEnabled(false)
        SystemProxyUserPreference.setEnabled(false)
        let state = AppState()

        state.setSystemProxyEnabled(true)

        #expect(SystemProxyPreference.isEnabled == false)
        #expect(SystemProxyUserPreference.isEnabled == false)
        #expect(state.toggles.first(where: { $0.id == "proxy" })?.isOn == false)
        #expect(state.systemProxyEnabled == false)
        #expect(state.toast?.message == "请先启动内核")
    }

    @Test func enablingTunWhileCoreStoppedRollsBackPreference() {
        let originalPreference = TunPreference.isEnabled
        let originalUserPreference = TunUserPreference.isEnabled
        defer {
            TunPreference.setEnabled(originalPreference)
            TunUserPreference.setEnabled(originalUserPreference)
        }

        TunPreference.setEnabled(false)
        TunUserPreference.setEnabled(false)
        let state = AppState()

        state.setTunEnabled(true)

        #expect(TunPreference.isEnabled == false)
        #expect(TunUserPreference.isEnabled == false)
        #expect(state.toggles.first(where: { $0.id == "tun" })?.isOn == false)
        #expect(state.toast?.message == "请先启动内核")
    }

    @Test func overviewTunToggleWhileCoreStoppedRollsBackToOff() {
        let originalPreference = TunPreference.isEnabled
        let originalUserPreference = TunUserPreference.isEnabled
        defer {
            TunPreference.setEnabled(originalPreference)
            TunUserPreference.setEnabled(originalUserPreference)
        }

        TunPreference.setEnabled(false)
        TunUserPreference.setEnabled(false)
        let state = AppState()
        let tunToggle = state.toggles.first(where: { $0.id == "tun" })!

        state.setToggle(tunToggle, isOn: true)

        #expect(TunPreference.isEnabled == false)
        #expect(TunUserPreference.isEnabled == false)
        #expect(state.toggles.first(where: { $0.id == "tun" })?.isOn == false)
        #expect(state.isTunEnabled == false)
        #expect(state.toast?.message == "请先启动内核")
    }

    @Test func startupWithCoreDisabledClearsActualTunButKeepsUserIntent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clash-meow-startup-tun-disabled-core-\(UUID().uuidString)", directoryHint: .isDirectory)
        let originalCorePreference = CoreAutoStartManager.isEnabled
        let originalPreference = TunPreference.isEnabled
        let originalUserPreference = TunUserPreference.isEnabled
        AppPersistencePaths.configDirectoryOverrideForTesting = directory
        defer {
            AppPersistencePaths.configDirectoryOverrideForTesting = nil
            CoreAutoStartManager.setEnabled(originalCorePreference)
            TunPreference.setEnabled(originalPreference)
            TunUserPreference.setEnabled(originalUserPreference)
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalYAML = """
        mixed-port: 7890
        tun:
          enable: false
        proxy-groups:
          - name: Proxy
            type: select
            proxies:
              - DIRECT
        rules:
          - MATCH,DIRECT
        """
        _ = try Self.writeRuntimeConfig(originalYAML, in: directory)
        CoreAutoStartManager.setEnabled(false)
        TunPreference.setEnabled(true)
        TunUserPreference.setEnabled(true)
        MockMihomoURLProtocolSupport.reset(tunEnabled: false)
        let session = MihomoAPI.makeMockSession(protocolClass: MockMihomoURLProtocol.self)
        var api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)
        api.urlSession = session

        let state = AppState()
        state.useAPIForTesting(api)

        await state.bootstrap()

        #expect(TunPreference.isEnabled == false)
        #expect(TunUserPreference.isEnabled == true)
        #expect(state.toggles.first(where: { $0.id == "tun" })?.isOn == false)
        #expect(!MockMihomoURLProtocolSupport.handledRequests.contains(where: { $0.method == "PUT" && $0.path == "/configs" }))
    }

    @Test func enablingTunUsesHotReloadAndPersistsAfterRuntimeValidation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clash-meow-tun-hot-reload-\(UUID().uuidString)", directoryHint: .isDirectory)
        let originalPreference = TunPreference.isEnabled
        let originalUserPreference = TunUserPreference.isEnabled
        AppPersistencePaths.configDirectoryOverrideForTesting = directory
        defer {
            AppPersistencePaths.configDirectoryOverrideForTesting = nil
            TunPreference.setEnabled(originalPreference)
            TunUserPreference.setEnabled(originalUserPreference)
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalYAML = """
        mixed-port: 7890
        tun:
          enable: false
        proxy-groups:
          - name: Proxy
            type: select
            proxies:
              - DIRECT
        rules:
          - MATCH,DIRECT
        """
        let runtimeConfig = try Self.writeRuntimeConfig(originalYAML, in: directory)
        TunPreference.setEnabled(false)
        TunUserPreference.setEnabled(false)
        MockMihomoURLProtocolSupport.reset(tunEnabled: false)
        let session = MihomoAPI.makeMockSession(protocolClass: MockMihomoURLProtocol.self)
        var api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)
        api.urlSession = session

        let state = AppState()
        state.useAPIForTesting(api)
        state.core.applyDemoPresentation()
        var didRestart = false
        state.setTunRestartForTesting {
            didRestart = true
        }

        state.setTunEnabled(true)
        try await Task.sleep(for: .milliseconds(200))

        let updatedYAML = try String(contentsOf: runtimeConfig, encoding: .utf8)
        #expect(updatedYAML.contains("enable: true"))
        #expect(TunPreference.isEnabled == true)
        #expect(TunUserPreference.isEnabled == true)
        #expect(state.toggles.first(where: { $0.id == "tun" })?.isOn == true)
        #expect(didRestart == false)
        #expect(MockMihomoURLProtocolSupport.handledRequests.contains(where: { $0.method == "PUT" && $0.path == "/configs" }))
        #expect(MockMihomoURLProtocolSupport.handledRequests.contains(where: { $0.method == "GET" && $0.path == "/configs" }))
    }

    @Test func rapidTunToggleWhileApplyingDoesNotStartSecondUpdate() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clash-meow-tun-single-flight-\(UUID().uuidString)", directoryHint: .isDirectory)
        let originalPreference = TunPreference.isEnabled
        let originalUserPreference = TunUserPreference.isEnabled
        AppPersistencePaths.configDirectoryOverrideForTesting = directory
        defer {
            AppPersistencePaths.configDirectoryOverrideForTesting = nil
            TunPreference.setEnabled(originalPreference)
            TunUserPreference.setEnabled(originalUserPreference)
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalYAML = """
        mixed-port: 7890
        tun:
          enable: false
        proxy-groups:
          - name: Proxy
            type: select
            proxies:
              - DIRECT
        rules:
          - MATCH,DIRECT
        """
        _ = try Self.writeRuntimeConfig(originalYAML, in: directory)
        TunPreference.setEnabled(false)
        TunUserPreference.setEnabled(false)
        MockMihomoURLProtocolSupport.reset(tunEnabled: false)
        let session = MihomoAPI.makeMockSession(protocolClass: MockMihomoURLProtocol.self)
        var api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)
        api.urlSession = session

        let state = AppState()
        state.useAPIForTesting(api)
        state.core.applyDemoPresentation()

        state.setTunEnabled(true)
        #expect(state.isApplyingTunUpdate == true)
        state.setTunEnabled(false)
        try await Task.sleep(for: .milliseconds(200))

        #expect(TunPreference.isEnabled == true)
        #expect(TunUserPreference.isEnabled == true)
        #expect(state.toggles.first(where: { $0.id == "tun" })?.isOn == true)
        #expect(MockMihomoURLProtocolSupport.handledRequests.filter { $0.method == "PUT" && $0.path == "/configs" }.count == 1)
    }

    @Test func enablingTunFallbackRestartWaitsForControllerReadiness() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clash-meow-tun-restart-ready-\(UUID().uuidString)", directoryHint: .isDirectory)
        let originalPreference = TunPreference.isEnabled
        let originalUserPreference = TunUserPreference.isEnabled
        AppPersistencePaths.configDirectoryOverrideForTesting = directory
        defer {
            AppPersistencePaths.configDirectoryOverrideForTesting = nil
            TunPreference.setEnabled(originalPreference)
            TunUserPreference.setEnabled(originalUserPreference)
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalYAML = """
        mixed-port: 7890
        tun:
          enable: false
        proxy-groups:
          - name: Proxy
            type: select
            proxies:
              - DIRECT
        rules:
          - MATCH,DIRECT
        """
        _ = try Self.writeRuntimeConfig(originalYAML, in: directory)
        TunPreference.setEnabled(false)
        TunUserPreference.setEnabled(false)
        MockMihomoURLProtocolSupport.reset(
            tunEnabled: false,
            reloadConfigShouldFail: true,
            versionFailureCount: 2
        )
        let session = MihomoAPI.makeMockSession(protocolClass: MockMihomoURLProtocol.self)
        var api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)
        api.urlSession = session

        let state = AppState()
        state.useAPIForTesting(api)
        state.core.applyDemoPresentation()
        var didRestart = false
        state.setTunRestartForTesting {
            didRestart = true
            MockMihomoURLProtocolSupport.setRuntimeTunEnabled(true)
        }

        state.setTunEnabled(true)
        try await Task.sleep(for: .milliseconds(600))

        #expect(didRestart == true)
        #expect(TunPreference.isEnabled == true)
        #expect(TunUserPreference.isEnabled == true)
        #expect(state.toggles.first(where: { $0.id == "tun" })?.isOn == true)
        #expect(MockMihomoURLProtocolSupport.handledRequests.filter { $0.method == "GET" && $0.path == "/version" }.count >= 3)
        #expect(MockMihomoURLProtocolSupport.handledRequests.contains(where: { $0.method == "GET" && $0.path == "/configs" }))
    }

    @Test func enablingTunRollsBackWhenCoreRestartFails() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clash-meow-tun-rollback-\(UUID().uuidString)", directoryHint: .isDirectory)
        let originalPreference = TunPreference.isEnabled
        let originalUserPreference = TunUserPreference.isEnabled
        AppPersistencePaths.configDirectoryOverrideForTesting = directory
        defer {
            AppPersistencePaths.configDirectoryOverrideForTesting = nil
            TunPreference.setEnabled(originalPreference)
            TunUserPreference.setEnabled(originalUserPreference)
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalYAML = """
        mixed-port: 7890
        tun:
          enable: false
        proxy-groups:
          - name: Proxy
            type: select
            proxies:
              - DIRECT
        rules:
          - MATCH,DIRECT
        """
        let runtimeConfig = try Self.writeRuntimeConfig(originalYAML, in: directory)
        TunPreference.setEnabled(false)
        TunUserPreference.setEnabled(false)
        MockMihomoURLProtocolSupport.reset(tunEnabled: false, reloadConfigShouldFail: true)
        let session = MihomoAPI.makeMockSession(protocolClass: MockMihomoURLProtocol.self)
        var api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)
        api.urlSession = session

        let state = AppState()
        state.useAPIForTesting(api)
        state.core.applyDemoPresentation()
        state.setTunRestartForTesting {
            throw NSError(domain: "ClashMeowTests", code: 1)
        }

        state.setTunEnabled(true)
        try await Task.sleep(for: .milliseconds(100))

        let restoredYAML = try String(contentsOf: runtimeConfig, encoding: .utf8)
        #expect(restoredYAML == originalYAML)
        #expect(TunPreference.isEnabled == false)
        #expect(TunUserPreference.isEnabled == false)
        #expect(state.toggles.first(where: { $0.id == "tun" })?.isOn == false)
        #expect(state.toast?.message == "TUN 设置失败")
        #expect(MockMihomoURLProtocolSupport.handledRequests.contains(where: { $0.method == "PUT" && $0.path == "/configs" }))
    }

    @Test func dashboardDemoRespectsPersistedCoreSwitch() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clash-meow-settings-\(UUID().uuidString)", directoryHint: .isDirectory)
        AppPreferenceStore.configDirectoryOverrideForTesting = directory
        defer {
            AppPreferenceStore.configDirectoryOverrideForTesting = nil
            try? FileManager.default.removeItem(at: directory)
        }

        CoreAutoStartManager.setEnabled(false)
        let state = AppState()

        state.applyDashboardDemo()

        #expect(state.core.status == .stopped)
        #expect(state.toggles.first(where: { $0.id == "proxy" })?.isOn == false)
        #expect(state.toggles.first(where: { $0.id == "tun" })?.isOn == false)
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

    @Test func testDelayFallsBackToProxyDelayAndKeepsPreviousDelayOnRequestFailure() async throws {
        MockMihomoURLProtocolSupport.reset(
            groupDelayShouldFail: true,
            proxyDelayResults: [
                "Tokyo-01": 91,
                "Singapore-02": 0
            ]
        )
        let session = MihomoAPI.makeMockSession(protocolClass: MockMihomoURLProtocol.self)
        var api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)
        api.urlSession = session

        let state = AppState()
        state.useAPIForTesting(api)
        state.core.applyDemoPresentation()
        state.proxyGroups = Self.sampleGroups(selected: "Tokyo-01")

        await state.testDelay(for: state.proxyGroups[0])

        let group = try #require(state.proxyGroups.first(where: { $0.id == "GLOBAL" }))
        let nodesByName = Dictionary(uniqueKeysWithValues: group.nodes.map { ($0.name, $0) })
        #expect(nodesByName["Tokyo-01"]?.delay == 91)
        #expect(nodesByName["Tokyo-01"]?.alive == true)
        #expect(nodesByName["Singapore-02"]?.delay == 0)
        #expect(nodesByName["Singapore-02"]?.alive == false)
        #expect(nodesByName["Los Angeles-03"]?.delay == 50)
        #expect(nodesByName["Los Angeles-03"]?.alive == true)
        #expect(MockMihomoURLProtocolSupport.handledRequests.contains(where: { request in
            request.method == "GET" && request.path.contains("/group/GLOBAL/delay")
        }))
        #expect(MockMihomoURLProtocolSupport.handledRequests.filter { request in
            request.method == "GET" && request.path.contains("/proxies/") && request.path.hasSuffix("/delay")
        }.count == 3)
    }

    @Test func testDelayWhileCoreStoppedShowsToastWithoutRequest() async throws {
        MockMihomoURLProtocolSupport.reset()
        let session = MihomoAPI.makeMockSession(protocolClass: MockMihomoURLProtocol.self)
        var api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)
        api.urlSession = session

        let state = AppState()
        state.useAPIForTesting(api)
        state.proxyGroups = Self.sampleGroups(selected: "Tokyo-01")

        await state.testDelay(for: state.proxyGroups[0])

        #expect(state.toast?.message == "请先启动内核，再测试代理延迟")
        #expect(MockMihomoURLProtocolSupport.handledRequests.isEmpty)
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

    private static func runtimeConfigURL(in rootDirectory: URL) -> URL {
        rootDirectory
            .appending(path: "runtime", directoryHint: .isDirectory)
            .appending(path: "mihomo", directoryHint: .isDirectory)
            .appending(path: "config.yaml")
    }

    private static func mihomoConfigsURL(in rootDirectory: URL) -> URL {
        rootDirectory
            .appending(path: "configs", directoryHint: .isDirectory)
            .appending(path: "mihomo", directoryHint: .isDirectory)
    }

    private static func makeRuleEditingState(
        in directory: URL,
        reloadConfigShouldFail: Bool = false
    ) throws -> (state: AppState, rule: RuleItem) {
        MockMihomoURLProtocolSupport.reset(reloadConfigShouldFail: reloadConfigShouldFail)
        let session = MihomoAPI.makeMockSession(protocolClass: MockMihomoURLProtocol.self)
        var api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)
        api.urlSession = session

        let mihomoConfigsDirectory = mihomoConfigsURL(in: directory)
        try FileManager.default.createDirectory(at: mihomoConfigsDirectory, withIntermediateDirectories: true)
        let profileYAML = """
        mixed-port: 7890
        proxy-groups:
          - name: Proxy
            type: select
            proxies:
              - DIRECT
        rules:
          - DOMAIN-SUFFIX,old.example.com,Proxy
          - MATCH,DIRECT
        """
        try profileYAML.write(
            to: mihomoConfigsDirectory.appending(path: "selected-profile.yaml"),
            atomically: true,
            encoding: .utf8
        )
        let repository = ProfileRepository(
            configDirectory: directory,
            activeConfigFile: runtimeConfigURL(in: directory)
        )
        try repository.activateProfile(id: "selected-profile")

        let state = AppState()
        state.useAPIForTesting(api)
        state.core.applyDemoPresentation()
        state.refreshProfiles()
        let rule = RuleItem(
            id: "0-DOMAIN-SUFFIX-old.example.com",
            index: 0,
            type: "DOMAIN-SUFFIX",
            payload: "old.example.com",
            proxy: "Proxy",
            isEnabled: true,
            hitCount: 0,
            missCount: 0,
            lastHit: nil,
            lastMiss: nil,
            size: 0
        )
        return (state, rule)
    }

    @discardableResult
    private static func writeRuntimeConfig(_ yaml: String, in rootDirectory: URL) throws -> URL {
        let url = runtimeConfigURL(in: rootDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
