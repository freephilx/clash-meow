import Foundation
import Combine

struct AppToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

@MainActor
final class AppState: ObservableObject {
    private static let forwardingModeKey = "mihomo.forwardingMode"
    private static let allowLanKey = "mihomo.allowLan"
    private static let systemProxyNetworkServiceKey = "mihomo.systemProxyNetworkService"

    @Published var core = MihomoCoreManager()
    @Published var config: MihomoConfig?
    @Published var version: MihomoVersion?
    @Published var traffic = TrafficSnapshot()
    @Published var trafficHistory: [TrafficSample] = []
    @Published var connections = ConnectionsSnapshot(downloadTotal: 0, uploadTotal: 0, connections: [])
    @Published var proxyGroups: [ProxyGroupItem] = []
    @Published var rules: [RuleItem] = []
    @Published var logs: [CoreLogEntry] = []
    @Published var isStreamingLogs = false
    @Published private(set) var testingDelayGroupID: String?
    @Published var activeProfileConfig: MihomoConfig?
    @Published var activeProfileProxyGroups: [ProxyGroupItem] = []
    @Published var activeProfileNodes: [ProxyNodeInfo] = []
    @Published var proxyNodeStatuses: [String: ProxyNodeRuntimeStatus] = [:]
    @Published var profiles: [ClashMeowProfileSummary] = []
    @Published var toast: AppToast?
    @Published var isImportingProfile = false
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
    private var configReloadTask: Task<Void, Never>?
    private var activeConfigFileMonitor: YAMLFileChangeMonitor?
    private var activeProfileFileMonitor: YAMLFileChangeMonitor?
    private var suppressFileChangeNotificationsUntil: Date?
    private var suppressModeDriftSync = false
    private var cancellables = Set<AnyCancellable>()

    var isTestingDelay: Bool {
        testingDelayGroupID != nil
    }

    func isTestingDelay(groupID: String) -> Bool {
        testingDelayGroupID == groupID
    }

    private var profileRepository: ProfileRepository {
        ProfileRepository(configDirectory: core.configDirectory, activeConfigFile: core.configFile)
    }

    private enum ObservedConfigFile {
        case activeConfig
        case activeProfile
    }

    init() {
        let savedMode = UserDefaults.standard.string(forKey: Self.forwardingModeKey)
        self.forwardingMode = MihomoMode(rawValue: savedMode ?? "") ?? .rule
        self.allowLan = UserDefaults.standard.object(forKey: Self.allowLanKey) as? Bool ?? false
        let savedSystemProxy = SystemProxyPreference.isEnabled
        let savedTun = TunPreference.isEnabled
        self.systemProxyEnabled = savedSystemProxy
        self.toggles = [
            .init(id: "dns", title: "DNS", subtitle: "DNS 解析与 nameserver 配置状态。", systemImage: "network", isOn: true),
            .init(id: "allowLan", title: "允许局域网访问", subtitle: "允许局域网设备连接本机混合端口。", systemImage: "rectangle.connected.to.line.below", isOn: self.allowLan),
            .init(id: "proxy", title: "系统代理", subtitle: "将系统网络设置指向本机混合端口。", systemImage: "globe", isOn: savedSystemProxy),
            .init(id: "tun", title: "TUN", subtitle: "系统栈、自动路由与虚拟网卡。", systemImage: "antenna.radiowaves.left.and.right", isOn: savedTun)
        ]

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
            return Self.proxyGroupsWithGlobalFirst(
                groups: groups,
                profileNodes: activeProfileNodes,
                statuses: proxyNodeStatuses
            )
            .sorted { lhs, rhs in
                if Self.isGlobalProxyGroup(lhs) { return true }
                if Self.isGlobalProxyGroup(rhs) { return false }
                return false
            }
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
            return Self.proxyGroupsWithGlobalFirst(
                groups: groups,
                profileNodes: activeProfileNodes,
                statuses: proxyNodeStatuses
            )
        }
        return groups
    }

    private static func isGlobalProxyGroup(_ group: ProxyGroupItem) -> Bool {
        group.id.caseInsensitiveCompare("GLOBAL") == .orderedSame
            || group.name.caseInsensitiveCompare("GLOBAL") == .orderedSame
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

        #if DEBUG
        if DebugMockOverviewPreference.isEnabled {
            enableDebugMockOverviewYAMLProfile()
            return
        }
        #endif

        refreshProfiles()
        loadActiveProfileSnapshot()
        startConfigurationFileMonitoring()
        addEvent(source: "Core", title: core.status.title, detail: coreSubtitle)

        if CoreAutoStartManager.isEnabled {
            connect(recordPreference: false)
            try? await Task.sleep(for: .milliseconds(800))
        }

        if core.status.isHealthy {
            await refresh()
        }
        await applySavedNetworkPreferences()
    }

    func applyDashboardDemo() {
        DashboardDemoData.apply(to: self)
        addEvent(source: "Core", title: core.status.title, detail: coreSubtitle)
    }

    func setDemoPresentationFlags(systemProxyEnabled: Bool) {
        self.systemProxyEnabled = systemProxyEnabled
    }

    #if DEBUG
    func setDebugMockOverviewYAMLProfileEnabled(_ isEnabled: Bool) {
        DebugMockOverviewPreference.setEnabled(isEnabled)
        if isEnabled {
            enableDebugMockOverviewYAMLProfile()
        } else {
            disableDebugMockOverviewYAMLProfile()
        }
    }

    private func enableDebugMockOverviewYAMLProfile() {
        do {
            suppressFileChangeNotifications()
            let summary = try profileRepository.upsertDebugMockProfile(
                id: DashboardDemoData.mockProfileID,
                name: DashboardDemoData.mockProfileName,
                yaml: DashboardDemoData.mockProfileYAML,
                subscriptionUserInfo: DashboardDemoData.mockSubscriptionUserInfo
            )
            refreshProfiles()
            updateActiveProfileFileMonitor()
            loadActiveProfileSnapshot(resetRuntimeData: true)
            applyDashboardDemo()
            refreshProfiles()
            addEvent(source: "Debug", title: "Mock YAML 已启用", detail: summary.name)
            showToast("已启用 Mock 概览 YAML")
        } catch {
            DebugMockOverviewPreference.setEnabled(false)
            showToast(error.localizedDescription)
        }
    }

    private func disableDebugMockOverviewYAMLProfile() {
        do {
            suppressFileChangeNotifications()
            if profiles.contains(where: { $0.id == DashboardDemoData.mockProfileID }) {
                _ = try profileRepository.deleteProfile(id: DashboardDemoData.mockProfileID)
            } else {
                _ = try? profileRepository.deleteProfile(id: DashboardDemoData.mockProfileID)
            }
            core.clearDemoPresentation()
            refreshProfiles()
            updateActiveProfileFileMonitor()
            loadActiveProfileSnapshot(resetRuntimeData: true)
            addEvent(source: "Debug", title: "Mock YAML 已关闭", detail: currentProfileName)
            showToast("已关闭 Mock 概览 YAML")
        } catch {
            showToast(error.localizedDescription)
        }
    }
    #endif

    func connect(recordPreference: Bool = true) {
        guard !DashboardDemoMode.isEnabled else { return }
        loadActiveProfileSnapshot()
        core.start()
        if recordPreference {
            CoreAutoStartManager.setEnabled(true)
        }
        addEvent(source: "Core", title: "启动内核", detail: "使用 \(currentProfileName) 作为配置文件。")
        syncTrafficStream()
        if SystemProxyPreference.isEnabled {
            setSystemProxyEnabled(true, recordPreference: false)
        }
    }

    func disconnect(recordPreference: Bool = true) {
        guard !DashboardDemoMode.isEnabled else { return }
        if systemProxyEnabled {
            systemProxyUpdateTask?.cancel()
            systemProxyUpdateTask = Task { [weak self] in
                try? await self?.applySystemProxy(false)
            }
            systemProxyEnabled = false
        }
        stopTrafficStream()
        stopPolling()
        core.stop()
        if recordPreference {
            CoreAutoStartManager.setEnabled(false)
        }
        addEvent(source: "Core", title: "停止内核", detail: "本地内核进程已停止。")
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
                delayOverrides: self.proxyNodeStatuses
            )
            self.rules = (try? await rules) ?? self.rules
            syncTrafficStream()
            await applySavedModeIfNeeded()
            await applySavedAllowLanIfNeeded()
        } catch {
            loadActiveProfileSnapshot()
            addEvent(source: "Core", title: "API 暂不可用", detail: error.localizedDescription)
        }
    }

    func refreshProfiles() {
        do {
            profiles = try profileRepository.listProfiles()
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
        toggles[index].isOn = isOn
        switch toggle.id {
        case "allowLan":
            setAllowLan(isOn)
        case "proxy":
            setSystemProxyEnabled(isOn)
        case "tun":
            setTunEnabled(isOn)
        default:
            addEvent(source: "Proxy", title: "\(toggle.title)\(isOn ? "开启" : "关闭")", detail: toggle.subtitle)
        }
    }

    func setSystemProxyEnabled(_ isEnabled: Bool, recordPreference: Bool = true) {
        if recordPreference {
            SystemProxyPreference.setEnabled(isEnabled)
        }
        systemProxyEnabled = isEnabled
        if let index = toggles.firstIndex(where: { $0.id == "proxy" }) {
            toggles[index].isOn = isEnabled
        }

        if isEnabled, !core.status.isHealthy {
            showToast("请先启动内核")
            setSystemProxyEnabled(false)
            return
        }

        systemProxyUpdateTask?.cancel()
        systemProxyUpdateTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.applySystemProxy(isEnabled)
                addEvent(
                    source: "Proxy",
                    title: "系统代理\(isEnabled ? "开启" : "关闭")",
                    detail: isEnabled ? "127.0.0.1:\(systemProxyPort)" : "已恢复系统网络设置"
                )
            } catch {
                systemProxyEnabled = false
                if recordPreference {
                    SystemProxyPreference.setEnabled(false)
                }
                if let index = toggles.firstIndex(where: { $0.id == "proxy" }) {
                    toggles[index].isOn = false
                }
                addEvent(source: "Proxy", title: "系统代理设置失败", detail: error.localizedDescription)
                showToast("系统代理设置失败")
            }
        }
    }

    func setTunEnabled(_ isEnabled: Bool, recordPreference: Bool = true) {
        if recordPreference {
            TunPreference.setEnabled(isEnabled)
        }
        if let index = toggles.firstIndex(where: { $0.id == "tun" }) {
            toggles[index].isOn = isEnabled
        }

        tunUpdateTask?.cancel()
        tunUpdateTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await applyTunEnabled(isEnabled)
                addEvent(
                    source: "TUN",
                    title: "TUN \(isEnabled ? "开启" : "关闭")",
                    detail: isEnabled ? tunDevice : "已写入配置并重启内核"
                )
            } catch {
                if recordPreference {
                    setTunEnabled(!isEnabled, recordPreference: false)
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
        let currentTun = activeProfileConfig?.tun?.enable ?? false
        if desiredTun != currentTun {
            do {
                try await applyTunEnabled(desiredTun, restartIfNeeded: core.status.isHealthy)
                if let index = toggles.firstIndex(where: { $0.id == "tun" }) {
                    toggles[index].isOn = desiredTun
                }
            } catch {
                addEvent(source: "TUN", title: "TUN 自动应用失败", detail: error.localizedDescription)
            }
        }
    }

    private func applySystemProxy(_ isEnabled: Bool) async throws {
        let savedService = UserDefaults.standard.string(forKey: Self.systemProxyNetworkServiceKey)
        let configuration = try systemProxyController.resolvedConfiguration(
            port: systemProxyPort,
            networkService: savedService
        )
        try systemProxyController.setEnabled(isEnabled, configuration: configuration)
        UserDefaults.standard.set(configuration.networkService, forKey: Self.systemProxyNetworkServiceKey)
    }

    private func disableSystemProxySynchronously() {
        let savedService = UserDefaults.standard.string(forKey: Self.systemProxyNetworkServiceKey)
        let port = systemProxyPort
        if let configuration = try? systemProxyController.resolvedConfiguration(
            port: port,
            networkService: savedService
        ) {
            try? systemProxyController.setEnabled(false, configuration: configuration)
        }
        systemProxyEnabled = false
    }

    private func applyTunEnabled(_ isEnabled: Bool, restartIfNeeded: Bool = true) async throws {
        suppressFileChangeNotifications()
        let yaml = try String(contentsOf: core.configFile, encoding: .utf8)
        let updated = MihomoYAMLSettings.setTunEnabled(isEnabled, in: yaml)
        try updated.write(to: core.configFile, atomically: true, encoding: .utf8)
        loadActiveProfileSnapshot()
        syncPublishedTunConfig(isEnabled: isEnabled)

        guard restartIfNeeded, core.status.shouldReloadForProfileChange else { return }
        core.releaseListeningPorts()
        core.restart()
        try await Task.sleep(for: .milliseconds(800))
        await refresh()
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
        UserDefaults.standard.set(mode.rawValue, forKey: Self.forwardingModeKey)
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
            addEvent(source: "Proxy", title: "切换节点", detail: "\(apiGroupName) → \(proxyName)")
            showToast("已切换到 \(proxyName)")
            await refresh()
        } catch {
            addEvent(source: "Proxy", title: "节点切换失败", detail: error.localizedDescription)
            showToast("节点切换失败")
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
        guard core.status.isHealthy, testingDelayGroupID == nil else { return }

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
            let measured = try? await api.proxyDelay(proxyName: node.name, testURL: testURL, timeoutMs: 5_000)
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
        do {
            try await api.setRuleEnabled(index: rule.index, isEnabled: isEnabled)
            if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                rules[index].isEnabled = isEnabled
            }
            addEvent(source: "Rule", title: isEnabled ? "启用规则" : "禁用规则", detail: rule.payload.isEmpty ? rule.type : rule.payload)
        } catch {
            addEvent(source: "Rule", title: "规则修改失败", detail: error.localizedDescription)
        }
    }

    func loadLogs() {
        logs = CoreLogSupport.recentLogs(from: core.coreLogFile, limit: 500)
    }

    func startLogStream(level: LogLevelFilter) {
        guard core.status.isHealthy else { return }
        logStreamTask?.cancel()
        isStreamingLogs = true
        let selectedLevel = level.controllerValue ?? displayedConfig?.logLevel
        logStreamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await log in api.logStream(level: selectedLevel) {
                    appendLog(log)
                }
            } catch {
                isStreamingLogs = false
            }
        }
    }

    func stopLogStream() {
        logStreamTask?.cancel()
        logStreamTask = nil
        isStreamingLogs = false
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

    func setAllowLan(_ isEnabled: Bool) {
        allowLan = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.allowLanKey)
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
        if isImportingProfile || !refreshingProfileIDs.isEmpty { return true }
        guard let suppressFileChangeNotificationsUntil else { return false }
        return Date() < suppressFileChangeNotificationsUntil
    }

    private func handleConfigurationFileChange(from source: ObservedConfigFile) {
        guard !shouldSuppressFileChangeNotification else { return }
        configReloadTask?.cancel()
        configReloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.applyObservedConfigurationFileChange(from: source)
        }
    }

    private func applyObservedConfigurationFileChange(from source: ObservedConfigFile) {
        if source == .activeProfile, let currentProfile {
            do {
                suppressFileChangeNotifications()
                core.releaseListeningPorts(for: profileRepository.profileFileURL(id: currentProfile.id))
                try profileRepository.activateProfile(id: currentProfile.id)
            } catch {
                showToast("配置文件更新失败")
                return
            }
        }

        refreshProfiles()
        updateActiveProfileFileMonitor()
        loadActiveProfileSnapshot(resetRuntimeData: true)
        reloadCoreAfterProfileChange(toastMessage: "检测到配置文件修改，已应用新配置")
        addEvent(source: "Config", title: "配置文件已更新", detail: currentProfileName)
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
        if UserDefaults.standard.string(forKey: Self.forwardingModeKey) == nil,
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
                try? await Task.sleep(for: .milliseconds(800))
            }
            await self?.refresh()
            if let toastMessage {
                self?.showToast(toastMessage)
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
        UserDefaults.standard.set(controllerMode.rawValue, forKey: Self.forwardingModeKey)
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

    private static func makeProxyGroups(
        from response: ProxiesResponse,
        delayOverrides: [String: ProxyNodeRuntimeStatus] = [:]
    ) -> [ProxyGroupItem] {
        response.proxies
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
            .sorted { lhs, rhs in
                if lhs.name == "GLOBAL" { return true }
                if rhs.name == "GLOBAL" { return false }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
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
