import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum DouMeowPalette {
    static let accent = Color(hex: 0x00A52A)
    static let orange = Color(hex: 0xFF9E14)
    static let ink = Color(hex: 0x1A1F26)
    static let muted = Color(hex: 0x94A1B3)
    static let faintLine = Color(hex: 0xE0E8F0)
    static let page = Color(hex: 0xF2F5FA)
    static let sidebar = Color(hex: 0xF7FAFC)
    static let sidebarSelection = Color(hex: 0xECEDEF)
    static let card = Color.white
}

private extension Color {
    init(hex: UInt, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

private enum SidebarDestination: String, CaseIterable, Identifiable {
    case overview = "概览"
    case profiles = "配置"
    case proxies = "代理"
    case connections = "连接"
    case logs = "日志"
    case rules = "规则"
    case healthCheck = "健康检查"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .overview: "house"
        case .profiles: "archivebox"
        case .proxies: "point.3.connected.trianglepath.dotted"
        case .connections: "network"
        case .logs: "doc.text.magnifyingglass"
        case .rules: "list.bullet.rectangle"
        case .healthCheck: "heart.text.square"
        }
    }
}

private struct SidebarGroup: Identifiable {
    let id: String
    let title: String
    let destinations: [SidebarDestination]
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selection: SidebarDestination? = .overview

    private let sidebarGroups = [
        SidebarGroup(id: "daily", title: "常用", destinations: [.overview]),
        SidebarGroup(id: "inspect", title: "翻墙", destinations: [.profiles, .proxies, .connections, .rules, .logs])
    ]

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selection) { _, newValue in
            if newValue == nil {
                selection = .overview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DouMeowPalette.page)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sidebarGroups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DouMeowPalette.muted)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 2)

                            ForEach(group.destinations) { destination in
                                SidebarDestinationRow(
                                    destination: destination,
                                    isSelected: selection == destination
                                ) {
                                    selection = destination
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("工具")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DouMeowPalette.muted)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 2)

                        SidebarDestinationRow(
                            destination: .healthCheck,
                            isSelected: selection == .healthCheck
                        ) {
                            selection = .healthCheck
                        }

                        SidebarSettingsRow()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
            }
        }
        .background(DouMeowPalette.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    }

    private var detail: some View {
        ZStack(alignment: .top) {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DouMeowPalette.page)

            if let toast = state.toast {
                AppToastView(toast: toast)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: state.toast)
        .navigationSplitViewColumnWidth(min: 540, ideal: 860)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .overview {
        case .overview:
            DashboardContent(
                openProfiles: { selection = .profiles },
                openProxies: { selection = .proxies }
            )
        case .profiles:
            ProfilesContent()
        case .proxies:
            ProxiesContent()
        case .connections:
            ConnectionsContent()
        case .logs:
            LogsContent()
        case .rules:
            RulesContent()
        case .healthCheck:
            HealthCheckContent()
        }
    }

}

private struct SidebarSettingsRow: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: SettingsView.windowID)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20, height: 20)
                Text("偏好设置")
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                Text("⌘,")
                    .font(.system(size: 11))
                    .foregroundStyle(DouMeowPalette.muted)
            }
            .foregroundStyle(DouMeowPalette.ink)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("偏好设置")
    }
}

private struct SidebarDestinationRow: View {
    let destination: SidebarDestination
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: destination.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20, height: 20)
                Text(destination.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? DouMeowPalette.accent : DouMeowPalette.ink)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background(
                isSelected ? DouMeowPalette.sidebarSelection : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PageScaffold<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(DouMeowPalette.ink)

                content
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DouMeowPalette.page)
    }
}

private struct HealthCheckContent: View {
    @EnvironmentObject private var state: AppState
    @State private var refreshID = UUID()
    @State private var isRefreshing = false
    @State private var controllerCheck = ControllerHealthCheck.notChecked
    @State private var systemProxyCheck = SystemProxyHealthCheck.notChecked
    @State private var checkedAt: Date?
    @State private var isShowingNetworkDiagnostics = false

    private var helperManager: PrivilegedHelperManager {
        .shared
    }

    private var configURL: URL {
        state.currentProfile?.fileURL ?? state.core.configFile
    }

    private var configExists: Bool {
        FileManager.default.fileExists(atPath: configURL.path)
    }

    private var tunEnabled: Bool {
        state.displayedConfig?.tun?.enable == true
    }

    var body: some View {
        PageScaffold(title: "健康检查") {
            VStack(spacing: 0) {
                header

                Divider()

                HealthCheckRow(title: "芯片", subtitle: HealthDeviceInformation.chip)
                Divider()
                HealthCheckRow(title: "系统", subtitle: HealthDeviceInformation.system)
                Divider()
                helperRow
                Divider()
                coreRow
                Divider()
                controllerRow
                Divider()
                configurationRow
                Divider()
                tunRow
                Divider()
                systemProxyRow
                Divider()
                latencyRow(
                    title: "公网连接",
                    value: state.internetLatencySnapshot.internetMs,
                    unavailableState: .failed
                )
                Divider()
                latencyRow(
                    title: "默认网关",
                    value: state.internetLatencySnapshot.routerMs,
                    unavailableState: .warning
                )
                Divider()
                latencyRow(
                    title: "DNS 解析",
                    value: state.internetLatencySnapshot.dnsMs,
                    unavailableState: .failed
                )
                Divider()
                proxyChainRow
                Divider()

                Label(checkedAtText, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
            .surfaceCard(cornerRadius: 8)
        }
        .task(id: refreshID) {
            await refreshHealthStatus()
        }
        .sheet(isPresented: $isShowingNetworkDiagnostics) {
            NetworkDiagnosticsSheet()
                .environmentObject(state)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("健康检查")
                    .font(.headline)
                Text("检查 DouMeow、Mihomo 与当前网络的实际可用状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isShowingNetworkDiagnostics = true
                Task { await state.diagnoseInternetLatency() }
            } label: {
                Label("网络诊断", systemImage: "stethoscope")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            Divider()
                .frame(height: 16)

            Button {
                refreshID = UUID()
            } label: {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .frame(width: 24, height: 24)
            .disabled(isRefreshing)
            .help("刷新全部健康检查状态")
            .accessibilityLabel("刷新全部健康检查状态")
        }
        .padding(20)
    }

    private var helperRow: some View {
        let canInstall = helperManager.canInstallBundledHelper
        let isInstalled = helperManager.isInstalled
        let title = canInstall ? (isInstalled ? "已安装" : "未安装") : "开发环境"
        let healthState: HealthCheckState = canInstall ? (isInstalled ? .ready : .warning) : .inactive

        return HealthCheckRow(
            title: "管理员助手",
            subtitle: canInstall ? "用于安全地启动内核与调整系统网络设置。" : "当前进程不是应用程序包，不检查管理员助手。",
            statusTitle: title,
            state: healthState
        )
    }

    private var coreRow: some View {
        let subtitle: String
        let healthState: HealthCheckState

        switch state.core.status {
        case .running:
            subtitle = state.version?.version.map { "Mihomo \($0)" } ?? "Mihomo 进程正在运行。"
            healthState = .ready
        case .starting:
            subtitle = "正在启动 Mihomo 并等待 Controller。"
            healthState = .checking
        case .stopped:
            subtitle = "Mihomo 当前未运行。"
            healthState = .inactive
        case .missingBinary:
            subtitle = "未找到与当前芯片匹配的 Mihomo 可执行文件。"
            healthState = .failed
        case .failed(let message):
            subtitle = message
            healthState = .failed
        }

        return HealthCheckRow(
            title: "Mihomo",
            subtitle: subtitle,
            statusTitle: state.core.status.title,
            state: healthState
        )
    }

    private var controllerRow: some View {
        HealthCheckRow(
            title: "Controller",
            subtitle: controllerCheck.subtitle(port: state.controllerPort),
            statusTitle: controllerCheck.title,
            state: controllerCheck.healthState
        )
    }

    private var configurationRow: some View {
        let healthState: HealthCheckState
        let statusTitle: String

        if !configExists {
            healthState = .failed
            statusTitle = "文件缺失"
        } else if state.displayedConfig == nil {
            healthState = .warning
            statusTitle = "未解析"
        } else {
            healthState = .ready
            statusTitle = "可用"
        }

        return HealthCheckRow(
            title: "当前配置",
            subtitle: "\(state.currentProfileName) · \(configURL.path(percentEncoded: false))",
            statusTitle: statusTitle,
            state: healthState
        )
    }

    private var tunRow: some View {
        let statusTitle: String
        let healthState: HealthCheckState

        if tunEnabled, state.core.status.isHealthy {
            statusTitle = "已启用"
            healthState = .ready
        } else if tunEnabled {
            statusTitle = "等待内核"
            healthState = .warning
        } else {
            statusTitle = "未启用"
            healthState = .inactive
        }

        let subtitle = tunEnabled
            ? "通过 \(state.tunDevice) 接管不遵循系统代理的应用流量。"
            : "未接管不遵循系统代理的应用流量。"
        return HealthCheckRow(
            title: "增强模式",
            subtitle: subtitle,
            statusTitle: statusTitle,
            state: healthState
        )
    }

    private var systemProxyRow: some View {
        HealthCheckRow(
            title: "系统代理",
            subtitle: systemProxyCheck.subtitle,
            statusTitle: systemProxyCheck.title,
            state: systemProxyCheck.healthState
        )
    }

    private func latencyRow(
        title: String,
        value: Int?,
        unavailableState: HealthCheckState
    ) -> some View {
        let statusTitle: String
        let healthState: HealthCheckState

        if let value {
            statusTitle = "\(value) ms"
            healthState = .ready
        } else if isRefreshing || state.isDiagnosingInternetLatency {
            statusTitle = "检查中"
            healthState = .checking
        } else if state.internetLatencySnapshot.measuredAt == nil {
            statusTitle = "未检查"
            healthState = .inactive
        } else {
            statusTitle = "无响应"
            healthState = unavailableState
        }

        return HealthCheckRow(
            title: title,
            subtitle: latencyDetail(for: title),
            statusTitle: statusTitle,
            state: healthState
        )
    }

    private var proxyChainRow: some View {
        guard let entry = state.internetLatencySnapshot.entries.first(where: { $0.title == "测试代理链" }) else {
            return HealthCheckRow(
                title: "代理链",
                subtitle: state.core.status.isHealthy ? "等待测试当前选中节点。" : "Mihomo 未运行，跳过代理链测试。",
                statusTitle: isRefreshing ? "检查中" : "未检查",
                state: isRefreshing ? .checking : .inactive
            )
        }

        let healthState: HealthCheckState = switch entry.level {
        case .success: .ready
        case .warning: .warning
        case .info: .inactive
        }
        let statusTitle = switch entry.level {
        case .success: "可用"
        case .warning: "异常"
        case .info: "已跳过"
        }
        return HealthCheckRow(
            title: "代理链",
            subtitle: entry.message,
            statusTitle: statusTitle,
            state: healthState
        )
    }

    private var checkedAtText: String {
        guard let checkedAt else {
            return isRefreshing ? "正在检查" : "尚未检查"
        }
        return "检查时间：\(Self.timeFormatter.string(from: checkedAt))"
    }

    private func latencyDetail(for title: String) -> String {
        let entryTitle: String = switch title {
        case "默认网关": "路由器"
        case "DNS 解析": "测试 DNS"
        default: "测试直连策略"
        }
        return state.internetLatencySnapshot.entries.first(where: { $0.title == entryTitle })?.message
            ?? "等待网络诊断结果。"
    }

    @MainActor
    private func refreshHealthStatus() async {
        isRefreshing = true
        controllerCheck = state.core.status.isHealthy ? .checking : .coreStopped
        systemProxyCheck = .checking

        if DashboardDemoMode.isEnabled {
            controllerCheck = .available(version: state.version?.version)
            systemProxyCheck = state.systemProxyEnabled
                ? .enabled(service: "Wi-Fi", port: state.systemProxyPort)
                : .disabled(service: "Wi-Fi")
        }

        async let controllerRefresh: Void = refreshControllerIfNeeded()
        async let systemProxyRefresh: Void = refreshSystemProxyIfNeeded()
        await state.diagnoseInternetLatency()
        _ = await controllerRefresh
        _ = await systemProxyRefresh
        guard !Task.isCancelled else { return }

        checkedAt = Date()
        isRefreshing = false
    }

    @MainActor
    private func refreshControllerIfNeeded() async {
        guard !DashboardDemoMode.isEnabled, state.core.status.isHealthy else { return }

        do {
            let version = try await state.api.version()
            guard !Task.isCancelled else { return }
            controllerCheck = .available(version: version.version)
        } catch {
            guard !Task.isCancelled else { return }
            controllerCheck = .unavailable
        }
    }

    @MainActor
    private func refreshSystemProxyIfNeeded() async {
        guard !DashboardDemoMode.isEnabled else { return }

        let port = state.systemProxyPort
        let result = await Task.detached(priority: .utility) {
            let controller = SystemProxyController()
            do {
                let configuration = try controller.resolvedConfiguration(port: port)
                return switch try controller.health(configuration: configuration) {
                case .enabled:
                    SystemProxyHealthCheck.enabled(
                        service: configuration.networkService,
                        port: configuration.port
                    )
                case .disabled:
                    SystemProxyHealthCheck.disabled(service: configuration.networkService)
                case .mismatched:
                    SystemProxyHealthCheck.mismatched(
                        service: configuration.networkService,
                        expectedPort: configuration.port
                    )
                }
            } catch {
                return SystemProxyHealthCheck.unavailable
            }
        }.value

        guard !Task.isCancelled else { return }
        systemProxyCheck = result
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private enum HealthDeviceInformation {
    static let chip: String = {
        #if arch(arm64)
        "Apple Silicon"
        #elseif arch(x86_64)
        "Intel"
        #else
        "未知架构"
        #endif
    }()

    static let system = ProcessInfo.processInfo.operatingSystemVersionString
}

private enum HealthCheckState {
    case ready
    case checking
    case warning
    case failed
    case inactive

    var color: Color {
        switch self {
        case .ready: DouMeowPalette.accent
        case .checking, .warning: DouMeowPalette.orange
        case .failed: .red
        case .inactive: .secondary
        }
    }
}

private enum ControllerHealthCheck {
    case notChecked
    case checking
    case available(version: String?)
    case unavailable
    case coreStopped

    var title: String {
        switch self {
        case .notChecked: "未检查"
        case .checking: "检查中"
        case .available: "可用"
        case .unavailable: "不可用"
        case .coreStopped: "未启动"
        }
    }

    var healthState: HealthCheckState {
        switch self {
        case .notChecked, .coreStopped: .inactive
        case .checking: .checking
        case .available: .ready
        case .unavailable: .failed
        }
    }

    func subtitle(port: Int) -> String {
        switch self {
        case .notChecked:
            "尚未连接本地 Controller。"
        case .checking:
            "正在检查 127.0.0.1:\(port)。"
        case .available(let version):
            version.map { "127.0.0.1:\(port) · Mihomo \($0)" } ?? "127.0.0.1:\(port) 已响应。"
        case .unavailable:
            "127.0.0.1:\(port) 未响应，请检查内核日志。"
        case .coreStopped:
            "Mihomo 未运行，未检查本地 Controller。"
        }
    }
}

private enum SystemProxyHealthCheck: Sendable {
    case notChecked
    case checking
    case enabled(service: String, port: Int)
    case disabled(service: String)
    case mismatched(service: String, expectedPort: Int)
    case unavailable

    var title: String {
        switch self {
        case .notChecked: "未检查"
        case .checking: "检查中"
        case .enabled: "已启用"
        case .disabled: "未启用"
        case .mismatched: "配置不一致"
        case .unavailable: "无法读取"
        }
    }

    var healthState: HealthCheckState {
        switch self {
        case .notChecked, .disabled: .inactive
        case .checking: .checking
        case .enabled: .ready
        case .mismatched: .warning
        case .unavailable: .failed
        }
    }

    var subtitle: String {
        switch self {
        case .notChecked:
            "尚未读取当前主网络服务的代理设置。"
        case .checking:
            "正在读取 HTTP、HTTPS 与 SOCKS 代理设置。"
        case .enabled(let service, let port):
            "\(service) 的 HTTP、HTTPS 与 SOCKS 均指向 127.0.0.1:\(port)。"
        case .disabled(let service):
            "\(service) 未启用 HTTP、HTTPS 或 SOCKS 系统代理。"
        case .mismatched(let service, let expectedPort):
            "\(service) 的代理协议未全部指向 127.0.0.1:\(expectedPort)。"
        case .unavailable:
            "无法读取当前主网络服务的系统代理设置。"
        }
    }
}

private struct HealthCheckRow: View {
    let title: String
    let subtitle: String
    var statusTitle: String?
    var state: HealthCheckState = .inactive

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let statusTitle {
                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(state.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(state.color.opacity(0.10), in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

private struct AppToastView: View {
    let toast: AppToast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DouMeowPalette.accent)
            Text(toast.message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DouMeowPalette.ink)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(DouMeowPalette.card, in: Capsule())
        .overlay(
            Capsule()
                .stroke(DouMeowPalette.faintLine, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 8)
        .accessibilityLabel(toast.message)
    }
}

private struct ViewHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ProxiesContent: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedGroups = Set<String>()

    var body: some View {
        PageScaffold(title: "代理") {
            Group {
                if state.visibleProxyGroups.isEmpty {
                    ContentUnavailableView {
                        Label(state.effectiveForwardingMode == .direct ? "直连模式" : "暂无代理组", systemImage: "point.3.connected.trianglepath.dotted")
                    } description: {
                        Text(state.effectiveForwardingMode == .direct ? "当前模式不展示代理组。" : (state.core.status.isHealthy ? "当前配置没有可选择的代理组。" : "启动内核或导入包含代理组的配置。"))
                    } actions: {
                        if state.effectiveForwardingMode != .direct {
                            Button("刷新") {
                                Task { await state.refresh() }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVStack(spacing: 18) {
                        ForEach(state.visibleProxyGroups) { group in
                            ProxyGroupCard(
                                group: group,
                                isExpanded: isExpanded(group),
                                onToggle: { toggleExpansion(for: group) }
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .onAppear {
            expandInitialGroupsIfNeeded()
            Task {
                await state.refreshProxyGroupsFromControllerIfAvailable()
            }
        }
        .onChange(of: state.visibleProxyGroups.map(\.id)) {
            expandInitialGroupsIfNeeded()
        }
    }

    private func isExpanded(_ group: ProxyGroupItem) -> Bool {
        expandedGroups.contains(group.id)
    }

    private func toggleExpansion(for group: ProxyGroupItem) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            if expandedGroups.contains(group.id) {
                expandedGroups.remove(group.id)
            } else {
                expandedGroups.insert(group.id)
            }
        }
    }

    private func expandInitialGroupsIfNeeded() {
        if expandedGroups.isEmpty {
            expandedGroups = Set(state.visibleProxyGroups.prefix(3).map(\.id))
        }
    }
}

private struct ProxyGroupCard: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let group: ProxyGroupItem
    let isExpanded: Bool
    let onToggle: () -> Void

    private let nodeColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14, alignment: .top)
    ]

    private var nodes: [ProxyGroupNode] {
        if !group.nodes.isEmpty {
            return group.nodes
        }
        return (group.all.isEmpty ? [group.now] : group.all).map {
            ProxyGroupNode(name: $0, type: nil, delay: nil, alive: nil)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            groupHeader

            if isExpanded {
                LazyVGrid(columns: nodeColumns, alignment: .leading, spacing: 14) {
                    ForEach(nodes) { node in
                        ProxyCard(
                            group: group,
                            node: node,
                            isTestingDelay: state.isTestingDelay(groupID: group.id)
                        ) {
                            Task { await state.selectProxy(groupID: group.id, proxyName: node.name) }
                        }
                    }
                }
                .padding(.vertical, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contextMenu {
            Button("测速") {
                Task { await state.testDelay(for: group) }
            }
            .disabled(state.isTestingDelay)
        }
    }

    private var groupHeader: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(group.displayName)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(DouMeowPalette.ink)
                                .lineLimit(1)
                            Text("\(nodes.count)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DouMeowPalette.muted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: 0xF0F2F7), in: Capsule())
                        }
                        Text(group.displayNow)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DouMeowPalette.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DouMeowPalette.muted)
                        .frame(width: 24, height: 24)
                        .rotationEffect(.degrees(isExpanded ? -180 : 0))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.displayName)，当前 \(group.displayNow)")

            Button {
                Task { await state.testDelay(for: group) }
            } label: {
                if state.isTestingDelay(groupID: group.id) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "speedometer")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DouMeowPalette.muted)
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.plain)
            .disabled(state.isTestingDelay)
            .help("测试该代理组延迟")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }
}

private struct ProxyNodeSelectionDot: View {
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(isSelected ? DouMeowPalette.accent : DouMeowPalette.faintLine)
            .frame(width: 7, height: 7)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}

private struct ProxyCard: View {
    let group: ProxyGroupItem
    let node: ProxyGroupNode
    let isTestingDelay: Bool
    let action: () -> Void

    private var isSelected: Bool {
        node.name == group.now
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 9) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(node.displayName)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(DouMeowPalette.ink)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)

                    metadataRow
                }

                Spacer(minLength: 0)

                ProxyNodeSelectionDot(isSelected: isSelected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(
                isSelected ? DouMeowPalette.accent.opacity(0.10) : Color.white,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? DouMeowPalette.accent.opacity(0.18) : DouMeowPalette.faintLine.opacity(0.8),
                        lineWidth: 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(isSelected ? "当前代理" : "切换到 \(node.displayName)")
        .accessibilityLabel(node.displayName)
        .accessibilityValue(accessibilityValue)
    }

    private var proxyTypeText: String {
        node.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var delayDisplayText: String {
        if isTestingDelay {
            return "--"
        }
        if node.alive == false {
            return "超时"
        }
        guard let delay = node.delay else {
            return "--"
        }
        if delay <= 0 {
            return "超时"
        }
        return "\(delay) ms"
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 8) {
            if !proxyTypeText.isEmpty {
                Text(proxyTypeText)
                    .foregroundStyle(DouMeowPalette.muted)
            }
            if isTestingDelay {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Text(delayDisplayText)
                    .foregroundStyle(delayColor)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
    }

    private var accessibilityValue: String {
        var values: [String] = []
        if isSelected { values.append("已选中") }
        if !proxyTypeText.isEmpty { values.append(proxyTypeText) }
        values.append(isTestingDelay ? "测速中" : delayDisplayText)
        return values.joined(separator: ", ")
    }

    private var delayColor: Color {
        if node.alive == false {
            return DouMeowPalette.orange
        }
        guard let delay = node.delay else {
            return DouMeowPalette.muted.opacity(0.8)
        }
        if delay <= 0 {
            return DouMeowPalette.orange
        }
        if delay < 300 {
            return Color(red: 0.18, green: 0.72, blue: 0.38)
        }
        return DouMeowPalette.orange
    }
}

private struct ConnectionsContent: View {
    @EnvironmentObject private var state: AppState
    @State private var searchText = ""
    @State private var isConfirmingCloseAll = false

    private var filteredConnections: [MihomoConnection] {
        guard !searchText.isEmpty else { return state.connections.connections }
        return state.connections.connections.filter { connection in
            connection.displayHost.localizedCaseInsensitiveContains(searchText)
                || (connection.rule?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (connection.chains?.joined(separator: " ").localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        PageScaffold(title: "连接") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("搜索连接", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await state.refresh() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        isConfirmingCloseAll = true
                    } label: {
                        Label("关闭全部", systemImage: "xmark.circle")
                    }
                    .disabled(filteredConnections.isEmpty || !state.core.status.isHealthy)
                }

                if filteredConnections.isEmpty {
                    ContentUnavailableView {
                        Label(state.core.status.isHealthy ? "暂无连接" : "内核未运行", systemImage: "network")
                    } description: {
                        Text(state.core.status.isHealthy ? "活跃连接会显示在这里。" : "启动内核后可检查 TCP/UDP 会话。")
                    } actions: {
                        Button("刷新") {
                            Task { await state.refresh() }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredConnections) { connection in
                            ConnectionRow(connection: connection)
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "关闭全部 \(state.connections.connections.count) 个连接？",
            isPresented: $isConfirmingCloseAll,
            titleVisibility: .visible
        ) {
            Button("关闭全部", role: .destructive) {
                Task { await state.closeAllConnections() }
            }
            Button("取消", role: .cancel) {}
        }
    }
}

private struct ConnectionRow: View {
    @EnvironmentObject private var state: AppState
    let connection: MihomoConnection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: connection.metadata?.network == "udp" ? "antenna.radiowaves.left.and.right" : "network")
                .foregroundStyle(DouMeowPalette.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(connection.displayHost)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DouMeowPalette.ink)
                    .lineLimit(1)
                Text([connection.rule, connection.rulePayload, connection.chains?.joined(separator: " / ")].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DouMeowPalette.muted)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("↑ \(formatByteCount(connection.upload ?? 0))")
                Text("↓ \(formatByteCount(connection.download ?? 0))")
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(DouMeowPalette.muted)

            Button(role: .destructive) {
                Task { await state.closeConnection(connection) }
            } label: {
                Image(systemName: "xmark.circle")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DouMeowPalette.orange)
            .disabled(!state.core.status.isHealthy)
            .help("关闭连接")
        }
        .padding(14)
        .surfaceCard()
        .contextMenu {
            Button("复制 Host") {
                writeToPasteboard(connection.displayHost)
            }
            Button("复制规则") {
                writeToPasteboard(connection.rule ?? "-")
            }
            Divider()
            Button("关闭连接", role: .destructive) {
                Task { await state.closeConnection(connection) }
            }
            .disabled(!state.core.status.isHealthy)
        }
    }

    private func writeToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

private struct LogsContent: View {
    @EnvironmentObject private var state: AppState
    @State private var searchText = ""
    @State private var level: LogLevelFilter = .all
    @State private var source: LogSourceFilter = .all
    @State private var isPaused = false

    private let sourceFilters: [LogSourceFilter] = [.all, .app, .core]

    private var groupedLogs: [LogGroup] {
        let orderedLogs = state.logs.enumerated()
            .map { LogDisplayEntry(log: $0.element, order: $0.offset) }
            .sorted { left, right in
                switch (left.log.sortTime, right.log.sortTime) {
                case let (leftTime?, rightTime?) where leftTime != rightTime:
                    return leftTime > rightTime
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return left.order > right.order
                }
            }

        var groups = orderedLogs.reduce(into: [LogGroup]()) { groups, entry in
            if let lastIndex = groups.indices.last, groups[lastIndex].canAppend(entry) {
                groups[lastIndex].append(entry)
            } else {
                groups.append(LogGroup(entry: entry))
            }
        }
        var occurrenceByKey = [LogGroupKey: Int]()
        for index in groups.indices.reversed() {
            let key = groups[index].key
            let occurrence = occurrenceByKey[key, default: 0]
            groups[index].setOccurrence(occurrence)
            occurrenceByKey[key] = occurrence + 1
        }
        return groups
    }

    private var filteredGroups: [LogGroup] {
        groupedLogs.filter { group in
            let log = group.representative.log
            let matchesLevel = level == .all || log.normalizedLevel == level.rawValue
            let matchesSource = source == .all || log.source == source
            let matchesSearch = searchText.isEmpty
                || log.message.localizedCaseInsensitiveContains(searchText)
                || log.level.localizedCaseInsensitiveContains(searchText)
                || log.source.title.localizedCaseInsensitiveContains(searchText)
            return matchesLevel && matchesSource && matchesSearch
        }
    }

    var body: some View {
        let visibleGroups = filteredGroups

        PageScaffold(title: "日志") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("搜索日志", text: $searchText)
                        .textFieldStyle(.douMeowRounded)

                    LogIconButton(
                        title: isPaused ? "开始" : "暂停",
                        systemImage: isPaused ? "play.fill" : "pause.fill"
                    ) {
                        isPaused.toggle()
                    }

                    LogIconButton(title: "刷新", systemImage: "arrow.clockwise") {
                        state.loadLogs(source: .all)
                    }

                    LogActionButton(title: "复制可见日志") {
                        let rawText = visibleGroups
                            .flatMap(\.entries)
                            .map(\.log.rawText)
                            .joined(separator: "\n")
                        writeToPasteboard(rawText)
                    }
                    .disabled(visibleGroups.isEmpty)
                }

                RuleOptionRow {
                    ForEach(sourceFilters) { item in
                        RuleOptionButton(
                            title: item.title,
                            isSelected: source == item,
                            color: DouMeowPalette.accent
                        ) {
                            source = item
                        }
                    }
                }

                RuleOptionRow {
                    ForEach(LogLevelFilter.allCases) { item in
                        RuleOptionButton(
                            title: item.title,
                            isSelected: level == item,
                            color: DouMeowPalette.accent
                        ) {
                            level = item
                        }
                    }
                }

                if visibleGroups.isEmpty {
                    VStack(spacing: 8) {
                        Label(
                            searchText.isEmpty ? "暂无日志" : "无匹配结果",
                            systemImage: "doc.text.magnifyingglass"
                        )
                        .font(.headline)
                        Text(searchText.isEmpty ? emptyMessage : "试试其他搜索词。")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(visibleGroups) { group in
                            CoreLogRow(group: group)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .frame(minHeight: 160)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: coreLogStreamingTaskID) {
            guard shouldFollowCoreLogs else {
                state.stopLogStream()
                return
            }
            state.loadLogs(source: .all)
            if state.core.status.isHealthy {
                state.startLogStream(level: .all)
            } else {
                state.stopLogStream()
            }
        }
        .onDisappear {
            state.stopLogStream()
        }
    }

    private var shouldFollowCoreLogs: Bool {
        !isPaused && source != .app
    }

    private var coreLogStreamingTaskID: String {
        shouldFollowCoreLogs ? (state.core.status.isHealthy ? "running" : "stopped") : "paused"
    }

    private var emptyMessage: String {
        switch source {
        case .all:
            return "应用和内核运行事件会显示在这里。"
        case .app:
            return "应用操作、连接状态和诊断事件会显示在这里。"
        case .core:
            return "启动 Mihomo 后可查看内核日志。"
        }
    }

    private func writeToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

private struct LogDisplayEntry: Identifiable {
    let log: CoreLogEntry
    let order: Int

    var id: String { log.id }
}

private struct LogGroupKey: Hashable {
    let source: LogSourceFilter
    let level: String
    let message: String
}

private struct LogGroupID: Hashable {
    let key: LogGroupKey
    let occurrence: Int
}

private struct LogGroup: Identifiable {
    private(set) var entries: [LogDisplayEntry]
    private var occurrence = 0

    init(entry: LogDisplayEntry) {
        entries = [entry]
    }

    var id: LogGroupID {
        LogGroupID(key: key, occurrence: occurrence)
    }

    var representative: LogDisplayEntry {
        entries[0]
    }

    var repeatDescription: String? {
        guard entries.count > 1 else { return nil }
        let newestTime = LogTimeSupport.clockString(from: entries.first?.log.time) ?? "-"
        let oldestTime = LogTimeSupport.clockString(from: entries.last?.log.time) ?? "-"
        return "重复 \(entries.count) 次 · \(oldestTime)–\(newestTime)"
    }

    var rawText: String {
        entries.map(\.log.rawText).joined(separator: "\n")
    }

    var key: LogGroupKey {
        let log = representative.log
        return LogGroupKey(source: log.source, level: log.normalizedLevel, message: log.message)
    }

    func canAppend(_ entry: LogDisplayEntry) -> Bool {
        let log = entry.log
        return key == LogGroupKey(source: log.source, level: log.normalizedLevel, message: log.message)
    }

    mutating func append(_ entry: LogDisplayEntry) {
        entries.append(entry)
    }

    mutating func setOccurrence(_ occurrence: Int) {
        self.occurrence = occurrence
    }
}

private extension LogLevelFilter {
    var tintColor: Color {
        switch self {
        case .all: return DouMeowPalette.muted
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .debug: return DouMeowPalette.muted
        }
    }

    var messageColor: Color {
        switch self {
        case .error, .warning:
            return tintColor
        case .all, .info:
            return DouMeowPalette.ink
        case .debug:
            return DouMeowPalette.muted
        }
    }
}

private extension LogSourceFilter {
    var tintColor: Color {
        switch self {
        case .all: return DouMeowPalette.muted
        case .app: return DouMeowPalette.accent
        case .core: return .indigo
        }
    }
}

private struct DouMeowRoundedTextFieldStyle: TextFieldStyle {
    @Environment(\.isFocused) private var isFocused

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .tint(DouMeowPalette.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(DouMeowPalette.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isFocused ? DouMeowPalette.accent.opacity(0.72) : DouMeowPalette.faintLine,
                        lineWidth: 1
                    )
            }
    }
}

private extension TextFieldStyle where Self == DouMeowRoundedTextFieldStyle {
    static var douMeowRounded: DouMeowRoundedTextFieldStyle {
        DouMeowRoundedTextFieldStyle()
    }
}

private struct LogActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DouMeowPalette.ink.opacity(0.76))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Color(hex: 0xE7ECF3), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct LogIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DouMeowPalette.ink.opacity(0.76))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct CoreLogRow: View {
    let group: LogGroup

    private var log: CoreLogEntry {
        group.representative.log
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Capsule()
                .fill(level.tintColor)
                .frame(width: 3, height: 34)

            LogLevelChip(level: level)

            Text(LogTimeSupport.clockString(from: log.time) ?? "-")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DouMeowPalette.muted)
                .frame(width: 66, alignment: .leading)
                .lineLimit(1)

            LogSourceChip(source: log.source)

            VStack(alignment: .leading, spacing: 4) {
                Text(log.message)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(level.messageColor)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let repeatDescription = group.repeatDescription {
                    Text(repeatDescription)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(DouMeowPalette.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .surfaceCard(cornerRadius: 8)
        .contextMenu {
            Button("复制消息") {
                writeToPasteboard(log.message)
            }
            Button("复制原始日志") {
                writeToPasteboard(group.rawText)
            }
        }
    }

    private var level: LogLevelFilter {
        LogLevelFilter(rawValue: log.normalizedLevel) ?? .info
    }

    private func writeToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

private struct LogLevelChip: View {
    let level: LogLevelFilter

    var body: some View {
        Text(level.title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(level.tintColor)
            .lineLimit(1)
            .frame(width: 42, height: 22)
            .background(level.tintColor.opacity(0.1), in: Capsule())
            .overlay {
                Capsule().stroke(level.tintColor.opacity(0.2), lineWidth: 1)
            }
    }
}

private struct LogSourceChip: View {
    let source: LogSourceFilter

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(source.tintColor)
                .frame(width: 5, height: 5)
            Text(source.title)
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(source.tintColor)
        .lineLimit(1)
        .frame(width: 48, height: 22)
        .background(source.tintColor.opacity(0.08), in: Capsule())
    }
}

private struct LogLineCard: View {
    let source: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProfileChip(text: source)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DouMeowPalette.ink)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DouMeowPalette.muted)
                    .lineLimit(3)
            }
            Spacer()
        }
        .padding(14)
        .surfaceCard()
    }
}

private struct RulesContent: View {
    @EnvironmentObject private var state: AppState
    @State private var searchText = ""
    @State private var isAddingRuleOverride = false
    @State private var editingRule: RuleItem?

    private var filteredRules: [RuleItem] {
        state.rules.filter { rule in
            searchText.isEmpty
                || rule.type.localizedCaseInsensitiveContains(searchText)
                || rule.payload.localizedCaseInsensitiveContains(searchText)
                || rule.proxy.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        PageScaffold(title: "规则") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("搜索规则", text: $searchText)
                        .textFieldStyle(RuleTextFieldStyle())

                    Button {
                        Task { await state.refreshRules() }
                    } label: {
                        if state.isRefreshingRules {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .disabled(state.isRefreshingRules)
                    .help("刷新规则")
                    .accessibilityLabel("刷新规则")

                    Button {
                        isAddingRuleOverride = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .help("添加规则")
                    .accessibilityLabel("添加规则")
                }

                if filteredRules.isEmpty {
                    RuleEmptyView(
                        title: searchText.isEmpty ? "暂无规则" : "没有匹配规则",
                        message: searchText.isEmpty ? (state.core.status.isHealthy ? "controller 暂未返回规则。" : "启动内核后可读取运行时规则。") : "清除搜索或换一个关键词。",
                        buttonTitle: searchText.isEmpty ? "刷新" : "清除搜索",
                        systemImage: "list.bullet.rectangle"
                    ) {
                        if searchText.isEmpty {
                            Task { await state.refreshRules() }
                        } else {
                            searchText = ""
                        }
                    }
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredRules) { rule in
                            RuleRow(
                                rule: rule,
                                isControllerReady: state.core.status.isHealthy,
                                edit: { editingRule = rule },
                                setEnabled: { isEnabled in
                                    Task { await state.setRule(rule, isEnabled: isEnabled) }
                                }
                            )
                        }
                    }
                }
            }
        }
        .task {
            await state.refreshRules()
        }
        .sheet(isPresented: $isAddingRuleOverride) {
            RuleEditorView()
                .environmentObject(state)
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorView(initialRule: rule)
                .environmentObject(state)
        }
    }

}

private struct RuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    let initialRule: RuleItem?

    @State private var typeText: String
    @State private var payload: String
    @State private var proxy: String
    @State private var useRawInput = false
    @State private var rawRule: String

    init(initialRule: RuleItem? = nil) {
        self.initialRule = initialRule
        _typeText = State(initialValue: initialRule?.type ?? "DOMAIN-SUFFIX")
        _payload = State(initialValue: initialRule?.payload ?? "")
        _proxy = State(initialValue: initialRule?.proxy ?? "DIRECT")
        _rawRule = State(initialValue: initialRule?.overrideRuleText ?? "")
    }

    private var proxyOptions: [String] {
        let builtin = ["DIRECT", "REJECT"]
        let existing = state.rules.map(\.proxy).filter { !$0.isEmpty && $0 != "-" }
        let groups = state.activeProfileProxyGroups.map(\.name)
        let nodes = state.activeProfileNodes.map(\.name)
        return Array(Set(builtin + existing + groups + nodes)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var trimmedType: String {
        typeText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPayload: String {
        payload.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedProxy: String {
        proxy.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRawRule: String {
        rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var ruleText: String {
        if useRawInput {
            return trimmedRawRule
        }
        if trimmedType.uppercased() == "MATCH" {
            return "MATCH,\(trimmedProxy)"
        }
        return "\(trimmedType),\(trimmedPayload),\(trimmedProxy)"
    }

    private var canSubmit: Bool {
        RuleOverrideSet.isValidRuleText(ruleText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(initialRule == nil ? "添加规则" : "修改规则")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(DouMeowPalette.ink)
                Spacer()
                Button("取消") {
                    dismiss()
                }
            }

            Toggle("直接输入规则", isOn: $useRawInput)
                .toggleStyle(.switch)
                .tint(DouMeowPalette.accent)

            if useRawInput {
                TextField("DOMAIN-SUFFIX,example.com,DIRECT", text: $rawRule)
                    .textFieldStyle(RuleTextFieldStyle())
                    .onSubmit { submit() }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("类型")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DouMeowPalette.muted)
                    TextField("DOMAIN-SUFFIX", text: $typeText)
                        .textFieldStyle(RuleTextFieldStyle())
                    WrappingRuleOptionRow {
                        ForEach(RuleOverrideDraft.commonTypes, id: \.self) { type in
                            RuleOptionButton(
                                title: type,
                                isSelected: trimmedType == type,
                                color: DouMeowPalette.accent
                            ) {
                                typeText = type
                            }
                        }
                    }

                    if trimmedType.uppercased() != "MATCH" {
                        Text("匹配内容")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(DouMeowPalette.muted)
                        TextField(payloadPlaceholder, text: $payload)
                            .textFieldStyle(RuleTextFieldStyle())
                    }

                    Text("策略")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DouMeowPalette.muted)
                    TextField("出站策略", text: $proxy)
                        .textFieldStyle(RuleTextFieldStyle())
                        .onSubmit { submit() }

                    if !proxyOptions.isEmpty {
                        WrappingRuleOptionRow {
                            ForEach(proxyOptions, id: \.self) { option in
                                RuleOptionButton(
                                    title: option,
                                    isSelected: proxy == option,
                                    color: DouMeowPalette.accent
                                ) {
                                    proxy = option
                                }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("预览")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DouMeowPalette.muted)
                Text(ruleText.isEmpty ? "-" : ruleText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DouMeowPalette.ink)
                    .lineLimit(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xF0F2F7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack {
                Spacer()
                Button(initialRule == nil ? "添加" : "保存") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .tint(DouMeowPalette.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func submit() {
        guard canSubmit else { return }
        let submittedRule = ruleText
        let ruleToEdit = initialRule
        Task {
            if let ruleToEdit {
                await state.updateRule(ruleToEdit, with: submittedRule)
            } else {
                await state.addRuleOverride(submittedRule, placement: .prepend)
            }
            dismiss()
        }
    }

    private var payloadPlaceholder: String {
        switch trimmedType.uppercased() {
        case "DOMAIN-SUFFIX": "example.com"
        case "DOMAIN": "api.example.com"
        case "DOMAIN-KEYWORD": "example"
        case "IP-CIDR", "IP-CIDR6", "SRC-IP-CIDR": "8.8.8.0/24"
        case "GEOIP": "CN"
        default: "匹配内容"
        }
    }
}

private struct RuleTextFieldStyle: TextFieldStyle {
    @Environment(\.isFocused) private var isFocused

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .tint(DouMeowPalette.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(DouMeowPalette.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isFocused ? DouMeowPalette.accent.opacity(0.72) : DouMeowPalette.faintLine,
                        lineWidth: 1
                    )
            }
    }
}

private struct RuleOptionRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content
            }
        }
    }
}

private struct WrappingRuleOptionRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        WrappingLayout(spacing: 8, rowSpacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WrappingLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let rows = rows(in: proposal.width ?? .infinity, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.reduce(CGFloat.zero) { result, row in
            result + row.height
        } + CGFloat(max(rows.count - 1, 0)) * rowSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = rows(in: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(in maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        let availableWidth = maxWidth.isFinite ? maxWidth : CGFloat.greatestFiniteMagnitude

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty, nextWidth > availableWidth {
                rows.append(current)
                current = Row()
            }
            current.append(index: index, size: size, spacing: spacing)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(index: Int, size: CGSize, spacing: CGFloat) {
            if !items.isEmpty {
                width += spacing
            }
            items.append(Item(index: index, size: size))
            width += size.width
            height = max(height, size.height)
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }
}

private struct RuleOptionButton: View {
    let title: String
    let isSelected: Bool
    let color: Color
    var height: CGFloat = 32
    var fontSize: CGFloat = 12
    var width: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(isSelected ? color : DouMeowPalette.muted)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(width: width, height: height)
                .background(
                    (isSelected ? color : DouMeowPalette.muted).opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct RuleChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(DouMeowPalette.muted)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color(hex: 0xF0F2F7), in: Capsule())
    }
}

private struct RuleRow: View {
    let rule: RuleItem
    let isControllerReady: Bool
    let edit: () -> Void
    let setEnabled: (Bool) -> Void

    private var hitRateText: String {
        guard let rate = rule.hitRate else { return "-" }
        return "\(Int((rate * 100).rounded()))%"
    }

    private var lastActivityText: String {
        if let lastHit = rule.lastHit, !lastHit.isEmpty {
            return "最近命中 \(lastHit)"
        }
        if let lastMiss = rule.lastMiss, !lastMiss.isEmpty {
            return "最近未命中 \(lastMiss)"
        }
        return "尚无命中记录"
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding {
                rule.isEnabled
            } set: { isEnabled in
                setEnabled(isEnabled)
            })
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(DouMeowPalette.accent)
            .controlSize(.mini)
            .disabled(!isControllerReady)

            Text(rule.type)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DouMeowPalette.ink)
                .frame(width: 96, alignment: .leading)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.displayPayload)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DouMeowPalette.ink)
                    .lineLimit(1)
                Text("命中 \(rule.hitCount) · 未命中 \(rule.missCount) · size \(rule.size) · \(lastActivityText)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DouMeowPalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            RuleChip(text: hitRateText)
            Text(rule.proxy)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DouMeowPalette.muted)
                .frame(width: 110, alignment: .trailing)
                .lineLimit(1)

            Button(action: edit) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DouMeowPalette.accent)
            .help("修改规则")
        }
        .padding(12)
        .surfaceCard()
        .opacity(rule.isEnabled ? 1 : 0.58)
        .contextMenu {
            Button("复制规则") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(rule.overrideRuleText, forType: .string)
            }
            Button("修改规则", action: edit)
        }
    }
}

private struct RuleEmptyView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DouMeowPalette.ink)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DouMeowPalette.muted)
            Button(buttonTitle, action: action)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .surfaceCard()
    }
}

private struct SystemProxyContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        PageScaffold(title: "系统代理") {
            HStack(spacing: 16) {
                if let proxyToggle = state.toggles.first(where: { $0.id == "proxy" }) {
                    FeatureCard(
                        title: proxyToggle.title,
                        subtitle: proxyToggle.subtitle,
                        stateText: proxyToggle.isOn ? "已开启" : "已关闭",
                        stateColor: proxyToggle.isOn ? DouMeowPalette.accent : DouMeowPalette.orange,
                        isOn: proxyToggle.isOn,
                        actionImage: nil
                    ) { state.setToggle(proxyToggle, isOn: $0) }
                }
                SettingFactCard(
                    title: "本机端口",
                    value: "127.0.0.1:\(state.systemProxyPort)",
                    image: "network"
                )
                if let allowLanToggle = state.toggles.first(where: { $0.id == "allowLan" }) {
                    FeatureCard(
                        title: allowLanToggle.title,
                        subtitle: allowLanToggle.subtitle,
                        stateText: state.allowLan ? "已开启" : "已关闭",
                        stateColor: state.allowLan ? DouMeowPalette.accent : DouMeowPalette.orange,
                        isOn: state.allowLan,
                        actionImage: nil
                    ) { state.setToggle(allowLanToggle, isOn: $0) }
                }
            }
        }
    }
}

private struct DNSContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        PageScaffold(title: "DNS") {
            VStack(alignment: .leading, spacing: 12) {
                SettingFactCard(title: "IPv6", value: state.displayedConfig?.ipv6 == true ? "开启" : "关闭", image: "network")
                SettingFactCard(title: "日志级别", value: state.logLevelText, image: "doc.text")
                SettingFactCard(title: "配置文件", value: state.currentProfileName, image: "doc.plaintext")
            }
        }
    }
}

private struct TUNContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        PageScaffold(title: "TUN") {
            HStack(spacing: 16) {
                if let tunToggle = state.toggles.first(where: { $0.id == "tun" }) {
                    FeatureCard(
                        title: tunToggle.title,
                        subtitle: tunToggle.subtitle,
                        stateText: state.isApplyingTunUpdate ? "应用中" : (state.isTunEnabled ? "已开启" : "已关闭"),
                        stateColor: state.isTunEnabled ? DouMeowPalette.accent : DouMeowPalette.orange,
                        isOn: state.isTunEnabled,
                        actionImage: nil,
                        isDisabled: state.isApplyingTunUpdate
                    ) { state.setToggle(tunToggle, isOn: $0) }
                }
                SettingFactCard(title: "设备", value: state.tunDevice, image: "lock.shield")
            }
        }
    }
}

private struct SettingFactCard: View {
    let title: String
    let value: String
    let image: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: image)
                .foregroundStyle(DouMeowPalette.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DouMeowPalette.ink)
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DouMeowPalette.muted)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(16)
        .surfaceCard()
    }
}

private struct DashboardContent: View {
    @EnvironmentObject private var state: AppState
    let openProfiles: () -> Void
    let openProxies: () -> Void

    var body: some View {
        PageScaffold(title: "概览") {
            VStack(alignment: .leading, spacing: 20) {
                NetworkManageCard(openProfiles: openProfiles)

                HStack(spacing: 24) {
                    RouteModeCard()
                    ProxyNodeCard(openProxies: openProxies)
                }

                HStack(spacing: 18) {
                    let proxyToggle = state.toggles.first(where: { $0.id == "proxy" })
                    let tunToggle = state.toggles.first(where: { $0.id == "tun" })
                    FeatureCard(
                        title: "系统代理",
                        subtitle: "大多数应用的流量可以通过系统代理设置接管，兼容性和性能更稳定。",
                        stateText: state.systemProxyEnabled ? "已设置" : "未设置",
                        stateColor: state.systemProxyEnabled ? DouMeowPalette.accent : DouMeowPalette.orange,
                        isOn: proxyToggle?.isOn == true,
                        actionImage: nil,
                        onToggle: { isOn in
                            if let proxyToggle {
                                state.setToggle(proxyToggle, isOn: isOn)
                            }
                        }
                    )

                    FeatureCard(
                        title: "增强模式",
                        subtitle: "未遵循系统代理的应用可经由 TUN 或规则引擎接管，保持所有流量由 \(AppInfo.displayName) 路由。",
                        stateText: state.isApplyingTunUpdate ? "应用中" : (state.isTunEnabled ? "已启用" : "已禁用"),
                        stateColor: state.isTunEnabled ? DouMeowPalette.accent : DouMeowPalette.orange,
                        isOn: state.isTunEnabled,
                        actionImage: nil,
                        isDisabled: state.isApplyingTunUpdate,
                        onToggle: { isOn in
                            if let tunToggle {
                                state.setToggle(tunToggle, isOn: isOn)
                            }
                        }
                    )
                }

                ActivityGrid()
            }
        }
    }
}

private struct ProfilesContent: View {
    @EnvironmentObject private var state: AppState
    @State private var remoteURL = ""
    @State private var usesProxyForImport = false
    @State private var isImportingFile = false
    @State private var isDropTargeted = false
    @State private var profileDisplayOrder: [String] = []
    @FocusState private var urlFieldFocused: Bool

    var body: some View {
        PageScaffold(title: "配置") {
            VStack(alignment: .leading, spacing: 14) {
                importControls

                if state.profiles.isEmpty {
                    ContentUnavailableView {
                        Label("暂无配置", systemImage: "rectangle.stack.badge.plus")
                    } description: {
                        Text("可添加远程配置 URL 或本地 YAML。")
                    } actions: {
                        Button("Import File…") {
                            isImportingFile = true
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(displayedProfiles) { profile in
                            ProfilesListRow(
                                profile: profile,
                                summary: YAMLProfileSummary(
                                    url: profile.fileURL,
                                    config: profile.isCurrent ? state.displayedConfig : nil,
                                    proxyGroupCount: profile.isCurrent ? state.visibleProxyGroups.count : 0
                                ),
                                isBusy: state.isImportingProfile || !state.refreshingProfileIDs.isEmpty,
                                isRefreshing: state.refreshingProfileIDs.contains(profile.id),
                                use: {
                                    Task { await state.selectProfile(profile) }
                                },
                                refresh: {
                                    Task { await state.refreshProfile(profile) }
                                },
                                delete: {
                                    Task { await state.deleteProfile(profile) }
                                }
                            )
                        }
                    }
                }
            }
        }
        .background(DouMeowPalette.page)
        .overlay {
            if isDropTargeted {
                ProfileDropOverlay()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleProfileDrop(providers: providers)
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.yaml, .data, .plainText],
            allowsMultipleSelection: false
        ) { result in
            importLocalProfile(result)
        }
        .onAppear {
            state.refreshProfiles()
            profileDisplayOrder = profilesWithCurrentFirst(state.profiles).map(\.id)
            urlFieldFocused = true
        }
    }

    private var displayedProfiles: [DouMeowProfileSummary] {
        let profileByID = Dictionary(uniqueKeysWithValues: state.profiles.map { ($0.id, $0) })
        var usedIDs = Set<String>()
        var profiles = profileDisplayOrder.compactMap { id -> DouMeowProfileSummary? in
            guard let profile = profileByID[id] else { return nil }
            usedIDs.insert(id)
            return profile
        }
        profiles.append(contentsOf: profilesWithCurrentFirst(state.profiles).filter { !usedIDs.contains($0.id) })
        return profiles
    }

    private func profilesWithCurrentFirst(_ profiles: [DouMeowProfileSummary]) -> [DouMeowProfileSummary] {
        profiles.sorted { left, right in
            if left.isCurrent != right.isCurrent { return left.isCurrent }
            if left.id == "default" { return true }
            if right.id == "default" { return false }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    private var importControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                subscriptionURLField
                proxyImportToggle
                importActionGroup
            }

            VStack(alignment: .leading, spacing: 8) {
                subscriptionURLField
                HStack(spacing: 8) {
                    proxyImportToggle
                    Spacer()
                    importActionGroup
                }
            }
        }
    }

    private var subscriptionURLField: some View {
        HStack(spacing: 4) {
            TextField("Subscription URL", text: $remoteURL)
                .textFieldStyle(.plain)
                .focused($urlFieldFocused)
                .onSubmit { importRemoteProfile() }

            PasteButton(payloadType: String.self) { values in
                if let value = values.first {
                    remoteURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("粘贴远程配置 URL")
            .accessibilityLabel("粘贴远程配置 URL")
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .frame(height: 28)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(urlFieldFocused ? DouMeowPalette.accent : DouMeowPalette.faintLine, lineWidth: urlFieldFocused ? 2 : 1)
        }
    }

    private var proxyImportToggle: some View {
        Toggle("代理", isOn: $usesProxyForImport)
            .toggleStyle(.checkbox)
            .fixedSize()
    }

    private var importActionGroup: some View {
        HStack(spacing: 8) {
            Button("导入") {
                importRemoteProfile()
            }
            .disabled(remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isImportingProfile)

            Menu {
                Button("新建") {
                    Task { await state.createBlankLocalProfile() }
                }

                Button("打开") {
                    isImportingFile = true
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("新建或打开 YAML")
            .accessibilityLabel("新建或打开 YAML")
            .disabled(state.isImportingProfile)
        }
    }

    private func importRemoteProfile() {
        let value = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if await state.importRemoteProfile(urlString: value, useProxy: usesProxyForImport) {
                remoteURL = ""
            }
        }
    }

    private func importLocalProfile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            state.presentToast("未选择配置文件")
            return
        }

        importLocalProfile(from: url)
    }

    private func handleProfileDrop(providers: [NSItemProvider]) -> Bool {
        guard !state.isImportingProfile,
              let provider = providers.first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
              }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            let url: URL?
            if let itemURL = item as? URL {
                url = itemURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }

            Task { @MainActor in
                guard error == nil, let url else {
                    state.presentToast("无法读取拖入的文件")
                    return
                }
                guard ["yaml", "yml"].contains(url.pathExtension.lowercased()) else {
                    state.presentToast("仅支持 YAML 配置文件")
                    return
                }
                importLocalProfile(from: url)
            }
        }
        return true
    }

    private func importLocalProfile(from url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        Task {
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            await state.importLocalProfile(from: url)
        }
    }
}

private struct ProfileDropOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DouMeowPalette.accent.opacity(0.08))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    DouMeowPalette.accent,
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28, weight: .semibold))
                Text("拖入 YAML 以导入配置")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(DouMeowPalette.accent)
        }
        .padding(12)
    }
}

private struct YAMLProfileSummary: Identifiable {
    let id: String
    let name: String
    let path: String
    let fileSizeText: String
    let lineCount: Int
    let modifiedAt: Date?
    let modeText: String
    let mixedPortText: String
    let allowLanText: String
    let tunText: String
    let proxyGroupCount: Int

    init?(url: URL, config: MihomoConfig?, proxyGroupCount: Int) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes?[.size] as? NSNumber
        let modifiedAt = attributes?[.modificationDate] as? Date
        let yaml = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let lines = yaml.split(whereSeparator: \.isNewline)
        let fileConfig = MihomoConfig.parsed(from: yaml)

        self.id = url.path
        self.name = url.lastPathComponent
        self.path = url.path
        self.fileSizeText = formatByteCount(fileSize?.intValue ?? 0)
        self.lineCount = lines.count
        self.modifiedAt = modifiedAt
        self.modeText = MihomoMode(configValue: fileConfig.mode ?? config?.mode).displayValue
        self.mixedPortText = "\(fileConfig.mixedPort ?? config?.mixedPort ?? 7890)"
        let allowLan = fileConfig.allowLan ?? config?.allowLan
        let tunEnabled = fileConfig.tun?.enable ?? config?.tun?.enable
        self.allowLanText = allowLan == true ? "局域网已开启" : "局域网已关闭"
        self.tunText = tunEnabled == true ? "TUN 已开启" : "TUN 已关闭"
        self.proxyGroupCount = proxyGroupCount
    }

    var detailText: String {
        "\(fileSizeText) · \(lineCount) 行 · 本机端口 \(mixedPortText)"
    }
}

private struct ProfilesListRow: View {
    let profile: DouMeowProfileSummary
    let summary: YAMLProfileSummary?
    let isBusy: Bool
    let isRefreshing: Bool
    let use: () -> Void
    let refresh: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ProfileKindBadge(text: kindText, isSelected: profile.isCurrent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(profile.isCurrent ? DouMeowPalette.accent : DouMeowPalette.ink)
                        .lineLimit(1)
                    Text(profile.sourceDescription)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DouMeowPalette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let summary {
                        Text(summary.detailText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DouMeowPalette.muted)
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    if let modifiedAt = profile.updatedAt ?? summary?.modifiedAt {
                        Text(relativeUpdatedAtText(modifiedAt))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DouMeowPalette.muted)
                    }

                    if profile.kind == .remote {
                        Button(action: refresh) {
                            if isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(width: 24, height: 24)
                        .disabled(isBusy)
                        .help("刷新远程配置")
                    }

                    Toggle(
                        "",
                        isOn: Binding(
                            get: { profile.isCurrent },
                            set: { isOn in
                                if isOn, !profile.isCurrent {
                                    use()
                                }
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(DouMeowPalette.accent)
                    .fixedSize()
                    .allowsHitTesting(!profile.isCurrent && !isBusy)
                    .help(profile.isCurrent ? "当前配置" : "使用配置")
                    .accessibilityLabel(profile.isCurrent ? "当前配置" : "使用配置")

                    Menu {
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([profile.fileURL])
                        }
                        Button("复制路径") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(profile.fileURL.path, forType: .string)
                        }
                        if profile.kind == .remote {
                            Divider()
                            Button("刷新远程配置", action: refresh)
                        }
                        Divider()
                        Button("删除配置", role: .destructive, action: delete)
                            .disabled(profile.id == "default")
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .frame(height: 24)
                    .disabled(isBusy)
                }
                .frame(height: 24)
            }

            if let summary {
                HStack(spacing: 7) {
                    ProfileChip(text: "mode \(summary.modeText)")
                    ProfileChip(text: "端口 \(summary.mixedPortText)")
                    ProfileChip(text: summary.allowLanText)
                    ProfileChip(text: summary.tunText)
                    if profile.isCurrent {
                        ProfileChip(text: "\(summary.proxyGroupCount) 个代理组")
                    }
                }
            }

            if let subscription = profile.subscriptionUserInfo {
                ProfileSubscriptionUsageBlock(subscription: subscription)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DouMeowPalette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DouMeowPalette.faintLine, lineWidth: 1)
        }
        .help(profile.isCurrent ? "当前配置" : "使用右侧开关切换配置")
    }

    private var kindText: String {
        if profile.id == "default" { return "默认" }
        return profile.kind == .remote ? "远端" : "本地"
    }

    private func relativeUpdatedAtText(_ date: Date) -> String {
        let now = Date()
        let elapsed = now.timeIntervalSince(date)
        if elapsed >= 0, elapsed < 60 { return "刚刚" }
        return Self.relativeTimeFormatter.localizedString(for: date, relativeTo: now)
    }

    private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        return formatter
    }()
}

private struct ProfileSubscriptionUsageBlock: View {
    let subscription: SubscriptionUserInfo

    private var usageText: String {
        let used = formatByteCount(subscription.used)
        guard subscription.total > 0 else { return "\(used) / 未提供总量" }
        let percent = Int((subscription.progress ?? 0) * 100)
        return "\(used) / \(formatByteCount(subscription.total)) · \(percent)%"
    }

    private var expireText: String {
        guard let expire = subscription.expire, expire > 0 else {
            return "到期：未提供"
        }
        let date = Date(timeIntervalSince1970: TimeInterval(expire))
        return "到期：\(Self.dateFormatter.string(from: date))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(usageText, systemImage: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DouMeowPalette.muted)

            Label(expireText, systemImage: "clock")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if let progress = subscription.progress {
                GradientProgressBar(progress: progress)
                    .frame(maxWidth: 360)
            } else {
                EmptyProgressBar()
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProfileKindBadge: View {
    let text: String
    let isSelected: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(isSelected ? Color.white : DouMeowPalette.muted)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                isSelected ? DouMeowPalette.accent : DouMeowPalette.page,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
    }
}

private struct ProfileChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DouMeowPalette.muted)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color(hex: 0xF0F2F7), in: Capsule())
    }
}

private struct StatusStrip: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            Text("网络接管")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DouMeowPalette.accent)
            Spacer()
            StatusChip(title: "模式", value: state.modeText)
            StatusChip(title: "Controller", value: "\(state.controllerPort)")
        }
    }
}

private struct StatusChip: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color(hex: 0xF0F2F7), in: Capsule())
    }
}

private struct NetworkManageCard: View {
    @EnvironmentObject private var state: AppState
    let openProfiles: () -> Void

    private var subscription: SubscriptionUserInfo? {
        state.currentProfile?.subscriptionUserInfo
    }

    private var usageTitle: String {
        subscription == nil ? "远程配置用量未提供" : "远程配置用量"
    }

    private var usageDetailText: String {
        guard let subscription else {
            if state.currentProfile?.kind == .local {
                return "本地 YAML 没有远程配置用量信息"
            }
            return "远程配置没有返回用量信息"
        }
        guard subscription.total > 0 else {
            return "已使用 \(formatByteCount(subscription.used))"
        }
        return "已使用 \(formatByteCount(subscription.used))"
    }

    private var footerText: String {
        if let expire = subscription?.expire, expire > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(expire))
            return "到期：\(Self.dateFormatter.string(from: date))"
        }
        if let updatedAt = state.currentProfile?.updatedAt {
            return "最后更新：\(Self.dateFormatter.string(from: updatedAt))"
        }
        return "导入或刷新远程配置后显示真实用量"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "archivebox")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(state.currentProfileName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("YAML")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.08), in: Capsule())
                    }
                    Text(usageTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                CorePowerSwitch()
            }

            if let subscription {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已使用")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatByteCount(subscription.used))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    if subscription.total > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int((subscription.progress ?? 0) * 100))%")
                                .font(.headline.weight(.semibold))
                                .monospacedDigit()
                            Text("共 \(formatByteCount(subscription.total))")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("总量未提供")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: subscription.progress ?? 0)
                    .progressViewStyle(.linear)
                    .tint(DouMeowPalette.accent)
                    .accessibilityLabel("远程配置用量")
                    .accessibilityValue(usageDetailText)
            } else {
                Label(usageDetailText, systemImage: "chart.bar.xaxis")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)

                ProgressView(value: 0)
                    .progressViewStyle(.linear)
                    .tint(DouMeowPalette.accent)
                    .accessibilityLabel("远程配置用量未提供")
            }

            HStack(spacing: 10) {
                Label(footerText, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    FooterActionButton(title: "刷新", systemImage: "arrow.clockwise") {
                        Task { await state.refresh() }
                    }

                    FooterActionButton(title: "配置文件", systemImage: "doc.badge.gearshape") {
                        openProfiles()
                    }
                }
            }
        }
        .padding(20)
        .frame(minHeight: 174)
        .surfaceCard()
    }
}

private struct FooterActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}

private struct CorePowerSwitch: View {
    @EnvironmentObject private var state: AppState

    private var statusColor: Color {
        switch state.core.status {
        case .running:
            DouMeowPalette.accent
        case .starting:
            DouMeowPalette.orange
        case .failed, .missingBinary:
            Color.red
        case .stopped:
            DouMeowPalette.muted
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Toggle("内核总开关", isOn: Binding(
                get: {
                    switch state.core.status {
                    case .starting, .running:
                        true
                    case .stopped, .missingBinary, .failed:
                        false
                    }
                },
                set: { isOn in
                    isOn ? state.connect() : state.disconnect()
                }
            ))
            .toggleStyle(.switch)
            .tint(DouMeowPalette.accent)
            .controlSize(.small)
            .labelsHidden()
            .disabled(state.core.status == .starting)
            .help(state.core.status.isHealthy ? "内核总开关：停止内核" : "内核总开关：启动内核")

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(state.core.status.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GradientProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                if progress > 0 {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [DouMeowPalette.accent, DouMeowPalette.accent.opacity(0.72)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: proxy.size.width * progress)
                }
            }
        }
        .frame(height: 9)
    }
}

private struct EmptyProgressBar: View {
    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.10))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.20))
                    .frame(width: 0)
            }
            .frame(height: 9)
    }
}

private struct RouteModeCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("出口模式")
                    .font(.system(size: 16, weight: .bold))
                Text("选择当前网络流量的处理策略")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DouMeowPalette.muted)
            }

            VStack(spacing: 14) {
                RouteModeRow(label: "RULE", title: "规则", subtitle: MihomoMode.rule.detail, selected: state.effectiveForwardingMode == .rule) {
                    state.setForwardingMode(.rule)
                }
                RouteModeRow(label: "ALL", title: "全局", subtitle: MihomoMode.global.detail, selected: state.effectiveForwardingMode == .global) {
                    state.setForwardingMode(.global)
                }
                RouteModeRow(label: "DIR", title: "直连", subtitle: MihomoMode.direct.detail, selected: state.effectiveForwardingMode == .direct) {
                    state.setForwardingMode(.direct)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 212, alignment: .topLeading)
        .surfaceCard()
    }
}

private struct RouteModeRow: View {
    let label: String
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? DouMeowPalette.accent : DouMeowPalette.muted)
                    .frame(width: 34, height: 26)
                    .background((selected ? DouMeowPalette.accent : DouMeowPalette.muted).opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DouMeowPalette.ink)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DouMeowPalette.muted)
                }

                Spacer()

                Circle()
                    .fill(selected ? DouMeowPalette.accent : DouMeowPalette.faintLine)
                    .frame(width: 7, height: 7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ProxyNodeCard: View {
    @EnvironmentObject private var state: AppState
    let openProxies: () -> Void

    private var nodes: [OverviewProxyNode] {
        state.overviewProxyNodes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("配置节点")
                        .font(.system(size: 16, weight: .bold))
                    Text("当前选择与低延迟服务器")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DouMeowPalette.muted)
                }
                Spacer()
                Button("查看全部", action: openProxies)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DouMeowPalette.accent)
            }

            VStack(spacing: 16) {
                if nodes.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "server.rack")
                            .foregroundStyle(DouMeowPalette.muted)
                        Text("当前配置未声明 proxies 节点")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DouMeowPalette.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 86, alignment: .center)
                } else {
                    ForEach(Array(nodes.enumerated()), id: \.element.id) { index, item in
                        Button {
                            Task {
                                if let group = state.primaryProxyGroup {
                                    await state.selectProxy(groupID: group.id, proxyName: item.node.name)
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(item.node.typeLabel.prefix(3))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(DouMeowPalette.muted)
                                    .frame(width: 30, height: 24)
                                    .background(Color(hex: 0xF0F2F7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.node.displayName)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(DouMeowPalette.ink)
                                        .lineLimit(1)
                                    Text(item.detailText.isEmpty ? item.node.endpointText : item.detailText)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(item.isSelected ? DouMeowPalette.accent : DouMeowPalette.muted)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Circle()
                                    .fill(index == 0 ? DouMeowPalette.accent : DouMeowPalette.faintLine)
                                    .frame(width: 7, height: 7)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 212, alignment: .topLeading)
        .surfaceCard()
    }
}

private struct FeatureCard: View {
    let title: String
    let subtitle: String
    let stateText: String
    let stateColor: Color
    let isOn: Bool
    let actionImage: String?
    var isDisabled = false
    let onToggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { isOn },
                    set: { newValue in onToggle(newValue) }
                ))
                    .toggleStyle(.switch)
                    .tint(DouMeowPalette.accent)
                    .labelsHidden()
                    .disabled(isDisabled)
            }

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            HStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 10, height: 10)
                Text(stateText)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let actionImage {
                    Image(systemName: actionImage)
                        .font(.system(size: 15, weight: .bold))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .surfaceCard()
    }
}

private struct ActivityHeader: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("活动")
                .font(.system(size: 28, weight: .bold))
            HStack(spacing: 80) {
                HeaderMetric(title: "网络", value: "Home")
                HeaderMetric(title: "配置文件", value: state.currentProfileName)
                HeaderMetric(title: "出口模式", value: "\(state.effectiveForwardingMode.title)（\(state.modeText)）")
                HeaderMetric(title: "外部 IP", value: "203.0.113.1")
            }
        }
    }
}

private struct HeaderMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold))
        }
    }
}

private struct ActivityGrid: View {
    @EnvironmentObject private var state: AppState
    @State private var activityColumnHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 18) {
                LatencyCard()
                    .frame(maxWidth: .infinity)

                HStack(spacing: 18) {
                    ThroughputCard(
                        title: "上传",
                        value: formatByteCount(state.traffic.up),
                        samples: state.uploadSparklineSamples,
                        accent: DouMeowPalette.accent
                    )
                    .frame(maxWidth: .infinity)
                    ThroughputCard(
                        title: "下载",
                        value: formatByteCount(state.traffic.down),
                        samples: state.downloadSparklineSamples,
                        accent: DouMeowPalette.accent
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 24) {
                    SummaryCard(
                        title: "活动连接",
                        value: state.connectionCountText,
                        details: [
                            ("进程", "\(state.activityProcessCount)"),
                            ("设备", "—"),
                            ("DHCP 设备", "—")
                        ],
                        statusColor: state.core.status.isHealthy ? DouMeowPalette.accent : DouMeowPalette.orange,
                        todoDetailTitles: ["设备", "DHCP 设备"]
                    )
                    TotalTrafficCard()
                }
                .frame(maxWidth: .infinity)
                .reportHeight()

                TrafficListCard()
                    .frame(maxWidth: .infinity)
                    .frame(height: activityColumnHeight > 0 ? activityColumnHeight : nil, alignment: .top)
            }
            .onPreferenceChange(ViewHeightKey.self) { activityColumnHeight = $0 }
        }
    }
}

private struct LatencyCard: View {
    @EnvironmentObject private var state: AppState
    @State private var isShowingDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text("互联网延迟")
                    .font(.system(size: 14, weight: .bold))
                if state.isDiagnosingInternetLatency {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Button {
                        Task { await state.diagnoseInternetLatency() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("诊断") {
                    isShowingDiagnostics = true
                    Task { await state.diagnoseInternetLatency() }
                }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .padding(.horizontal, 12)
                    .background(Color(hex: 0xF5F7FA), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .disabled(state.isDiagnosingInternetLatency)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(state.activityInternetLatencyText.replacingOccurrences(of: " ms", with: ""))
                    .font(.system(size: 28, weight: .bold))
                Text("ms")
                    .font(.system(size: 13, weight: .bold))
            }
            HStack(spacing: 0) {
                MiniMetric(title: "路由器", value: state.activityRouterLatencyText)
                Divider()
                MiniMetric(title: "DNS", value: state.activityDNSLatencyText)
                Divider()
                MiniMetric(title: "当前节点", value: state.activitySelectedProxyDelayText)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .surfaceCard()
        .task {
            await state.diagnoseInternetLatencyIfNeeded()
        }
        .sheet(isPresented: $isShowingDiagnostics) {
            NetworkDiagnosticsSheet()
                .environmentObject(state)
        }
    }
}

private struct NetworkDiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("网络诊断")
                    .font(.system(size: 15, weight: .semibold))
                Text("网络诊断工具可以协助你快速地找到问题。")
                    .font(.system(size: 12))
                    .foregroundStyle(DouMeowPalette.muted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    diagnosticsSummary
                    diagnosticsLog
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 280)

            Divider()

            HStack {
                if state.isDiagnosingInternetLatency {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 690, height: 520)
    }

    private var diagnosticsSummary: some View {
        HStack(spacing: 0) {
            MiniMetric(title: "公网", value: state.activityInternetLatencyText)
            Divider()
            MiniMetric(title: "路由器", value: state.activityRouterLatencyText)
            Divider()
            MiniMetric(title: "DNS", value: state.activityDNSLatencyText)
            Divider()
            MiniMetric(title: "当前节点", value: state.activitySelectedProxyDelayText)
        }
        .padding(14)
        .background(Color(hex: 0xF7F8FB), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var diagnosticsLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(state.internetLatencySnapshot.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DouMeowPalette.ink)
                    Text("\(symbol(for: entry.level)) \(entry.message)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(color(for: entry.level))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if state.internetLatencySnapshot.entries.isEmpty {
                Text(state.isDiagnosingInternetLatency ? "正在诊断..." : "尚无诊断结果")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DouMeowPalette.muted)
            }
        }
    }

    private func symbol(for level: InternetDiagnosticEntry.Level) -> String {
        switch level {
        case .success: return "✓"
        case .warning: return "⚠"
        case .info: return "•"
        }
    }

    private func color(for level: InternetDiagnosticEntry.Level) -> Color {
        switch level {
        case .success: return Color(red: 0.18, green: 0.62, blue: 0.32)
        case .warning: return DouMeowPalette.orange
        case .info: return DouMeowPalette.muted
        }
    }
}

private struct ThroughputCard: View {
    let title: String
    let value: String
    let samples: [Int]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(value)
                    .font(.system(size: 28, weight: .bold))
                Text("/s")
                    .font(.system(size: 13, weight: .bold))
            }
            Spacer()
            Sparkline(samples: samples, accent: accent)
                .frame(height: 34)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .surfaceCard()
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let details: [(String, String)]
    let statusColor: Color
    var todoDetailTitles: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 11, height: 11)
            }
            Text(value)
                .font(.system(size: 31, weight: .bold))
            HStack(spacing: 0) {
                ForEach(details, id: \.0) { item in
                    MiniMetric(
                        title: item.0,
                        value: item.1,
                        showsTodo: todoDetailTitles.contains(item.0)
                    )
                    if item.0 != details.last?.0 {
                        Divider()
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .surfaceCard()
    }
}

private struct TotalTrafficCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("总流量")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("今日")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 28)
                    .frame(height: 22)
                    .foregroundStyle(DouMeowPalette.ink)
                    .background(Color.white, in: Capsule())
                HStack(spacing: 4) {
                    Text("本月")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TodoBadge()
                }
                .padding(.horizontal, 12)
                .frame(height: 22)
                .background(Color(hex: 0xF0F2F7), in: Capsule())
            }
            Text(formatByteCount(state.activityCumulativeTrafficTotal))
                .font(.system(size: 31, weight: .bold))
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("直连")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TodoBadge()
                    }
                    Text("—")
                        .font(.system(size: 13, weight: .bold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("节点")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TodoBadge()
                    }
                    Text("—")
                        .font(.system(size: 13, weight: .bold))
                }
            }
            HStack(spacing: 5) {
                Capsule().fill(DouMeowPalette.accent.opacity(0.35)).frame(maxWidth: .infinity)
                Capsule().fill(DouMeowPalette.accent.opacity(0.35)).frame(maxWidth: .infinity)
            }
            .frame(height: 9)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .surfaceCard()
    }
}

private struct TrafficListCard: View {
    @EnvironmentObject private var state: AppState
    @State private var scopeIndex = 0
    @State private var tabIndex = 0

    private var rows: [(String, String, Color)] {
        guard tabIndex == 0 else { return [] }
        let liveRows = state.activityTrafficRows.prefix(5).map { row in
            (row.name, formatByteCount(row.bytes), DouMeowPalette.accent)
        }
        if !liveRows.isEmpty {
            return Array(liveRows)
        }
        guard state.core.status.isHealthy else { return [] }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("流量")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                SegmentedPill(labels: ["全部", "节点"], selection: $scopeIndex, todoIndices: [1])
            }

            BarTimeline(samples: state.trafficHistory.map(\.total))
                .frame(height: 54)

            SegmentedPill(labels: ["客户端", "域名", "策略"], compact: true, selection: $tabIndex, todoIndices: [1, 2])

            Group {
                if tabIndex != 0 {
                    HStack(spacing: 6) {
                        TodoBadge()
                        Text("该维度统计尚未实现")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DouMeowPalette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else if scopeIndex == 1 {
                    HStack(spacing: 6) {
                        TodoBadge()
                        Text("节点流量筛选尚未实现")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DouMeowPalette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else if rows.isEmpty {
                    Text(state.core.status.isHealthy ? "暂无客户端流量数据" : "启动内核后可查看流量统计")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DouMeowPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    VStack(spacing: 10) {
                        ForEach(rows, id: \.0) { row in
                            TrafficRow(name: row.0, value: row.1, color: row.2)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .surfaceCard()
    }
}

private struct MiniMetric: View {
    let title: String
    let value: String
    var showsTodo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                if showsTodo {
                    TodoBadge()
                }
            }
            Text(value)
                .font(.system(size: 15, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }
}

private struct TodoBadge: View {
    var body: some View {
        Text("TODO")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(DouMeowPalette.orange)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(DouMeowPalette.orange.opacity(0.12), in: Capsule())
    }
}

private struct Sparkline: View {
    let samples: [Int]
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let points = normalizedPoints(in: CGSize(width: width, height: height))

            if points.count >= 2 {
                Path { path in
                    path.move(to: points[0])
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                if let last = points.last {
                    Circle()
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .overlay(Circle().stroke(accent, lineWidth: 2))
                        .frame(width: 7, height: 7)
                        .position(last)
                }
            } else {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height * 0.68))
                    path.addCurve(
                        to: CGPoint(x: width, y: height * 0.62),
                        control1: CGPoint(x: width * 0.34, y: height * 0.74),
                        control2: CGPoint(x: width * 0.66, y: height * 0.54)
                    )
                }
                .stroke(accent.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !samples.isEmpty else { return [] }
        let maxValue = max(samples.max() ?? 0, 1)
        let stepX = size.width / CGFloat(max(samples.count - 1, 1))
        return samples.enumerated().map { index, sample in
            let x = CGFloat(index) * stepX
            let ratio = CGFloat(sample) / CGFloat(maxValue)
            let y = size.height - (ratio * size.height * 0.85 + size.height * 0.08)
            return CGPoint(x: x, y: y)
        }
    }
}

private struct BarTimeline: View {
    let samples: [Int]

    private var displayedSamples: [Int] {
        Array(samples.suffix(18))
    }

    private var bars: [CGFloat] {
        guard !displayedSamples.isEmpty else {
            return Array(repeating: 0.08, count: 18)
        }
        let maxValue = max(displayedSamples.max() ?? 1, 1)
        return displayedSamples.map { CGFloat($0) / CGFloat(maxValue) }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(DouMeowPalette.accent.opacity(displayedSamples.isEmpty ? 0.25 : 1))
                    .frame(width: 5, height: max(3, 44 * bar))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider().offset(y: -6)
        }
    }
}

private struct SegmentedPill: View {
    let labels: [String]
    var compact = false
    @Binding var selection: Int
    var todoIndices: Set<Int> = []

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Button {
                    selection = index
                } label: {
                    HStack(spacing: 4) {
                        Text(label)
                        if todoIndices.contains(index) {
                            TodoBadge()
                        }
                    }
                    .font(.system(size: compact ? 11 : 12, weight: selection == index ? .bold : .medium))
                    .foregroundStyle(selection == index ? DouMeowPalette.ink : DouMeowPalette.muted)
                    .frame(minWidth: compact ? 70 : 58)
                    .frame(height: compact ? 20 : 22)
                    .background(selection == index ? Color.white : Color.clear, in: Capsule())
                    .shadow(color: selection == index ? .black.opacity(0.04) : .clear, radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color(hex: 0xF0F2F7), in: Capsule())
    }
}

private struct TrafficRow: View {
    let name: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 17, height: 17)
                .overlay {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.secondary.opacity(0.10))
                    .frame(width: proxy.size.width * 0.78, height: 3)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 16)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 76, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension View {
    func reportHeight() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: ViewHeightKey.self, value: proxy.size.height)
            }
        }
    }

    func surfaceCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(DouMeowPalette.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DouMeowPalette.faintLine, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.025), radius: 6, x: 0, y: 2)
    }
}

private func formatByteCount(_ value: Int) -> String {
    let units = ["B", "KB", "MB", "GB"]
    var number = Double(max(0, value))
    var unitIndex = 0
    while number >= 1024, unitIndex < units.count - 1 {
        number /= 1024
        unitIndex += 1
    }
    if unitIndex == 0 {
        return "\(Int(number)) \(units[unitIndex])"
    }
    return String(format: "%.1f %@", number, units[unitIndex])
}
