import AppKit
import Foundation
import Combine

struct AppToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

private enum TunUpdateError: LocalizedError {
    case coreRestartFailed(CoreStatus)
    case coreRestartTimedOut
    case runtimeTunMismatch(expected: Bool, actual: Bool?)

    var errorDescription: String? {
        switch self {
        case .coreRestartFailed(let status):
            "增强模式需要 mihomo 正常启动，当前状态：\(status.title)"
        case .coreRestartTimedOut:
            "增强模式需要 mihomo 正常启动，但等待启动超时。"
        case .runtimeTunMismatch(let expected, let actual):
            "增强模式运行状态校验失败，期望：\(expected)，实际：\(actual.map(String.init) ?? "nil")。"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var core = MihomoCoreManager()
    @Published var config: MihomoConfig?
    @Published var version: MihomoVersion?
    @Published var traffic = TrafficSnapshot()
    @Published var trafficHistory: [TrafficSample] = []
    @Published var connections = ConnectionsSnapshot(downloadTotal: 0, uploadTotal: 0, connections: [])
    @Published var proxyGroups: [ProxyGroupItem] = []
    @Published var rules: [RuleItem] = []
    @Published var ruleProviders: [RuleProviderItem] = []
    @Published var logs: [CoreLogEntry] = []
    @Published var isStreamingLogs = false
    @Published private(set) var updatingRuleProviderNames = Set<String>()
    @Published private(set) var testingDelayGroupID: String?
    @Published var activeProfileConfig: MihomoConfig?
    @Published var activeProfileProxyGroups: [ProxyGroupItem] = []
    @Published var activeProfileNodes: [ProxyNodeInfo] = []
    @Published var proxyNodeStatuses: [String: ProxyNodeRuntimeStatus] = [:]
    @Published var internetLatencySnapshot = InternetLatencySnapshot.empty
    @Published private(set) var isDiagnosingInternetLatency = false
    @Published var profiles: [ClashMeowProfileSummary] = []
    @Published var toast: AppToast?
    @Published var isImportingProfile = false
    @Published private(set) var isApplyingTunUpdate = false
    @Published var refreshingProfileIDs = Set<String>()
    @Published var forwardingMode: MihomoMode
    @Published var allowLan: Bool
    @Published private(set) var systemProxyEnabled = SystemProxyPreference.isEnabled
    @Published var events: [EventItem] = []
    @Published var toggles: [FeatureToggle] = [
        .init(id: "dns", title: "DNS", subtitle: "DNS 解析与 nameserver 配置状态。", systemImage: "network", isOn: true),
        .init(id: "allowLan", title: "允许局域网访问", subtitle: "允许局域网设备连接本机混合端口。", systemImage: "rectangle.connected.to.line.below", isOn: false),
        .init(id: "proxy", title: "系统代理", subtitle: "将系统网络设置指向本机混合端口。", systemImage: "globe", isOn: false),
        .init(id: "tun", title: "TUN", subtitle: "系统栈、自动路由与虚拟网卡。", systemImage: "antenna.radiowaves.left.and.right", isOn: false)
    ]

    private(set) var api = MihomoAPI()
    private let systemProxyController = SystemProxyController()
    private var pollTask: Task<Void, Never>?
    private var logStreamTask: Task<Void, Never>?
    private var modeUpdateTask: Task<Void, Never>?
    private var allowLanUpdateTask: Task<Void, Never>?
    private var systemProxyUpdateTask: Task<Void, Never>?
    private var tunUpdateTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var trafficStreamTask: Task<Void, Never>?
    private var coreStartupTask: Task<Void, Never>?
    private var configReloadTask: Task<Void, Never>?
    private var activeConfigFileMonitor: YAMLFileChangeMonitor?
    private var activeProfileFileMonitor: YAMLFileChangeMonitor?
    private var suppressFileChangeNotificationsUntil: Date?
    private var isApplyingObservedConfigurationChange = false
    private var pendingObservedConfigurationChange: ObservedConfigFile?
    private var suppressModeDriftSync = false
    private var cancellables = Set<AnyCancellable>()
    #if DEBUG
    private var tunRestartForTesting: (() async throws -> Void)?
    #endif

    var isTestingDelay: Bool {
        testingDelayGroupID != nil
    }

    func isTestingDelay(groupID: String) -> Bool {
        testingDelayGroupID == groupID
    }

    private var profileRepository: ProfileRepository {
        ProfileRepository(
            configDirectory: core.rootDirectory,
            activeConfigFile: core.configFile,
            logsDirectory: core.logsDirectory
        )
    }

    private enum ObservedConfigFile {
        case activeConfig
        case activeProfile
    }

    init() {
        let savedMode = AppPreferenceStore.string(\.forwardingMode)
        self.forwardingMode = MihomoMode(rawValue: savedMode ?? "") ?? .rule
        self.allowLan = AppPreferenceStore.bool(\.allowLan, default: false)
        let savedSystemProxy = SystemProxyPreference.isEnabled
        let savedTun = TunPreference.isEnabled
        self.toggles = [
            .init(id: "dns", title: "DNS", subtitle: "DNS 解析与 nameserver 配置状态。", systemImage: "network", isOn: true),
            .init(id: "allowLan", title: "允许局域网访问", subtitle: "允许局域网设备连接本机混合端口。", systemImage: "rectangle.connected.to.line.below", isOn: self.allowLan),
            .init(id: "proxy", title: "系统代理", subtitle: "将系统网络设置指向本机混合端口。", systemImage: "globe", isOn: savedSystemProxy),
            .init(id: "tun", title: "TUN", subtitle: "系统栈、自动路由与虚拟网卡。", systemImage: "antenna.radiowaves.left.and.right", isOn: savedTun)
        ]

        AppLogSupport.info("AppState 初始化完成", module: "App", logsDirectory: core.logsDirectory)

        core.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        core.$status
            .removeDuplicates()
            .sink { [weak self] status in
                guard let self, !DashboardDemoMode.isEnabled else { return }
                if status.isHealthy {
                    startPolling()
                } else {
                    stopPolling()
                    stopTrafficStream()
                }
            }
            .store(in: &cancellables)
    }

    var visibleProxyGroups: [ProxyGroupItem] {
        let groups: [ProxyGroupItem]
        if !proxyGroups.isEmpty {
            groups = proxyGroups
        } else if !activeProfileProxyGroups.isEmpty {
            groups = activeProfileProxyGroups
        } else {
            groups = [
                .init(id: "Proxy", name: "Proxy", type: "select", now: "DIRECT", all: ["DIRECT"], nodes: [.init(name: "DIRECT", type: "direct", delay: nil, alive: true)], aliveCount: 1, testURL: nil),
                .init(id: "DIRECT", name: "DIRECT", type: "direct", now: "DIRECT", all: [], nodes: [], aliveCount: nil, testURL: nil)
            ]
        }

        switch effectiveForwardingMode {
        case .direct:
            return []
        case .global:
            return Self.moveGlobalProxyGroupFirst(Self.proxyGroupsWithGlobalFirst(
                groups: groups,
                profileNodes: activeProfileNodes,
                statuses: proxyNodeStatuses
            ))
        case .rule:
            return groups.filter { !Self.isGlobalProxyGroup($0) }
        }
    }

    var visibleProxyNodes: [ProxyNodeInfo] {
        activeProfileNodes
    }

    var overviewProxyNodes: [OverviewProxyNode] {
        let groups = runtimeProxyGroupsForCurrentMode
        return Self.makeOverviewProxyNodes(
            mode: effectiveForwardingMode,
            groups: groups,
            profileNodes: activeProfileNodes,
            statuses: proxyNodeStatuses
        )
    }

    var primaryProxyGroup: ProxyGroupItem? {
        let groups = runtimeProxyGroupsForCurrentMode
        return groups.first(where: { $0.name == "GLOBAL" }) ?? groups.first
    }

    private var runtimeProxyGroupsForCurrentMode: [ProxyGroupItem] {
        let groups = proxyGroups.isEmpty ? activeProfileProxyGroups : proxyGroups
        if effectiveForwardingMode == .global {
            return Self.moveGlobalProxyGroupFirst(Self.proxyGroupsWithGlobalFirst(
                groups: groups,
                profileNodes: activeProfileNodes,
                statuses: proxyNodeStatuses
            ))
        }
        return groups
    }

    private static func isGlobalProxyGroup(_ group: ProxyGroupItem) -> Bool {
        group.id.caseInsensitiveCompare("GLOBAL") == .orderedSame
            || group.name.caseInsensitiveCompare("GLOBAL") == .orderedSame
    }

    private static func moveGlobalProxyGroupFirst(_ groups: [ProxyGroupItem]) -> [ProxyGroupItem] {
        guard let index = groups.firstIndex(where: { isGlobalProxyGroup($0) }), index > 0 else {
            return groups
        }
        var reordered = groups
        let global = reordered.remove(at: index)
        reordered.insert(global, at: 0)
        return reordered
    }

    static func proxyGroupsWithGlobalFirst(
        groups: [ProxyGroupItem],
        profileNodes: [ProxyNodeInfo],
        statuses: [String: ProxyNodeRuntimeStatus]
    ) -> [ProxyGroupItem] {
        guard !groups.contains(where: { isGlobalProxyGroup($0) }) else {
            return groups
        }

        let fallbackNodes = groups.first?.nodes ?? []
        let nodes: [ProxyGroupNode]
        if !profileNodes.isEmpty {
            nodes = profileNodes.map { node in
                let status = statuses[node.name]
                return ProxyGroupNode(
                    name: node.name,
                    type: node.type,
                    delay: status?.delay,
                    alive: status?.alive
                )
            }
        } else {
            nodes = fallbackNodes
        }

        let all = nodes.map(\.name)
        guard !all.isEmpty else { return groups }

        let selected = groups.first?.now
        let now = selected.flatMap { all.contains($0) ? $0 : nil } ?? all.first ?? "-"
        let global = ProxyGroupItem(
            id: "GLOBAL",
            name: "GLOBAL",
            type: "select",
            now: now,
            all: all,
            nodes: nodes,
            aliveCount: nodes.filter { $0.alive != false }.count,
            testURL: groups.first?.testURL
        )
        return [global] + groups
    }

    static func makeOverviewProxyNodes(
        mode: MihomoMode = .rule,
        groups: [ProxyGroupItem],
        profileNodes: [ProxyNodeInfo],
        statuses: [String: ProxyNodeRuntimeStatus]
    ) -> [OverviewProxyNode] {
        if mode == .direct {
            return [
                OverviewProxyNode(
                    node: ProxyNodeInfo(name: "DIRECT", type: "direct", server: nil, port: nil),
                    isSelected: true,
                    delay: nil
                )
            ]
        }

        guard let group = overviewProxyGroup(for: mode, groups: groups) else {
            return []
        }

        let nodeByName = profileNodes.reduce(into: [String: ProxyNodeInfo]()) { result, node in
            result[node.name] = node
        }
        let selectedName = group.now
        var result: [OverviewProxyNode] = []

        if selectedName != "-", selectedName.caseInsensitiveCompare("DIRECT") != .orderedSame, let selectedNode = nodeByName[selectedName] {
            result.append(
                OverviewProxyNode(
                    node: selectedNode,
                    isSelected: true,
                    delay: validDelay(statuses[selectedName]?.delay)
                )
            )
        }

        let rankedNodes = profileNodes
            .filter { $0.name != selectedName }
            .sorted { left, right in
                let leftDelay = validDelay(statuses[left.name]?.delay) ?? Int.max
                let rightDelay = validDelay(statuses[right.name]?.delay) ?? Int.max
                if leftDelay != rightDelay {
                    return leftDelay < rightDelay
                }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
            .prefix(max(0, 3 - result.count))
            .map {
                OverviewProxyNode(
                    node: $0,
                    isSelected: false,
                    delay: validDelay(statuses[$0.name]?.delay)
                )
            }

        result.append(contentsOf: rankedNodes)
        return result
    }

    private static func overviewProxyGroup(for mode: MihomoMode, groups: [ProxyGroupItem]) -> ProxyGroupItem? {
        switch mode {
        case .global:
            return groups.first(where: { isGlobalProxyGroup($0) }) ?? groups.first
        case .rule:
            return groups.first(where: { !isGlobalProxyGroup($0) }) ?? groups.first
        case .direct:
            return nil
        }
    }

    private static func validDelay(_ delay: Int?) -> Int? {
        guard let delay, delay > 0 else { return nil }
        return delay
    }

    internal func useAPIForTesting(_ api: MihomoAPI) {
        self.api = api
    }

    #if DEBUG
    internal func setTunRestartForTesting(_ restart: (() async throws -> Void)?) {
        tunRestartForTesting = restart
    }
    #endif

    var currentProfile: ClashMeowProfileSummary? {
        profiles.first(where: \.isCurrent)
    }

    var currentProfileName: String {
        currentProfile?.name ?? core.configFile.lastPathComponent
    }

    var displayedConfig: MihomoConfig? {
        activeProfileConfig ?? config
    }

    var mixedPort: Int {
        displayedConfig?.mixedPort ?? 7890
    }

    var controllerPort: Int {
        displayedConfig?.externalControllerURL?.port ?? 9090
    }

    var tunDevice: String {
        displayedConfig?.tun?.deviceName ?? "utun10"
    }

    var modeText: String {
        effectiveForwardingMode.displayValue
    }

    var effectiveForwardingMode: MihomoMode {
        if core.status.isHealthy, let runtimeMode = config?.mode {
            return MihomoMode(configValue: runtimeMode)
        }
        return forwardingMode
    }

    var logLevelText: String {
        displayedConfig?.logLevel ?? "info"
    }

    var connectionCountText: String {
        "\(connections.connections.count)"
    }

    var trafficText: String {
        "\(Self.formatBytes(traffic.up))/s up · \(Self.formatBytes(traffic.down))/s down"
    }

    var activityProcessCount: Int {
        Set(connections.connections.map { $0.metadata?.processName ?? $0.displayHost }).count
    }

    var activityTrafficRows: [ActivityTrafficRow] {
        var totals: [String: Int] = [:]
        for connection in connections.connections {
            let name = connection.metadata?.processName ?? connection.displayHost
            totals[name, default: 0] += (connection.upload ?? 0) + (connection.download ?? 0)
        }
        return totals
            .map { ActivityTrafficRow(id: $0.key, name: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }

    var activitySelectedProxyDelayText: String {
        guard core.status.isHealthy else { return "--" }
        let groups = proxyGroups.isEmpty ? activeProfileProxyGroups : proxyGroups
        guard let group = groups.first(where: { $0.name == "GLOBAL" }) ?? groups.first else { return "--" }
        let selected = group.now
        if let delay = proxyNodeStatuses[selected]?.delay, delay > 0 {
            return "\(delay) ms"
        }
        if let node = group.nodes.first(where: { $0.name == selected }),
           let delay = node.delay, delay > 0 {
            return "\(delay) ms"
        }
        return "--"
    }

    var activityInternetLatencyText: String {
        internetLatencySnapshot.internetText
    }

    var activityRouterLatencyText: String {
        internetLatencySnapshot.routerText
    }

    var activityDNSLatencyText: String {
        internetLatencySnapshot.dnsText
    }

    var activityCumulativeTrafficTotal: Int {
        let streamed = traffic.upTotal + traffic.downTotal
        if streamed > 0 { return streamed }
        return (connections.uploadTotal ?? 0) + (connections.downloadTotal ?? 0)
    }

    var uploadSparklineSamples: [Int] {
        trafficHistory.map(\.upload)
    }

    var downloadSparklineSamples: [Int] {
        trafficHistory.map(\.download)
    }

    var isTunEnabled: Bool {
        toggles.first(where: { $0.id == "tun" })?.isOn ?? TunPreference.isEnabled
    }

    var systemProxyPort: Int {
        config?.mixedPort ?? activeProfileConfig?.mixedPort ?? 7890
    }

    var coreSubtitle: String {
        switch core.status {
        case .running:
            let versionText = version?.version ?? "内核"
            return "\(versionText) 正在运行，模式 \(modeText)，控制器已连接。"
        case .missingBinary:
            return "未找到网络内核组件。"
        case .failed(let message):
            return message
        case .starting:
            return "正在启动内核并读取控制器状态。"
        case .stopped:
            return "网络内核未启动。启动后会读取配置、连接、流量和节点组状态。"
        }
    }

    func bootstrap() async {
        core.prepare()

        if DashboardDemoMode.isEnabled {
            applyDashboardDemo()
            return
        }

        guard ensureRequiredHelperInstalledForStartup() else {
            return
        }

        restoreSelectedProfileIfNeeded()
        refreshProfiles()
        loadActiveProfileSnapshot()
        startConfigurationFileMonitoring()
        addEvent(source: "Core", title: core.status.title, detail: coreSubtitle)

        if CoreAutoStartManager.isEnabled {
            connect(recordPreference: false)
        } else {
            await applySavedNetworkPreferences()
        }
    }

    private func ensureRequiredHelperInstalledForStartup() -> Bool {
        guard PrivilegedHelperManager.shared.canInstallBundledHelper else {
            AppLogSupport.warning("当前运行环境不是 app bundle，跳过启动 helper 前置校验", module: "Helper", logsDirectory: core.logsDirectory)
            return true
        }

        do {
            AppLogSupport.info("启动前校验 privileged helper", module: "Helper", logsDirectory: core.logsDirectory)
            try PrivilegedHelperManager.shared.ensureInstalledForApplicationStartup()
            addEvent(source: "Helper", title: "管理员助手已就绪", detail: "已安装并通过版本校验。")
            return true
        } catch {
            AppLogSupport.error("启动前 helper 校验失败: \(error.localizedDescription)", module: "Helper", logsDirectory: core.logsDirectory)
            addEvent(source: "Helper", title: "管理员助手未就绪", detail: error.localizedDescription)
            showToast("需要安装管理员助手")
            return false
        }
    }

    func applyDashboardDemo() {
        DashboardDemoData.apply(to: self, coreEnabled: CoreAutoStartManager.isEnabled)
        addEvent(source: "Core", title: core.status.title, detail: coreSubtitle)
    }

    func setDemoPresentationFlags(systemProxyEnabled: Bool) {
        self.systemProxyEnabled = systemProxyEnabled
    }

    func connect(recordPreference: Bool = true) {
        guard !DashboardDemoMode.isEnabled else { return }
        loadActiveProfileSnapshot()
        core.start()
        if recordPreference {
            CoreAutoStartManager.setEnabled(true)
        }
        addEvent(source: "Core", title: "启动内核", detail: "使用 \(currentProfileName) 作为配置文件。")
        schedulePostCoreStartupRestore()
    }

    func disconnect(recordPreference: Bool = true) {
        guard !DashboardDemoMode.isEnabled else { return }
        coreStartupTask?.cancel()
        coreStartupTask = nil
        if systemProxyEnabled {
            setSystemProxyEnabled(false, recordPreference: false)
        }
        if isTunEnabled {
            setTunEnabled(false, recordPreference: false, restartIfNeeded: false)
        }
        stopTrafficStream()
        stopPolling()
        core.stop()
        if recordPreference {
            CoreAutoStartManager.setEnabled(false)
        }
        addEvent(source: "Core", title: "停止内核", detail: "本地内核进程已停止。")
    }

    private func schedulePostCoreStartupRestore() {
        coreStartupTask?.cancel()
        coreStartupTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await waitForControllerReadyAfterCoreStart()
                guard !Task.isCancelled, core.status.isHealthy else { return }
                await refresh()
                if SystemProxyUserPreference.isEnabled {
                    setSystemProxyEnabled(true, recordPreference: false)
                }
                if TunUserPreference.isEnabled {
                    setTunEnabled(true, recordPreference: false)
                } else {
                    await applySavedNetworkPreferences()
                }
            } catch {
                guard !Task.isCancelled else { return }
                addEvent(source: "Core", title: "Controller 暂不可用", detail: error.localizedDescription)
            }
        }
    }

    private func waitForControllerReadyAfterCoreStart(timeout: TimeInterval = 12) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?
        while Date() < deadline {
            try Task.checkCancellation()
            guard core.status.isHealthy else {
                try await Task.sleep(for: .milliseconds(150))
                continue
            }
            do {
                _ = try await api.version()
                return
            } catch {
                lastError = error
                try await Task.sleep(for: .milliseconds(150))
            }
        }
        throw lastError ?? URLError(.timedOut)
    }

    func shutdown() {
        stopLogStream()
        stopTrafficStream()
        stopPolling()
        modeUpdateTask?.cancel()
        modeUpdateTask = nil
        allowLanUpdateTask?.cancel()
        allowLanUpdateTask = nil
        systemProxyUpdateTask?.cancel()
        systemProxyUpdateTask = nil
        tunUpdateTask?.cancel()
        tunUpdateTask = nil
        toastDismissTask?.cancel()
        toastDismissTask = nil
        configReloadTask?.cancel()
        configReloadTask = nil
        isApplyingObservedConfigurationChange = false
        pendingObservedConfigurationChange = nil
        activeConfigFileMonitor?.stop()
        activeConfigFileMonitor = nil
        activeProfileFileMonitor?.stop()
        activeProfileFileMonitor = nil

        let shouldReleasePorts = core.status.shouldReloadForProfileChange
        disableSystemProxySynchronously()
        core.stop()
        if shouldReleasePorts {
            core.releaseListeningPorts()
        }
    }

    func prepareForTermination() async {
        shutdown()
    }

    func restart() {
        core.restart()
        addEvent(source: "Core", title: "重新连接", detail: "正在重启网络内核。")
    }

    func refresh() async {
        guard core.status.isHealthy else { return }

        do {
            async let version = api.version()
            async let config = api.configs()
            async let connections = api.connections()
            async let proxies = api.proxies()
            async let rules = api.rules()
            async let ruleProviders = api.ruleProviders()
            self.version = try await version
            self.config = try await config
            updateAPIEndpoint(from: self.config)
            self.connections = try await connections
            self.traffic = (try? await api.traffic()) ?? self.traffic
            let proxiesResponse = try await proxies
            let fetchedStatuses = Self.makeProxyNodeStatuses(from: proxiesResponse)
            self.proxyNodeStatuses = Self.mergedProxyNodeStatuses(
                existing: self.proxyNodeStatuses,
                fetched: fetchedStatuses
            )
            self.proxyGroups = Self.makeProxyGroups(
                from: proxiesResponse,
                configuredGroups: self.activeProfileProxyGroups,
                delayOverrides: self.proxyNodeStatuses
            )
            if let fetchedRules = try? await rules {
                self.rules = fetchedRules
            }
            self.ruleProviders = (try? await ruleProviders) ?? self.ruleProviders
            syncTrafficStream()
            await applySavedModeIfNeeded()
            await applySavedAllowLanIfNeeded()
        } catch {
            loadActiveProfileSnapshot()
            addEvent(source: "Core", title: "API 暂不可用", detail: error.localizedDescription)
        }
    }

    func refreshProxyGroupsFromControllerIfAvailable() async {
        do {
            async let config = api.configs()
            async let proxies = api.proxies()
            self.config = try await config
            updateAPIEndpoint(from: self.config)
            let proxiesResponse = try await proxies
            let fetchedStatuses = Self.makeProxyNodeStatuses(from: proxiesResponse)
            self.proxyNodeStatuses = Self.mergedProxyNodeStatuses(
                existing: self.proxyNodeStatuses,
                fetched: fetchedStatuses
            )
            self.proxyGroups = Self.makeProxyGroups(
                from: proxiesResponse,
                configuredGroups: self.activeProfileProxyGroups,
                delayOverrides: self.proxyNodeStatuses
            )
        } catch {
            addEvent(source: "Proxy", title: "代理组刷新失败", detail: error.localizedDescription)
        }
    }

    func diagnoseInternetLatencyIfNeeded() async {
        guard internetLatencySnapshot.measuredAt == nil else { return }
        await diagnoseInternetLatency()
    }

    func diagnoseInternetLatency() async {
        guard !isDiagnosingInternetLatency else { return }

        isDiagnosingInternetLatency = true
        defer { isDiagnosingInternetLatency = false }

        let configuration = InternetLatencyPreference.configuration
        var snapshot = await Task.detached(priority: .utility) {
            await InternetLatencyDiagnostics.measure(configuration: configuration)
        }.value
        let proxyEntry = await proxyChainDiagnosticEntry(configuration: configuration)
        snapshot.entries.append(proxyEntry)
        internetLatencySnapshot = snapshot

        let values = [
            "公网 \(snapshot.internetText)",
            "路由器 \(snapshot.routerText)",
            "DNS \(snapshot.dnsText)"
        ].joined(separator: " · ")
        addEvent(source: "Network", title: "互联网延迟诊断完成", detail: values)
    }

    private func proxyChainDiagnosticEntry(configuration: InternetLatencyConfiguration) async -> InternetDiagnosticEntry {
        guard core.status.isHealthy else {
            return InternetDiagnosticEntry(title: "测试代理链", message: "内核未运行，跳过代理链测试", level: .info)
        }
        let groups = proxyGroups.isEmpty ? activeProfileProxyGroups : proxyGroups
        guard let group = groups.first(where: { $0.name == "GLOBAL" }) ?? groups.first else {
            return InternetDiagnosticEntry(title: "测试代理链", message: "当前没有可用节点组", level: .info)
        }
        let proxyName = group.now.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proxyName.isEmpty, proxyName.uppercased() != "DIRECT" else {
            return InternetDiagnosticEntry(title: "测试代理链", message: "当前选择 DIRECT，跳过代理链测试", level: .info)
        }

        let testURL = MihomoAPI.resolvedDelayTestURL(group.testURL)
        do {
            let delay = try await api.proxyDelay(
                proxyName: proxyName,
                testURL: testURL,
                timeoutMs: MihomoAPI.fallbackProxyDelayTimeoutMs
            )
            guard let delay, delay > 0 else {
                return InternetDiagnosticEntry(
                    title: "测试代理链",
                    message: "通过 \(proxyName) 连接到 \(testURL) 超时",
                    level: .warning
                )
            }
            proxyNodeStatuses[proxyName] = ProxyNodeRuntimeStatus(delay: delay, alive: true)
            return InternetDiagnosticEntry(
                title: "测试代理链",
                message: "通过 \(proxyName) 连接到 \(testURL): \(delay) ms",
                level: .success
            )
        } catch {
            return InternetDiagnosticEntry(
                title: "测试代理链",
                message: "通过 \(proxyName) 连接到 \(testURL) 失败: \(error.localizedDescription)",
                level: .warning
            )
        }
    }

    func refreshProfiles() {
        do {
            profiles = try profileRepository.listProfiles()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func restoreSelectedProfileIfNeeded() {
        do {
            try profileRepository.restoreSelectedProfileIfNeeded()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    @discardableResult
    func importRemoteProfile(urlString: String, useProxy: Bool) async -> Bool {
        let value = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), !value.isEmpty else {
            showToast("远程配置 URL 无效")
            return false
        }
        if useProxy, !core.status.isHealthy {
            showToast("请先启动内核，再通过本机网络获取远程配置")
            return false
        }

        isImportingProfile = true
        defer { isImportingProfile = false }

        do {
            suppressFileChangeNotifications()
            let summary = try await profileRepository.importRemoteProfile(
                from: url,
                useProxy: useProxy,
                proxyPort: useProxy ? mixedPort : nil
            )
            refreshProfiles()
            updateActiveProfileFileMonitor()
            loadActiveProfileSnapshot(resetRuntimeData: true)
            core.releaseListeningPorts()
            reloadCoreAfterProfileChange(toastMessage: "已导入 \(summary.name)")
            addEvent(source: "Profile", title: "导入远程配置", detail: summary.name)
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func importLocalProfile(from url: URL) async -> Bool {
        isImportingProfile = true
        defer { isImportingProfile = false }

        do {
            suppressFileChangeNotifications()
            let summary = try profileRepository.importLocalProfile(from: url)
            refreshProfiles()
            updateActiveProfileFileMonitor()
            loadActiveProfileSnapshot(resetRuntimeData: true)
            core.releaseListeningPorts()
            reloadCoreAfterProfileChange(toastMessage: "已导入 \(summary.name)")
            addEvent(source: "Profile", title: "导入本地配置", detail: summary.name)
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func createBlankLocalProfile() async -> Bool {
        isImportingProfile = true
        defer { isImportingProfile = false }

        do {
            let summary = try profileRepository.createBlankLocalProfile()
            refreshProfiles()
            updateActiveProfileFileMonitor()
            addEvent(source: "Profile", title: "新建本地配置", detail: summary.name)
            showToast("已创建空白配置 \(summary.name)")
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
        }
    }

    func selectProfile(_ profile: ClashMeowProfileSummary) async {
        guard !profile.isCurrent else { return }
        do {
            suppressFileChangeNotifications()
            core.releaseListeningPorts(for: profileRepository.profileFileURL(id: profile.id))
            try profileRepository.activateProfile(id: profile.id)
            refreshProfiles()
            updateActiveProfileFileMonitor()
            loadActiveProfileSnapshot(resetRuntimeData: true)
            core.releaseListeningPorts()
            reloadCoreAfterProfileChange(toastMessage: "已切换到 \(profile.name)")
            addEvent(source: "Profile", title: "切换配置", detail: profile.name)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func refreshProfile(_ profile: ClashMeowProfileSummary) async {
        guard profile.kind == .remote, !refreshingProfileIDs.contains(profile.id) else { return }
        if profile.useProxy, !core.status.isHealthy {
            showToast("请先启动内核，再通过本机网络刷新远程配置")
            return
        }
        refreshingProfileIDs.insert(profile.id)
        defer { refreshingProfileIDs.remove(profile.id) }

        do {
            if profile.isCurrent {
                suppressFileChangeNotifications()
            }
            let summary = try await profileRepository.refreshRemoteProfile(
                id: profile.id,
                proxyPort: profile.useProxy ? mixedPort : nil
            )
            refreshProfiles()
            updateActiveProfileFileMonitor()
            if profile.isCurrent {
                suppressFileChangeNotifications()
                loadActiveProfileSnapshot(resetRuntimeData: true)
                core.releaseListeningPorts()
                reloadCoreAfterProfileChange(toastMessage: "\(summary.name) 已更新")
            } else {
                showToast("\(summary.name) 已更新")
            }
            addEvent(source: "Profile", title: "刷新远程配置", detail: summary.name)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func deleteProfile(_ profile: ClashMeowProfileSummary) async {
        do {
            let deletedCurrent = try profileRepository.deleteProfile(id: profile.id)
            refreshProfiles()
            updateActiveProfileFileMonitor()
            if deletedCurrent {
                suppressFileChangeNotifications()
                loadActiveProfileSnapshot(resetRuntimeData: true)
                core.releaseListeningPorts()
                reloadCoreAfterProfileChange(toastMessage: "已删除 \(profile.name)")
            } else {
                showToast("已删除 \(profile.name)")
            }
            addEvent(source: "Profile", title: "删除配置", detail: profile.name)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func setToggle(_ toggle: FeatureToggle, isOn: Bool) {
        guard let index = toggles.firstIndex(where: { $0.id == toggle.id }) else { return }
        switch toggle.id {
        case "allowLan":
            setAllowLan(isOn)
        case "proxy":
            setSystemProxyEnabled(isOn)
        case "tun":
            setTunEnabled(isOn)
        default:
            toggles[index].isOn = isOn
            addEvent(source: "Proxy", title: "\(toggle.title)\(isOn ? "开启" : "关闭")", detail: toggle.subtitle)
        }
    }

    func setSystemProxyEnabled(_ isEnabled: Bool, recordPreference: Bool = true) {
        let previousEnabled = systemProxyEnabled
        let previousPreference = SystemProxyPreference.isEnabled
        let previousUserPreference = SystemProxyUserPreference.isEnabled
        let previousToggle = previousEnabled
        if isEnabled, !core.status.isHealthy {
            showToast("请先启动内核")
            systemProxyEnabled = previousEnabled
            SystemProxyPreference.setEnabled(previousPreference)
            SystemProxyUserPreference.setEnabled(previousUserPreference)
            if let index = toggles.firstIndex(where: { $0.id == "proxy" }) {
                toggles[index].isOn = previousToggle
            }
            return
        }

        systemProxyEnabled = isEnabled
        if let index = toggles.firstIndex(where: { $0.id == "proxy" }) {
            toggles[index].isOn = isEnabled
        }

        systemProxyUpdateTask?.cancel()
        systemProxyUpdateTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.applySystemProxy(isEnabled)
                SystemProxyPreference.setEnabled(isEnabled)
                if recordPreference {
                    SystemProxyUserPreference.setEnabled(isEnabled)
                }
                addEvent(
                    source: "Proxy",
                    title: "系统代理\(isEnabled ? "开启" : "关闭")",
                    detail: isEnabled ? "127.0.0.1:\(systemProxyPort)" : "已恢复系统网络设置"
                )
            } catch {
                systemProxyEnabled = previousEnabled
                SystemProxyPreference.setEnabled(previousPreference)
                SystemProxyUserPreference.setEnabled(previousUserPreference)
                if let index = toggles.firstIndex(where: { $0.id == "proxy" }) {
                    toggles[index].isOn = previousToggle
                }
                addEvent(source: "Proxy", title: "系统代理设置失败", detail: error.localizedDescription)
                showToast("系统代理设置失败")
            }
        }
    }

    func setTunEnabled(_ isEnabled: Bool, recordPreference: Bool = true, restartIfNeeded: Bool = true) {
        let previousPreference = TunPreference.isEnabled
        let previousUserPreference = TunUserPreference.isEnabled
        let previousToggle = toggles.first(where: { $0.id == "tun" })?.isOn ?? previousPreference
        if isApplyingTunUpdate {
            showToast("增强模式正在应用，请稍后再试")
            if let index = toggles.firstIndex(where: { $0.id == "tun" }) {
                toggles[index].isOn = previousToggle
            }
            return
        }
        if isEnabled, !core.status.isHealthy {
            showToast("请先启动内核")
            TunPreference.setEnabled(previousPreference)
            TunUserPreference.setEnabled(previousUserPreference)
            if let index = toggles.firstIndex(where: { $0.id == "tun" }) {
                toggles[index].isOn = previousToggle
            }
            return
        }

        if let index = toggles.firstIndex(where: { $0.id == "tun" }) {
            toggles[index].isOn = isEnabled
        }

        isApplyingTunUpdate = true
        tunUpdateTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isApplyingTunUpdate = false
                tunUpdateTask = nil
            }
            do {
                try await applyTunEnabled(isEnabled, restartIfNeeded: restartIfNeeded)
                TunPreference.setEnabled(isEnabled)
                if recordPreference {
                    TunUserPreference.setEnabled(isEnabled)
                }
                if let index = toggles.firstIndex(where: { $0.id == "tun" }) {
                    toggles[index].isOn = isEnabled
                }
                addEvent(
                    source: "TUN",
                    title: "TUN \(isEnabled ? "开启" : "关闭")",
                    detail: isEnabled ? tunDevice : "已写入配置并应用"
                )
            } catch {
                TunPreference.setEnabled(previousPreference)
                TunUserPreference.setEnabled(previousUserPreference)
                if let index = toggles.firstIndex(where: { $0.id == "tun" }) {
                    toggles[index].isOn = previousToggle
                }
                addEvent(source: "TUN", title: "TUN 设置失败", detail: error.localizedDescription)
                showToast("TUN 设置失败")
            }
        }
    }

    private func applySavedNetworkPreferences() async {
        if SystemProxyPreference.isEnabled, core.status.isHealthy {
            do {
                try await applySystemProxy(true)
                systemProxyEnabled = true
                if let index = toggles.firstIndex(where: { $0.id == "proxy" }) {
                    toggles[index].isOn = true
                }
            } catch {
                setSystemProxyEnabled(false)
            }
        }

        let desiredTun = TunPreference.isEnabled
        guard core.status.isHealthy else {
            if desiredTun {
                TunPreference.setEnabled(false)
                if let index = toggles.firstIndex(where: { $0.id == "tun" }) {
                    toggles[index].isOn = false
                }
            }
            return
        }

        let currentTun = activeProfileConfig?.tun?.enable ?? false
        if desiredTun != currentTun {
            do {
                isApplyingTunUpdate = true
                defer { isApplyingTunUpdate = false }
                try await applyTunEnabled(desiredTun)
                if let index = toggles.firstIndex(where: { $0.id == "tun" }) {
                    toggles[index].isOn = desiredTun
                }
            } catch {
                addEvent(source: "TUN", title: "TUN 自动应用失败", detail: error.localizedDescription)
            }
        }
    }

    private func applySystemProxy(_ isEnabled: Bool) async throws {
        let savedService = AppPreferenceStore.string(\.systemProxyNetworkService)
        let configuration = try systemProxyController.resolvedConfiguration(
            port: systemProxyPort,
            networkService: savedService
        )
        try systemProxyController.setEnabled(isEnabled, configuration: configuration)
        AppPreferenceStore.setString(configuration.networkService, \.systemProxyNetworkService)
    }

    private func disableSystemProxySynchronously() {
        let savedService = AppPreferenceStore.string(\.systemProxyNetworkService)
        let port = systemProxyPort
        if let configuration = try? systemProxyController.resolvedConfiguration(
            port: port,
            networkService: savedService
        ) {
            try? systemProxyController.setEnabled(false, configuration: configuration)
        }
        systemProxyEnabled = false
        SystemProxyPreference.setEnabled(false)
    }

    private func applyTunEnabled(_ isEnabled: Bool, restartIfNeeded: Bool = true) async throws {
        suppressFileChangeNotifications()
        let yaml = try String(contentsOf: core.configFile, encoding: .utf8)
        let previousTunEnabled = activeProfileConfig?.tun?.enable ?? false
        let shouldRestart = restartIfNeeded && core.status.shouldReloadForProfileChange
        let updated = try MihomoYAMLSettings.setTunEnabled(isEnabled, in: yaml)

        do {
            try updated.write(to: core.configFile, atomically: true, encoding: .utf8)
            loadActiveProfileSnapshot()
            syncPublishedTunConfig(isEnabled: isEnabled)

            guard shouldRestart else { return }
            try await applyCoreAfterTunChange(isEnabled: isEnabled)
            await refresh()
        } catch {
            try? yaml.write(to: core.configFile, atomically: true, encoding: .utf8)
            loadActiveProfileSnapshot()
            syncPublishedTunConfig(isEnabled: previousTunEnabled)
            if shouldRestart {
                #if DEBUG
                if tunRestartForTesting == nil {
                    await recoverCoreAfterTunRollback()
                }
                #else
                await recoverCoreAfterTunRollback()
                #endif
            }
            throw error
        }
    }

    private func applyCoreAfterTunChange(isEnabled: Bool) async throws {
        do {
            try await reloadCoreConfigAfterTunChange(isEnabled: isEnabled)
        } catch {
            AppLogSupport.warning(
                "TUN API reload 失败，fallback restart: \(error.localizedDescription)",
                module: "TUN",
                logsDirectory: core.logsDirectory
            )
            try await restartCoreAfterTunChange()
            try await validateRuntimeTunEnabled(isEnabled)
        }
    }

    private func reloadCoreConfigAfterTunChange(isEnabled: Bool) async throws {
        try await api.reloadConfig(path: core.configFile)
        try await validateRuntimeTunEnabled(isEnabled)
    }

    private func validateRuntimeTunEnabled(_ expected: Bool) async throws {
        let runtimeConfig = try await api.configs()
        let actual = runtimeConfig.tun?.enable
        guard actual == expected else {
            throw TunUpdateError.runtimeTunMismatch(expected: expected, actual: actual)
        }
    }

    private func restartCoreAfterTunChange() async throws {
        #if DEBUG
        if let tunRestartForTesting {
            try await tunRestartForTesting()
        } else {
            core.releaseListeningPorts()
            core.restart()
        }
        #else
        core.releaseListeningPorts()
        core.restart()
        #endif
        try await waitForCoreHealthyAfterTunRestart()
    }

    private func waitForCoreHealthyAfterTunRestart(timeout: TimeInterval = 12) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?
        repeat {
            if core.status.isHealthy {
                do {
                    _ = try await api.version()
                    return
                } catch {
                    lastError = error
                }
            }
            switch core.status {
            case .failed, .missingBinary:
                throw TunUpdateError.coreRestartFailed(core.status)
            case .starting, .stopped, .running:
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        if let lastError {
            throw lastError
        }
        throw TunUpdateError.coreRestartTimedOut
    }

    private func recoverCoreAfterTunRollback() async {
        if core.status.isHealthy {
            core.restart()
        } else {
            core.start()
        }
        try? await waitForCoreHealthyAfterTunRestart()
        if core.status.isHealthy {
            await refresh()
        }
    }

    private func syncPublishedTunConfig(isEnabled: Bool) {
        let tun = TunConfig(
            enable: isEnabled,
            stack: activeProfileConfig?.tun?.stack,
            device: activeProfileConfig?.tun?.device
        )
        config = config.map { current in
            MihomoConfig(
                port: current.port,
                socksPort: current.socksPort,
                mixedPort: current.mixedPort,
                redirPort: current.redirPort,
                tproxyPort: current.tproxyPort,
                mode: current.mode,
                logLevel: current.logLevel,
                allowLan: current.allowLan,
                ipv6: current.ipv6,
                interfaceName: current.interfaceName,
                tun: tun,
                externalController: current.externalController,
                secret: current.secret
            )
        }
        activeProfileConfig = activeProfileConfig.map { current in
            MihomoConfig(
                port: current.port,
                socksPort: current.socksPort,
                mixedPort: current.mixedPort,
                redirPort: current.redirPort,
                tproxyPort: current.tproxyPort,
                mode: current.mode,
                logLevel: current.logLevel,
                allowLan: current.allowLan,
                ipv6: current.ipv6,
                interfaceName: current.interfaceName,
                tun: tun,
                externalController: current.externalController,
                secret: current.secret
            )
        }
    }

    func setForwardingMode(_ mode: MihomoMode) {
        forwardingMode = mode
        AppPreferenceStore.setString(mode.rawValue, \.forwardingMode)
        config = config.map {
            MihomoConfig(
                port: $0.port,
                socksPort: $0.socksPort,
                mixedPort: $0.mixedPort,
                redirPort: $0.redirPort,
                tproxyPort: $0.tproxyPort,
                mode: mode.mihomoValue,
                logLevel: $0.logLevel,
                allowLan: $0.allowLan,
                ipv6: $0.ipv6,
                interfaceName: $0.interfaceName,
                tun: $0.tun,
                externalController: $0.externalController
            )
        }
        activeProfileConfig = activeProfileConfig.map {
            MihomoConfig(
                port: $0.port,
                socksPort: $0.socksPort,
                mixedPort: $0.mixedPort,
                redirPort: $0.redirPort,
                tproxyPort: $0.tproxyPort,
                mode: mode.mihomoValue,
                logLevel: $0.logLevel,
                allowLan: $0.allowLan,
                ipv6: $0.ipv6,
                interfaceName: $0.interfaceName,
                tun: $0.tun,
                externalController: $0.externalController
            )
        }
        updateAPIEndpoint(from: activeProfileConfig ?? config)
        addEvent(source: "Mode", title: "切换为\(mode.title)", detail: mode.detail)
        guard core.status.isHealthy else {
            AppDebugLog.mode("已保存出口模式偏好=\(mode.mihomoValue)，内核未运行，待启动后同步")
            showToast("模式偏好已保存，启动内核后生效")
            return
        }
        AppDebugLog.mode("请求切换出口模式 -> \(mode.mihomoValue) @ \(api.baseURL.absoluteString)")
        scheduleModeUpdate(mode)
    }

    static func verifyAppliedForwardingMode(expected: MihomoMode, configMode: String?) -> Bool {
        MihomoMode(configValue: configMode) == expected
    }

    func selectProxy(groupID: String, proxyName: String) async {
        guard core.status.isHealthy else {
            showToast("请先启动内核")
            return
        }
        let apiGroupName = apiProxyGroupName(for: groupID)
        do {
            try await api.selectProxy(groupName: apiGroupName, proxyName: proxyName)
            proxyGroups = proxyGroups.map { group in
                updatedProxyGroup(group, groupID: groupID, proxyName: proxyName) ?? group
            }
            activeProfileProxyGroups = activeProfileProxyGroups.map { group in
                updatedProxyGroup(group, groupID: groupID, proxyName: proxyName) ?? group
            }
            addEvent(source: "Proxy", title: "切换代理", detail: "\(apiGroupName) → \(proxyName)")
            showToast("已切换到 \(proxyName)")
            await refresh()
        } catch {
            addEvent(source: "Proxy", title: "代理切换失败", detail: error.localizedDescription)
            showToast("代理切换失败")
        }
    }

    private func apiProxyGroupName(for groupID: String) -> String {
        if groupID.caseInsensitiveCompare("GLOBAL") == .orderedSame,
           !proxyGroups.contains(where: { Self.isGlobalProxyGroup($0) }),
           !activeProfileProxyGroups.contains(where: { Self.isGlobalProxyGroup($0) }) {
            return (proxyGroups.first ?? activeProfileProxyGroups.first)?.id ?? groupID
        }
        return proxyGroups.first(where: { $0.id == groupID || $0.name == groupID })?.id
            ?? activeProfileProxyGroups.first(where: { $0.id == groupID || $0.name == groupID })?.id
            ?? groupID
    }

    private func updatedProxyGroup(_ group: ProxyGroupItem, groupID: String, proxyName: String) -> ProxyGroupItem? {
        guard group.id == groupID || group.name == groupID else { return nil }
        return ProxyGroupItem(
            id: group.id,
            name: group.name,
            type: group.type,
            now: proxyName,
            all: group.all,
            nodes: group.nodes,
            aliveCount: group.aliveCount,
            testURL: group.testURL
        )
    }

    func testDelay(for group: ProxyGroupItem) async {
        guard core.status.isHealthy else {
            showToast("请先启动内核，再测试代理延迟")
            return
        }
        guard testingDelayGroupID == nil else { return }

        let seedNodes = Self.resolvedProxyNodes(for: group)
        guard !seedNodes.isEmpty else { return }

        testingDelayGroupID = group.id
        pollTask?.cancel()
        pollTask = nil
        defer {
            testingDelayGroupID = nil
            startPolling()
        }

        let nodes = await testGroupDelayNodes(for: group, seedNodes: seedNodes)
        let successCount = nodes.filter { ($0.delay ?? 0) > 0 }.count

        if let index = proxyGroups.firstIndex(where: { $0.id == group.id }) {
            updateProxyGroup(at: index, nodes: nodes)
        } else {
            updateProxyGroupNodes(groupID: group.id, nodes: nodes)
        }

        if successCount == 0 {
            addEvent(source: "Proxy", title: "测速失败", detail: "\(group.name) · 未获取到有效延迟")
            showToast("测速失败，请确认内核已连接")
            return
        }

        addEvent(
            source: "Proxy",
            title: "测速完成",
            detail: "\(group.name) · \(successCount)/\(seedNodes.count) 个节点"
        )
    }

    /// Prefer mihomo batch `/group/{name}/delay`, then fall back to Kumo-style sequential proxy tests.
    private func testGroupDelayNodes(for group: ProxyGroupItem, seedNodes: [ProxyGroupNode]) async -> [ProxyGroupNode] {
        let apiGroupName = apiProxyGroupName(for: group.id)
        let testURL = MihomoAPI.resolvedDelayTestURL(group.testURL)
        let timeoutMs = MihomoAPI.recommendedGroupDelayTimeoutMs(nodeCount: seedNodes.count)

        if let delayMap = try? await api.groupDelay(groupName: apiGroupName, testURL: testURL, timeoutMs: timeoutMs),
           !delayMap.isEmpty {
            return seedNodes.map { Self.proxyGroupNode(from: $0, batchDelayMap: delayMap) }
        }

        addEvent(source: "Proxy", title: "组测速 API 不可用", detail: "回退为逐节点测速")

        var nodes: [ProxyGroupNode] = []
        for node in seedNodes {
            let measured = try? await api.proxyDelay(
                proxyName: node.name,
                testURL: testURL,
                timeoutMs: MihomoAPI.fallbackProxyDelayTimeoutMs
            )
            nodes.append(Self.proxyGroupNode(from: node, measuredDelay: measured))
        }
        return nodes
    }

    private func updateProxyGroup(at index: Int, nodes: [ProxyGroupNode]) {
        let group = proxyGroups[index]
        proxyGroups[index] = ProxyGroupItem(
            id: group.id,
            name: group.name,
            type: group.type,
            now: group.now,
            all: group.all,
            nodes: nodes,
            aliveCount: nodes.filter { $0.alive != false }.count,
            testURL: group.testURL
        )
        for node in nodes {
            proxyNodeStatuses[node.name] = ProxyNodeRuntimeStatus(delay: node.delay, alive: node.alive)
        }
    }

    private static func proxyGroupNode(from node: ProxyGroupNode, batchDelayMap: [String: Int]) -> ProxyGroupNode {
        guard let measured = batchDelayMap[node.name] else {
            return ProxyGroupNode(name: node.name, type: node.type, delay: 0, alive: false)
        }
        if measured > 0 {
            return ProxyGroupNode(name: node.name, type: node.type, delay: measured, alive: true)
        }
        return ProxyGroupNode(name: node.name, type: node.type, delay: measured, alive: false)
    }

    /// Kumo-style merge: keep the previous delay when a single-node test fails.
    private static func proxyGroupNode(from node: ProxyGroupNode, measuredDelay: Int?) -> ProxyGroupNode {
        guard let measured = measuredDelay else {
            return node
        }
        if measured > 0 {
            return ProxyGroupNode(name: node.name, type: node.type, delay: measured, alive: true)
        }
        return ProxyGroupNode(name: node.name, type: node.type, delay: measured, alive: false)
    }

    private static func resolvedProxyNodes(for group: ProxyGroupItem) -> [ProxyGroupNode] {
        if !group.nodes.isEmpty {
            return group.nodes
        }
        return (group.all.isEmpty ? [group.now] : group.all).map {
            ProxyGroupNode(name: $0, type: nil, delay: nil, alive: nil)
        }
    }

    func closeConnection(_ connection: MihomoConnection) async {
        do {
            try await api.closeConnection(id: connection.id)
            connections = ConnectionsSnapshot(
                downloadTotal: connections.downloadTotal,
                uploadTotal: connections.uploadTotal,
                connections: connections.connections.filter { $0.id != connection.id }
            )
            addEvent(source: "Connection", title: "关闭连接", detail: connection.displayHost)
        } catch {
            addEvent(source: "Connection", title: "关闭连接失败", detail: error.localizedDescription)
        }
    }

    func closeAllConnections() async {
        do {
            try await api.closeAllConnections()
            connections = ConnectionsSnapshot(downloadTotal: connections.downloadTotal, uploadTotal: connections.uploadTotal, connections: [])
            addEvent(source: "Connection", title: "关闭全部连接", detail: "已请求内核断开当前连接。")
        } catch {
            addEvent(source: "Connection", title: "关闭连接失败", detail: error.localizedDescription)
        }
    }

    func setRule(_ rule: RuleItem, isEnabled: Bool) async {
        guard let profileID = currentProfile?.id else {
            showToast("没有当前配置")
            return
        }

        do {
            suppressFileChangeNotifications()
            try profileRepository.setRuleDeletedOverride(
                profileID: profileID,
                rule: rule.overrideRuleText,
                isDeleted: !isEnabled
            )
            refreshProfiles()
            updateActiveProfileFileMonitor()
            loadActiveProfileSnapshot()
            await applyRuleToggleRuntimeChange(rule: rule, isEnabled: isEnabled)
            addEvent(source: "Rule", title: isEnabled ? "启用规则" : "关闭规则", detail: rule.overrideRuleText)
        } catch {
            showToast("规则修改失败")
            addEvent(source: "Rule", title: "规则修改失败", detail: error.localizedDescription)
        }
    }

    func refreshRules() async {
        guard core.status.isHealthy else { return }
        do {
            async let refreshedRules = api.rules()
            async let refreshedProviders = api.ruleProviders()
            rules = try await refreshedRules
            ruleProviders = (try? await refreshedProviders) ?? ruleProviders
        } catch {
            showToast("规则刷新失败")
            addEvent(source: "Rule", title: "规则刷新失败", detail: error.localizedDescription)
        }
    }

    func isUpdatingRuleProvider(_ provider: RuleProviderItem) -> Bool {
        updatingRuleProviderNames.contains(provider.name)
    }

    func updateRuleProvider(_ provider: RuleProviderItem) async {
        guard core.status.isHealthy else { return }
        updatingRuleProviderNames.insert(provider.name)
        defer { updatingRuleProviderNames.remove(provider.name) }

        do {
            try await api.updateRuleProvider(name: provider.name)
            async let refreshedRules = api.rules()
            async let refreshedProviders = api.ruleProviders()
            if let fetchedRules = try? await refreshedRules {
                rules = fetchedRules
            }
            ruleProviders = try await refreshedProviders
            addEvent(source: "Rule", title: "更新规则集合", detail: provider.name)
        } catch {
            showToast("规则集合更新失败")
            addEvent(source: "Rule", title: "规则集合更新失败", detail: error.localizedDescription)
        }
    }

    func updateAllRuleProviders() async {
        guard core.status.isHealthy, !ruleProviders.isEmpty else { return }
        let providers = ruleProviders
        updatingRuleProviderNames.formUnion(providers.map(\.name))
        defer { updatingRuleProviderNames.subtract(providers.map(\.name)) }

        do {
            for provider in providers {
                try await api.updateRuleProvider(name: provider.name)
            }
            async let refreshedRules = api.rules()
            async let refreshedProviders = api.ruleProviders()
            if let fetchedRules = try? await refreshedRules {
                rules = fetchedRules
            }
            ruleProviders = try await refreshedProviders
            addEvent(source: "Rule", title: "更新全部规则集合", detail: "\(providers.count) 个 provider")
        } catch {
            showToast("规则集合更新失败")
            addEvent(source: "Rule", title: "规则集合更新失败", detail: error.localizedDescription)
        }
    }

    func addRuleOverride(_ ruleText: String, placement: RuleOverridePlacement) async {
        let rule = ruleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty else {
            showToast("规则不能为空")
            return
        }
        guard let profileID = currentProfile?.id else {
            showToast("没有当前配置")
            return
        }

        do {
            suppressFileChangeNotifications()
            try profileRepository.addRuleOverride(profileID: profileID, rule: rule, placement: placement)
            refreshProfiles()
            updateActiveProfileFileMonitor()
            loadActiveProfileSnapshot()
            await applyRuleOverrideRuntimeChange(toastMessage: "已添加规则")
            addEvent(source: "Rule", title: "添加配置规则", detail: rule)
        } catch {
            showToast("添加规则失败")
            addEvent(source: "Rule", title: "添加规则失败", detail: error.localizedDescription)
        }
    }

    func loadLogs() {
        loadLogs(source: LogPreference.defaultSource)
    }

    func loadLogs(source: LogSourceFilter) {
        logs = CoreLogSupport.recentLogs(
            coreFile: core.coreLogFile,
            appFile: core.appLogFile,
            source: source,
            limit: 500
        )
    }

    func startLogStream(level: LogLevelFilter) {
        guard core.status.isHealthy else { return }
        logStreamTask?.cancel()
        isStreamingLogs = true
        let selectedLevel = level.controllerValue ?? displayedConfig?.logLevel
        AppLogSupport.info(
            "开始跟随 mihomo 日志，level=\(selectedLevel ?? "config")",
            module: "Logs",
            logsDirectory: core.logsDirectory
        )
        logStreamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await log in api.logStream(level: selectedLevel) {
                    appendLog(log)
                }
            } catch {
                isStreamingLogs = false
                AppLogSupport.error("mihomo 日志流断开: \(error.localizedDescription)", module: "Logs", logsDirectory: core.logsDirectory)
            }
        }
    }

    func stopLogStream() {
        logStreamTask?.cancel()
        logStreamTask = nil
        isStreamingLogs = false
        AppLogSupport.info("停止跟随 mihomo 日志", module: "Logs", logsDirectory: core.logsDirectory)
    }

    func stopTrafficStream() {
        trafficStreamTask?.cancel()
        trafficStreamTask = nil
        traffic = TrafficSnapshot()
        trafficHistory = []
    }

    private func startTrafficStream() {
        guard core.status.isHealthy else { return }
        guard trafficStreamTask == nil else { return }
        trafficStreamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await snapshot in api.trafficStream() {
                    traffic = snapshot
                    appendTrafficSample(from: snapshot)
                }
            } catch is CancellationError {
                return
            } catch {
                traffic = TrafficSnapshot()
                trafficHistory = []
            }
        }
    }

    private func syncTrafficStream() {
        if core.status.isHealthy {
            startTrafficStream()
        } else {
            stopTrafficStream()
        }
    }

    private func appendTrafficSample(from snapshot: TrafficSnapshot) {
        let sample = TrafficSample(
            timestamp: Date(),
            upload: snapshot.up,
            download: snapshot.down
        )
        trafficHistory.append(sample)
        let capacity = 60
        if trafficHistory.count > capacity {
            trafficHistory.removeFirst(trafficHistory.count - capacity)
        }
    }

    func clearLogs() {
        logs = []
    }

    func logFileURL(for source: LogSourceFilter) -> URL {
        switch source {
        case .core:
            return core.coreLogFile
        case .app:
            return core.appLogFile
        case .all:
            return core.runtimeDirectory
        }
    }

    func openLogFile(source: LogSourceFilter) {
        let url = logFileURL(for: source)
        NSWorkspace.shared.open(url)
        AppLogSupport.info("打开日志文件: \(url.path)", module: "Logs", logsDirectory: core.logsDirectory)
    }

    func revealLogFile(source: LogSourceFilter) {
        let url = logFileURL(for: source)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        AppLogSupport.info("在 Finder 中显示日志文件: \(url.path)", module: "Logs", logsDirectory: core.logsDirectory)
    }

    func clearLogFile(source: LogSourceFilter) {
        switch source {
        case .core:
            try? CoreLogSupport.truncate(core.coreLogFile)
        case .app:
            try? CoreLogSupport.truncate(core.appLogFile)
        case .all:
            try? CoreLogSupport.truncate(core.coreLogFile)
            try? CoreLogSupport.truncate(core.appLogFile)
        }
        logs = []
        if source == .core {
            AppLogSupport.warning("已清空日志文件 source=\(source.rawValue)", module: "Logs", logsDirectory: core.logsDirectory)
        }
    }

    func setAllowLan(_ isEnabled: Bool) {
        allowLan = isEnabled
        AppPreferenceStore.setBool(isEnabled, \.allowLan)
        if let index = toggles.firstIndex(where: { $0.id == "allowLan" }) {
            toggles[index].isOn = isEnabled
        }
        config = config.map {
            MihomoConfig(
                port: $0.port,
                socksPort: $0.socksPort,
                mixedPort: $0.mixedPort,
                redirPort: $0.redirPort,
                tproxyPort: $0.tproxyPort,
                mode: $0.mode,
                logLevel: $0.logLevel,
                allowLan: isEnabled,
                ipv6: $0.ipv6,
                interfaceName: $0.interfaceName,
                tun: $0.tun,
                externalController: $0.externalController
            )
        }
        activeProfileConfig = activeProfileConfig.map {
            MihomoConfig(
                port: $0.port,
                socksPort: $0.socksPort,
                mixedPort: $0.mixedPort,
                redirPort: $0.redirPort,
                tproxyPort: $0.tproxyPort,
                mode: $0.mode,
                logLevel: $0.logLevel,
                allowLan: isEnabled,
                ipv6: $0.ipv6,
                interfaceName: $0.interfaceName,
                tun: $0.tun,
                externalController: $0.externalController
            )
        }
        updateAPIEndpoint(from: activeProfileConfig ?? config)
        addEvent(source: "Config", title: "局域网访问\(isEnabled ? "开启" : "关闭")", detail: "allow-lan = \(isEnabled ? "true" : "false")")
        scheduleAllowLanUpdate(isEnabled)
    }

    private func startPolling() {
        pollTask?.cancel()
        guard testingDelayGroupID == nil, core.status.isHealthy else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.testingDelayGroupID == nil, self.core.status.isHealthy {
                    await self.refresh()
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func addEvent(source: String, title: String, detail: String) {
        events.insert(.init(source: source, title: title, detail: detail), at: 0)
        if events.count > 8 {
            events.removeLast(events.count - 8)
        }
    }

    func presentToast(_ message: String) {
        showToast(message)
    }

    private func showToast(_ message: String) {
        toastDismissTask?.cancel()
        toast = AppToast(message: message)
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.toast = nil
                self?.toastDismissTask = nil
            }
        }
    }

    private func startConfigurationFileMonitoring() {
        activeConfigFileMonitor?.stop()
        activeConfigFileMonitor = YAMLFileChangeMonitor(url: core.configFile) { [weak self] in
            Task { @MainActor in
                self?.handleConfigurationFileChange(from: .activeConfig)
            }
        }
        activeConfigFileMonitor?.start()
        updateActiveProfileFileMonitor()
    }

    private func updateActiveProfileFileMonitor() {
        activeProfileFileMonitor?.stop()
        activeProfileFileMonitor = nil

        guard let currentProfile,
              currentProfile.fileURL.path != core.configFile.path,
              FileManager.default.fileExists(atPath: currentProfile.fileURL.path) else {
            return
        }

        activeProfileFileMonitor = YAMLFileChangeMonitor(url: currentProfile.fileURL) { [weak self] in
            Task { @MainActor in
                self?.handleConfigurationFileChange(from: .activeProfile)
            }
        }
        activeProfileFileMonitor?.start()
    }

    private func suppressFileChangeNotifications() {
        suppressFileChangeNotificationsUntil = Date().addingTimeInterval(1.2)
    }

    private var shouldSuppressFileChangeNotification: Bool {
        if isApplyingTunUpdate { return true }
        if isImportingProfile || !refreshingProfileIDs.isEmpty { return true }
        guard let suppressFileChangeNotificationsUntil else { return false }
        return Date() < suppressFileChangeNotificationsUntil
    }

    private func handleConfigurationFileChange(from source: ObservedConfigFile) {
        guard !shouldSuppressFileChangeNotification else { return }
        guard !isApplyingObservedConfigurationChange else {
            pendingObservedConfigurationChange = source
            return
        }
        configReloadTask?.cancel()
        configReloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.applyObservedConfigurationFileChange(from: source)
        }
    }

    private func applyObservedConfigurationFileChange(from source: ObservedConfigFile) async {
        guard !isApplyingObservedConfigurationChange else {
            pendingObservedConfigurationChange = source
            return
        }
        isApplyingObservedConfigurationChange = true
        defer {
            isApplyingObservedConfigurationChange = false
            if let pendingObservedConfigurationChange {
                self.pendingObservedConfigurationChange = nil
                handleConfigurationFileChange(from: pendingObservedConfigurationChange)
            }
        }

        if source == .activeProfile, let currentProfile {
            do {
                suppressFileChangeNotifications()
                core.releaseListeningPorts(for: profileRepository.profileFileURL(id: currentProfile.id))
                try profileRepository.activateProfile(id: currentProfile.id)
            } catch {
                handleObservedConfigurationApplyFailure(error, title: "配置文件更新失败")
                return
            }
        }

        refreshProfiles()
        updateActiveProfileFileMonitor()
        loadActiveProfileSnapshot(resetRuntimeData: true)
        do {
            try await applyReloadAfterObservedConfigurationChange()
            showToast("检测到配置文件修改，已应用新配置")
            addEvent(source: "Config", title: "配置文件已更新", detail: currentProfileName)
        } catch {
            handleObservedConfigurationApplyFailure(error, title: "配置文件应用失败")
        }
    }

    private func handleObservedConfigurationApplyFailure(_ error: Error, title: String) {
        let detail = error.localizedDescription
        showToast(title)
        addEvent(source: "Config", title: title, detail: detail)
        AppLogSupport.error("\(title): \(detail)", module: "Config", logsDirectory: core.logsDirectory)
    }

    private func applyReloadAfterObservedConfigurationChange() async throws {
        let shouldRefreshAfterRestart = core.status.shouldReloadForProfileChange
        if shouldRefreshAfterRestart {
            core.restart()
            try await waitForControllerReadyAfterCoreStart()
        }
        await refresh()
    }

    private func updateAPIEndpoint(from config: MihomoConfig?) {
        if let url = config?.externalControllerURL {
            api.baseURL = url
        } else if let url = activeProfileConfig?.externalControllerURL {
            api.baseURL = url
        }
        if let secret = config?.secret, !secret.isEmpty {
            api.secret = secret
        } else if let secret = activeProfileConfig?.secret, !secret.isEmpty {
            api.secret = secret
        }
    }

    private func loadActiveProfileSnapshot(resetRuntimeData: Bool = false) {
        guard let yaml = try? String(contentsOf: core.configFile, encoding: .utf8) else { return }
        activeProfileConfig = MihomoConfig.parsed(from: yaml)
        updateAPIEndpoint(from: activeProfileConfig)
        activeProfileProxyGroups = ProxyGroupItem.parsed(from: yaml)
        activeProfileNodes = ProxyNodeInfo.parsed(from: yaml)
        if AppPreferenceStore.string(\.forwardingMode) == nil,
           let activeMode = activeProfileConfig?.mode {
            forwardingMode = MihomoMode(configValue: activeMode)
        }
        if let activeAllowLan = activeProfileConfig?.allowLan {
            allowLan = activeAllowLan
            if let index = toggles.firstIndex(where: { $0.id == "allowLan" }) {
                toggles[index].isOn = activeAllowLan
            }
        }
        if let index = toggles.firstIndex(where: { $0.id == "tun" }) {
            toggles[index].isOn = TunPreference.isEnabled
        }
        if resetRuntimeData {
            config = activeProfileConfig
            proxyGroups = []
            proxyNodeStatuses = [:]
            rules = []
            connections = ConnectionsSnapshot(downloadTotal: 0, uploadTotal: 0, connections: [])
            traffic = TrafficSnapshot()
            trafficHistory = []
        }
    }

    private func reloadCoreAfterProfileChange(toastMessage: String? = nil) {
        let shouldRefreshAfterRestart = core.status.shouldReloadForProfileChange
        if core.status.shouldReloadForProfileChange {
            core.restart()
        }
        Task { [weak self] in
            if shouldRefreshAfterRestart {
                try? await self?.waitForControllerReadyAfterCoreStart()
            }
            await self?.refresh()
            if let toastMessage {
                self?.showToast(toastMessage)
            }
        }
    }

    private func applyRuleOverrideRuntimeChange(toastMessage: String) async {
        guard core.status.isHealthy else {
            showToast(toastMessage)
            addEvent(source: "Rule", title: "规则已保存", detail: "内核未运行，将在下次启动时生效。")
            return
        }

        do {
            try await api.reloadConfig(path: core.configFile)
            await refresh()
            showToast(toastMessage)
            addEvent(source: "Rule", title: "规则热更新", detail: "已通过 controller 重新加载 runtime config。")
        } catch {
            showToast("规则已保存，热更新失败")
            addEvent(source: "Rule", title: "规则热更新失败", detail: error.localizedDescription)
            AppLogSupport.error("规则热更新失败: \(error.localizedDescription)", module: "Rule", logsDirectory: core.logsDirectory)
        }
    }

    private func applyRuleToggleRuntimeChange(rule: RuleItem, isEnabled: Bool) async {
        let toastMessage = isEnabled ? "已启用规则" : "已关闭规则"
        guard core.status.isHealthy else {
            showToast(toastMessage)
            addEvent(source: "Rule", title: "规则已保存", detail: "内核未运行，将在下次启动时生效。")
            return
        }

        do {
            try await api.setRuleEnabled(index: rule.index, isEnabled: isEnabled)
            await refreshRules()
            showToast(toastMessage)
            addEvent(source: "Rule", title: "规则热更新", detail: "已通过 controller 更新规则状态。")
        } catch {
            do {
                try await api.reloadConfig(path: core.configFile)
                await refreshRules()
                showToast(toastMessage)
                addEvent(source: "Rule", title: "规则热更新", detail: "规则状态接口失败，已重新加载 runtime config。")
            } catch {
                await refreshRules()
                showToast("规则已保存，热更新失败")
                addEvent(source: "Rule", title: "规则热更新失败", detail: error.localizedDescription)
                AppLogSupport.error("规则热更新失败: \(error.localizedDescription)", module: "Rule", logsDirectory: core.logsDirectory)
            }
        }
    }

    private func applySavedModeIfNeeded() async {
        guard core.status.isHealthy, !suppressModeDriftSync else { return }
        let currentMode = MihomoMode(configValue: config?.mode)
        guard currentMode != forwardingMode else { return }
        AppDebugLog.mode("检测到模式漂移，同步 saved=\(forwardingMode.mihomoValue) controller=\(currentMode.mihomoValue)")
        do {
            try await api.updateMode(forwardingMode)
            config = config.map {
                MihomoConfig(
                    port: $0.port,
                    socksPort: $0.socksPort,
                    mixedPort: $0.mixedPort,
                    redirPort: $0.redirPort,
                    tproxyPort: $0.tproxyPort,
                    mode: forwardingMode.mihomoValue,
                    logLevel: $0.logLevel,
                    allowLan: $0.allowLan,
                    ipv6: $0.ipv6,
                    interfaceName: $0.interfaceName,
                    tun: $0.tun,
                    externalController: $0.externalController
                )
            }
            updateAPIEndpoint(from: config)
            if Self.verifyAppliedForwardingMode(expected: forwardingMode, configMode: config?.mode) {
                AppDebugLog.mode("模式漂移同步成功，当前=\(config?.mode ?? forwardingMode.mihomoValue)")
            } else {
                AppDebugLog.mode("模式漂移同步后校验失败，期望=\(forwardingMode.mihomoValue) 实际=\(config?.mode ?? "nil")")
            }
        } catch {
            AppDebugLog.mode("模式漂移同步失败：\(error.localizedDescription)")
            addEvent(source: "Mode", title: "模式同步失败", detail: error.localizedDescription)
        }
    }

    private func applySavedAllowLanIfNeeded() async {
        guard core.status.isHealthy else { return }
        guard config?.allowLan != allowLan else { return }
        do {
            try await api.updateAllowLan(allowLan)
            config = config.map {
                MihomoConfig(
                    port: $0.port,
                    socksPort: $0.socksPort,
                    mixedPort: $0.mixedPort,
                    redirPort: $0.redirPort,
                    tproxyPort: $0.tproxyPort,
                    mode: $0.mode,
                    logLevel: $0.logLevel,
                    allowLan: allowLan,
                    ipv6: $0.ipv6,
                    interfaceName: $0.interfaceName,
                    tun: $0.tun,
                    externalController: $0.externalController
                )
            }
            updateAPIEndpoint(from: config)
        } catch {
            addEvent(source: "Config", title: "局域网访问同步失败", detail: error.localizedDescription)
        }
    }

    private func scheduleModeUpdate(_ mode: MihomoMode) {
        modeUpdateTask?.cancel()
        AppDebugLog.mode("开始 API 同步出口模式 -> \(mode.mihomoValue)")
        modeUpdateTask = Task { [weak self] in
            guard let self else { return }
            guard core.status.isHealthy else {
                AppDebugLog.mode("取消 API 同步：内核未就绪")
                return
            }
            do {
                try await api.updateMode(mode)
                AppDebugLog.mode("PATCH /configs 成功，目标模式=\(mode.mihomoValue)")
                config = config.map { current in
                    MihomoConfig(
                        port: current.port,
                        socksPort: current.socksPort,
                        mixedPort: current.mixedPort,
                        redirPort: current.redirPort,
                        tproxyPort: current.tproxyPort,
                        mode: mode.mihomoValue,
                        logLevel: current.logLevel,
                        allowLan: current.allowLan,
                        ipv6: current.ipv6,
                        interfaceName: current.interfaceName,
                        tun: current.tun,
                        externalController: current.externalController,
                        secret: current.secret
                    )
                }
                activeProfileConfig = activeProfileConfig.map { current in
                    MihomoConfig(
                        port: current.port,
                        socksPort: current.socksPort,
                        mixedPort: current.mixedPort,
                        redirPort: current.redirPort,
                        tproxyPort: current.tproxyPort,
                        mode: mode.mihomoValue,
                        logLevel: current.logLevel,
                        allowLan: current.allowLan,
                        ipv6: current.ipv6,
                        interfaceName: current.interfaceName,
                        tun: current.tun,
                        externalController: current.externalController,
                        secret: current.secret
                    )
                }
                await refresh()
                await testOverviewProxyGroupDelayIfNeeded()
                if Self.verifyAppliedForwardingMode(expected: mode, configMode: config?.mode) {
                    AppDebugLog.mode("出口模式切换成功，controller 当前模式=\(config?.mode ?? mode.mihomoValue)")
                } else {
                    let actual = config?.mode ?? "nil"
                    AppDebugLog.mode("出口模式切换校验失败，期望=\(mode.mihomoValue) 实际=\(actual)")
                    await revertForwardingModeFromController(failedTarget: mode)
                    addEvent(source: "Mode", title: "模式切换未生效", detail: "期望 \(mode.mihomoValue)，实际 \(actual)")
                    showToast("模式切换未生效")
                }
            } catch {
                if core.status.isHealthy {
                    AppDebugLog.mode("出口模式切换失败：\(error.localizedDescription)")
                    await revertForwardingModeFromController(failedTarget: mode)
                    addEvent(source: "Mode", title: "模式切换失败", detail: error.localizedDescription)
                    showToast("模式切换失败")
                }
            }
        }
    }

    private func testOverviewProxyGroupDelayIfNeeded() async {
        let mode = effectiveForwardingMode
        guard mode != .direct else { return }
        let groups = runtimeProxyGroupsForCurrentMode
        guard let group = Self.overviewProxyGroup(for: mode, groups: groups) else { return }
        await testDelay(for: group)
    }

    private func revertForwardingModeFromController(failedTarget: MihomoMode) async {
        suppressModeDriftSync = true
        defer { suppressModeDriftSync = false }
        await refresh()
        let controllerMode = MihomoMode(configValue: config?.mode)
        guard forwardingMode != controllerMode else {
            AppDebugLog.mode("切换失败后状态一致，保持 controller 模式=\(controllerMode.mihomoValue)")
            return
        }
        forwardingMode = controllerMode
        AppPreferenceStore.setString(controllerMode.rawValue, \.forwardingMode)
        AppDebugLog.mode("切换失败已回滚 UI 模式 \(failedTarget.mihomoValue) -> \(controllerMode.mihomoValue)")
    }

    private func scheduleAllowLanUpdate(_ isEnabled: Bool) {
        allowLanUpdateTask?.cancel()
        allowLanUpdateTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await api.updateAllowLan(isEnabled)
            } catch {
                if core.status.isHealthy {
                    addEvent(source: "Config", title: "局域网访问修改失败", detail: error.localizedDescription)
                }
            }
        }
    }

    static func makeProxyGroups(
        from response: ProxiesResponse,
        configuredGroups: [ProxyGroupItem] = [],
        delayOverrides: [String: ProxyNodeRuntimeStatus] = [:]
    ) -> [ProxyGroupItem] {
        let runtimeGroups = response.proxies
            .compactMap { key, node -> ProxyGroupItem? in
                guard let type = node.type, node.all?.isEmpty == false, node.hidden != true else { return nil }
                let all = node.all ?? []
                let nodes = all.map { nodeName -> ProxyGroupNode in
                    let runtimeNode = response.proxies[nodeName]
                    let override = delayOverrides[nodeName]
                    let historyDelay = runtimeNode?.history?.last?.delay
                    let delay = historyDelay ?? override?.delay
                    let alive: Bool? = {
                        if let delay {
                            return delay > 0
                        }
                        return runtimeNode?.alive ?? override?.alive
                    }()
                    return ProxyGroupNode(
                        name: nodeName,
                        type: runtimeNode?.type,
                        delay: delay,
                        alive: alive
                    )
                }
                return ProxyGroupItem(
                    id: key,
                    name: node.name ?? key,
                    type: type,
                    now: node.now ?? "-",
                    all: all,
                    nodes: nodes,
                    aliveCount: nodes.filter { $0.alive != false }.count,
                    testURL: node.testURL
                )
            }

        guard !configuredGroups.isEmpty else {
            return runtimeGroups.sorted { lhs, rhs in
                if isGlobalProxyGroup(lhs) { return true }
                if isGlobalProxyGroup(rhs) { return false }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }

        var consumedIDs = Set<String>()
        let configuredOrder = configuredGroups.compactMap { configuredGroup -> ProxyGroupItem? in
            guard let group = runtimeGroups.first(where: { runtimeGroup in
                !consumedIDs.contains(runtimeGroup.id)
                    && (runtimeGroup.id == configuredGroup.id
                        || runtimeGroup.name == configuredGroup.name
                        || runtimeGroup.id.caseInsensitiveCompare(configuredGroup.id) == .orderedSame
                        || runtimeGroup.name.caseInsensitiveCompare(configuredGroup.name) == .orderedSame)
            }) else {
                return nil
            }
            consumedIDs.insert(group.id)
            return group
        }
        let appendedGroups = runtimeGroups
            .filter { !consumedIDs.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return configuredOrder + appendedGroups
    }

    private static func makeProxyNodeStatuses(from response: ProxiesResponse) -> [String: ProxyNodeRuntimeStatus] {
        response.proxies.reduce(into: [String: ProxyNodeRuntimeStatus]()) { result, item in
            let name = item.value.name ?? item.key
            let delay = item.value.history?.last?.delay
            let alive: Bool? = {
                if let delay {
                    return delay > 0
                }
                return item.value.alive
            }()
            result[name] = ProxyNodeRuntimeStatus(delay: delay, alive: alive)
        }
    }

    private static func formatBytes(_ value: Int) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var number = Double(value)
        var index = 0
        while number >= 1024, index < units.count - 1 {
            number /= 1024
            index += 1
        }
        if index == 0 {
            return "\(Int(number)) \(units[index])"
        }
        return String(format: "%.1f %@", number, units[index])
    }

    private static func mergedProxyNodeStatuses(
        existing: [String: ProxyNodeRuntimeStatus],
        fetched: [String: ProxyNodeRuntimeStatus]
    ) -> [String: ProxyNodeRuntimeStatus] {
        var merged = fetched
        for (name, status) in existing {
            guard let delay = status.delay, delay > 0 else { continue }
            let fetchedDelay = fetched[name]?.delay ?? 0
            if fetchedDelay <= 0 {
                merged[name] = status
            }
        }
        return merged
    }

    private func updateProxyGroupNodes(groupID: String, nodes: [ProxyGroupNode]) {
        let updatedGroup = { (group: ProxyGroupItem) -> ProxyGroupItem in
            guard group.id == groupID else { return group }
            return ProxyGroupItem(
                id: group.id,
                name: group.name,
                type: group.type,
                now: group.now,
                all: group.all,
                nodes: nodes,
                aliveCount: nodes.filter { $0.alive != false }.count,
                testURL: group.testURL
            )
        }
        proxyGroups = proxyGroups.map(updatedGroup)
        activeProfileProxyGroups = activeProfileProxyGroups.map(updatedGroup)
        for node in nodes {
            proxyNodeStatuses[node.name] = ProxyNodeRuntimeStatus(delay: node.delay, alive: node.alive)
        }
    }

    private func appendLog(_ log: CoreLogEntry) {
        logs.append(log)
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }
}
