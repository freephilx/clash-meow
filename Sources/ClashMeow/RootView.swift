import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum ClashMeowPalette {
    static let purple = Color(hex: 0x845CFB)
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

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .overview: "house"
        case .profiles: "archivebox"
        case .proxies: "point.3.connected.trianglepath.dotted"
        case .connections: "network"
        case .logs: "doc.text.magnifyingglass"
        case .rules: "list.bullet.rectangle"
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
        SidebarGroup(id: "daily", title: "常用", destinations: [.overview, .profiles, .proxies]),
        SidebarGroup(id: "inspect", title: "检查", destinations: [.connections, .rules, .logs])
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
        .background(ClashMeowPalette.page)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sidebarGroups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ClashMeowPalette.muted)
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
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
            }
        }
        .background(ClashMeowPalette.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    }

    private var detail: some View {
        ZStack(alignment: .top) {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ClashMeowPalette.page)

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
        }
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
            .foregroundStyle(isSelected ? ClashMeowPalette.purple : ClashMeowPalette.ink)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background(
                isSelected ? ClashMeowPalette.sidebarSelection : Color.clear,
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
                    .foregroundStyle(ClashMeowPalette.ink)

                content
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ClashMeowPalette.page)
    }
}

private struct AppToastView: View {
    let toast: AppToast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ClashMeowPalette.purple)
            Text(toast.message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ClashMeowPalette.ink)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(ClashMeowPalette.card, in: Capsule())
        .overlay(
            Capsule()
                .stroke(ClashMeowPalette.faintLine, lineWidth: 1)
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
                                .foregroundStyle(ClashMeowPalette.ink)
                                .lineLimit(1)
                            Text("\(nodes.count)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ClashMeowPalette.muted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: 0xF0F2F7), in: Capsule())
                        }
                        Text(group.displayNow)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ClashMeowPalette.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ClashMeowPalette.muted)
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
                        .foregroundStyle(ClashMeowPalette.muted)
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
            .fill(isSelected ? ClashMeowPalette.purple : ClashMeowPalette.faintLine)
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
                        .foregroundStyle(ClashMeowPalette.ink)
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
                isSelected ? ClashMeowPalette.purple.opacity(0.10) : Color.white,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? ClashMeowPalette.purple.opacity(0.18) : ClashMeowPalette.faintLine.opacity(0.8),
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
                    .foregroundStyle(ClashMeowPalette.muted)
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
            return ClashMeowPalette.orange
        }
        guard let delay = node.delay else {
            return ClashMeowPalette.muted.opacity(0.8)
        }
        if delay <= 0 {
            return ClashMeowPalette.orange
        }
        if delay < 300 {
            return Color(red: 0.18, green: 0.72, blue: 0.38)
        }
        return ClashMeowPalette.orange
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
                .foregroundStyle(ClashMeowPalette.purple)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(connection.displayHost)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ClashMeowPalette.ink)
                    .lineLimit(1)
                Text([connection.rule, connection.rulePayload, connection.chains?.joined(separator: " / ")].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ClashMeowPalette.muted)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("↑ \(formatByteCount(connection.upload ?? 0))")
                Text("↓ \(formatByteCount(connection.download ?? 0))")
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(ClashMeowPalette.muted)

            Button(role: .destructive) {
                Task { await state.closeConnection(connection) }
            } label: {
                Image(systemName: "xmark.circle")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ClashMeowPalette.orange)
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
    @State private var level: LogLevelFilter = LogPreference.defaultLevel
    @State private var source: LogSourceFilter = LogPreference.defaultSource
    @State private var confirmsClearingFile = false

    private let sourceFilters: [LogSourceFilter] = [.all, .core, .app]

    private var filteredLogs: [CoreLogEntry] {
        state.logs.filter { log in
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
        PageScaffold(title: "日志") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("搜索日志", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    Button("刷新") {
                        state.loadLogs(source: source)
                    }
                }

                RuleOptionRow {
                    ForEach(sourceFilters) { item in
                        RuleOptionButton(
                            title: item.title,
                            isSelected: source == item,
                            color: ClashMeowPalette.purple
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
                            color: ClashMeowPalette.purple
                        ) {
                            level = item
                        }
                    }
                }

                RuleOptionRow {
                    LogActionButton(title: state.isStreamingLogs ? "暂停" : "跟随") {
                        if state.isStreamingLogs {
                            state.stopLogStream()
                        } else {
                            state.startLogStream(level: level)
                        }
                    }
                    .disabled(!state.core.status.isHealthy)

                    LogActionButton(title: "清空") {
                        state.clearLogs()
                    }
                    .disabled(state.logs.isEmpty)

                    LogActionButton(title: "打开文件") {
                        state.openLogFile(source: source)
                    }

                    LogActionButton(title: "在 Finder 中显示") {
                        state.revealLogFile(source: source)
                    }

                    if LogPreference.allowsDestructiveFileActions {
                        LogActionButton(title: "清空文件") {
                            confirmsClearingFile = true
                        }
                    }
                }

                if filteredLogs.isEmpty {
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? "暂无日志" : "无匹配结果", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text(
                            searchText.isEmpty
                                ? (state.core.status.isHealthy ? "点击跟随可查看内核实时日志。" : "启动内核后可查看 core.log 与实时日志。")
                                : "试试其他搜索词。"
                        )
                    } actions: {
                        Button("刷新") {
                            state.loadLogs(source: source)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredLogs) { item in
                            CoreLogRow(log: item)
                                .contextMenu {
                                    Button("复制消息") {
                                        writeToPasteboard(item.message)
                                    }
                                    Button("复制可见日志") {
                                        writeToPasteboard(filteredLogs.map(\.message).joined(separator: "\n"))
                                    }
                                }
                        }
                    }
                }
            }
        }
        .task {
            state.loadLogs(source: source)
        }
        .alert("清空日志文件？", isPresented: $confirmsClearingFile) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                state.clearLogFile(source: source)
            }
        } message: {
            Text("这会清空当前来源对应的持久日志文件，重启后也无法恢复。")
        }
        .onChange(of: level) { _, newLevel in
            LogPreference.defaultLevel = newLevel
            if state.isStreamingLogs {
                state.startLogStream(level: newLevel)
            }
        }
        .onChange(of: source) { _, newSource in
            LogPreference.defaultSource = newSource
            state.loadLogs(source: newSource)
        }
    }

    private func writeToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

private struct LogActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ClashMeowPalette.ink.opacity(0.76))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Color(hex: 0xE7ECF3), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct CoreLogRow: View {
    let log: CoreLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(log.source.title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(ClashMeowPalette.muted)
                .frame(width: 42, alignment: .leading)
            Text(log.level.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(levelColor)
                .frame(width: 62, alignment: .leading)
            Text(log.message)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ClashMeowPalette.ink)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if let time = log.time {
                Text(time)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ClashMeowPalette.muted)
            }
        }
        .padding(12)
        .surfaceCard()
        .contextMenu {
            Button("复制消息") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(log.message, forType: .string)
            }
        }
    }

    private var levelColor: Color {
        switch log.normalizedLevel {
        case "error":
            ClashMeowPalette.orange
        case "warning":
            ClashMeowPalette.orange
        default:
            ClashMeowPalette.purple
        }
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
                    .foregroundStyle(ClashMeowPalette.ink)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClashMeowPalette.muted)
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
    @State private var selectedTab: RuleRuntimeTab = .rules
    @State private var sortOrder: RuleSortOrder = .natural
    @State private var typeFilters = Set<String>()
    @State private var policyFilters = Set<String>()
    @State private var isAddingRuleOverride = false
    private let leadingOptionWidth: CGFloat = 78

    private var filteredRules: [RuleItem] {
        let searched = state.rules.filter { rule in
            let matchesSearch = searchText.isEmpty
                || rule.type.localizedCaseInsensitiveContains(searchText)
                || rule.payload.localizedCaseInsensitiveContains(searchText)
                || rule.proxy.localizedCaseInsensitiveContains(searchText)
            let matchesType = typeFilters.isEmpty || typeFilters.contains(rule.type)
            let matchesPolicy = policyFilters.isEmpty || policyFilters.contains(rule.proxy)
            return matchesSearch && matchesType && matchesPolicy
        }
        return sortOrder.sort(searched)
    }

    private var filteredRuleProviders: [RuleProviderItem] {
        guard !searchText.isEmpty else { return state.ruleProviders }
        return state.ruleProviders.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.behavior?.localizedCaseInsensitiveContains(searchText) ?? false)
                || ($0.vehicleType?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var typeFacets: [(value: String, count: Int)] {
        facets(for: state.rules.map(\.type))
    }

    private var policyFacets: [(value: String, count: Int)] {
        facets(for: state.rules.map(\.proxy))
    }

    private var hasActiveFilters: Bool {
        !searchText.isEmpty || !typeFilters.isEmpty || !policyFilters.isEmpty
    }

    var body: some View {
        PageScaffold(title: "规则") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    TextField(selectedTab == .rules ? "搜索规则" : "搜索规则集合", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        Task { await state.refreshRules() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }

                    Button {
                        isAddingRuleOverride = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("添加规则")
                    .accessibilityLabel("添加规则")

                    if selectedTab == .ruleProviders {
                        Button {
                            Task { await state.updateAllRuleProviders() }
                        } label: {
                            Label("全部更新", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(state.ruleProviders.isEmpty || !state.core.status.isHealthy || !state.updatingRuleProviderNames.isEmpty)
                    }
                }

                HStack(spacing: 10) {
                    RuleOptionRow {
                        ForEach(RuleRuntimeTab.allCases) { tab in
                            RuleOptionButton(
                                title: "\(tab.title) \(tab.count(rules: state.rules, providers: state.ruleProviders))",
                                isSelected: selectedTab == tab,
                                color: ClashMeowPalette.purple
                            ) {
                                selectedTab = tab
                            }
                        }
                    }
                }

                if selectedTab == .rules {
                    rulesToolbar

                    if filteredRules.isEmpty {
                        ContentUnavailableView {
                            Label(hasActiveFilters ? "没有匹配规则" : "暂无规则", systemImage: "list.bullet.rectangle")
                        } description: {
                            Text(hasActiveFilters ? "清除筛选或换一个关键词。" : (state.core.status.isHealthy ? "controller 暂未返回规则。" : "启动内核后可读取运行时规则。"))
                        } actions: {
                            Button(hasActiveFilters ? "清除筛选" : "刷新") {
                                if hasActiveFilters {
                                    clearFilters()
                                } else {
                                    Task { await state.refreshRules() }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)

                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredRules) { rule in
                                RuleRow(rule: rule)
                            }
                        }
                    }
                } else {
                    if filteredRuleProviders.isEmpty {
                        ContentUnavailableView {
                            Label(searchText.isEmpty ? "暂无规则集合" : "没有匹配规则集合", systemImage: "tray.full")
                        } description: {
                            Text(searchText.isEmpty ? "当前配置没有 rule-providers，或 controller 暂未返回规则集合。" : "换一个关键词试试。")
                        } actions: {
                            Button("刷新") {
                                Task { await state.refreshRules() }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredRuleProviders) { provider in
                                RuleProviderRow(provider: provider)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await state.refreshRules()
        }
        .sheet(isPresented: $isAddingRuleOverride) {
            AddRuleOverrideView()
                .environmentObject(state)
        }
    }

    private var rulesToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RuleOptionRow {
                    ForEach(RuleSortOrder.allCases) { order in
                        RuleOptionButton(
                            title: order.title,
                            isSelected: sortOrder == order,
                            color: ClashMeowPalette.purple,
                            width: order == .natural ? leadingOptionWidth : nil
                        ) {
                            sortOrder = order
                        }
                    }
                }

                Text("\(filteredRules.count) / \(state.rules.count) 条规则")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ClashMeowPalette.muted)

                Spacer()

                if hasActiveFilters {
                    Button {
                        clearFilters()
                    } label: {
                        Text("清除筛选")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ClashMeowPalette.purple)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(ClashMeowPalette.purple.opacity(0.10), in: Capsule())
                }
            }

            RuleFacetStrip(
                facets: typeFacets,
                selectedValues: typeFilters,
                color: ClashMeowPalette.purple,
                leadingWidth: leadingOptionWidth
            ) { value in
                toggle(value, in: &typeFilters)
            } clear: {
                typeFilters.removeAll()
            }

            RuleFacetStrip(
                facets: policyFacets,
                selectedValues: policyFilters,
                color: ClashMeowPalette.purple,
                leadingWidth: leadingOptionWidth
            ) { value in
                toggle(value, in: &policyFilters)
            } clear: {
                policyFilters.removeAll()
            }
        }
    }

    private func clearFilters() {
        searchText = ""
        typeFilters.removeAll()
        policyFilters.removeAll()
    }

    private func facets(for values: [String]) -> [(value: String, count: Int)] {
        let counts = values.reduce(into: [String: Int]()) { result, value in
            result[value, default: 0] += 1
        }
        return counts
            .map { (value: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.value.localizedStandardCompare($1.value) == .orderedAscending
            }
    }

    private func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }
}

struct AddRuleOverrideView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @State private var draft = RuleOverrideDraft()
    @State private var placement: RuleOverridePlacement = .prepend

    private var proxyOptions: [String] {
        let builtin = ["DIRECT", "REJECT"]
        let groups = state.activeProfileProxyGroups.map(\.name)
        let nodes = state.activeProfileNodes.map(\.name)
        return Array(Set(builtin + groups + nodes)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var canSubmit: Bool {
        draft.isValid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加规则")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(ClashMeowPalette.ink)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("位置")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ClashMeowPalette.muted)
                        WrappingRuleOptionRow {
                            ForEach(RuleOverridePlacement.allCases) { item in
                                RuleOptionButton(
                                    title: item.title,
                                    isSelected: placement == item,
                                    color: ClashMeowPalette.purple,
                                    width: 78
                                ) {
                                    placement = item
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("类型")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ClashMeowPalette.muted)
                        WrappingRuleOptionRow {
                            ForEach(RuleOverrideDraft.commonTypes, id: \.self) { type in
                                RuleOptionButton(
                                    title: type,
                                    isSelected: draft.type == type,
                                    color: ClashMeowPalette.purple
                                ) {
                                    draft.type = type
                                    draft.normalizeForSelectedType()
                                }
                            }
                        }
                    }

                    TextField("匹配内容", text: $draft.payload)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!draft.requiresPayload)
                        .onSubmit { submit() }

                    TextField("出站策略", text: $draft.proxy)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { submit() }

                    if !proxyOptions.isEmpty {
                        WrappingRuleOptionRow {
                            ForEach(proxyOptions, id: \.self) { proxy in
                                RuleOptionButton(
                                    title: proxy,
                                    isSelected: draft.proxy == proxy,
                                    color: ClashMeowPalette.purple
                                ) {
                                    draft.proxy = proxy
                                }
                            }
                        }
                    }

                    if draft.supportsNoResolve || draft.supportsSource {
                        HStack(spacing: 14) {
                            if draft.supportsNoResolve {
                                Toggle("no-resolve", isOn: $draft.noResolve)
                            }
                            if draft.supportsSource {
                                Toggle("src", isOn: $draft.source)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
            .frame(maxHeight: 480)

            VStack(alignment: .leading, spacing: 8) {
                Text("实时结果")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ClashMeowPalette.muted)
                Text(draft.ruleText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ClashMeowPalette.purple)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ClashMeowPalette.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("确定") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 560)
        .frame(maxHeight: 620)
    }

    private func submit() {
        guard canSubmit else { return }
        let rule = draft.ruleText
        let selectedPlacement = placement
        Task {
            await state.addRuleOverride(rule, placement: selectedPlacement)
            dismiss()
        }
    }
}

private enum RuleRuntimeTab: String, CaseIterable, Identifiable {
    case rules
    case ruleProviders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rules: "规则"
        case .ruleProviders: "规则集合"
        }
    }

    func count(rules: [RuleItem], providers: [RuleProviderItem]) -> Int {
        switch self {
        case .rules: rules.count
        case .ruleProviders: providers.count
        }
    }
}

private enum RuleSortOrder: String, CaseIterable, Identifiable {
    case natural
    case typeAscending
    case typeDescending
    case payloadAscending
    case payloadDescending
    case hitDescending
    case hitAscending
    case lastHitDescending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: "配置顺序"
        case .typeAscending: "类型 A-Z"
        case .typeDescending: "类型 Z-A"
        case .payloadAscending: "匹配内容 A-Z"
        case .payloadDescending: "匹配内容 Z-A"
        case .hitDescending: "命中多到少"
        case .hitAscending: "命中少到多"
        case .lastHitDescending: "最近命中"
        }
    }

    func sort(_ rules: [RuleItem]) -> [RuleItem] {
        switch self {
        case .natural:
            return rules
        case .typeAscending:
            return rules.sorted { $0.type.localizedStandardCompare($1.type) == .orderedAscending }
        case .typeDescending:
            return rules.sorted { $0.type.localizedStandardCompare($1.type) == .orderedDescending }
        case .payloadAscending:
            return rules.sorted { $0.displayPayload.localizedStandardCompare($1.displayPayload) == .orderedAscending }
        case .payloadDescending:
            return rules.sorted { $0.displayPayload.localizedStandardCompare($1.displayPayload) == .orderedDescending }
        case .hitDescending:
            return rules.sorted { left, right in
                if left.hitCount != right.hitCount { return left.hitCount > right.hitCount }
                return left.index < right.index
            }
        case .hitAscending:
            return rules.sorted { left, right in
                if left.hitCount != right.hitCount { return left.hitCount < right.hitCount }
                return left.index < right.index
            }
        case .lastHitDescending:
            return rules.sorted { left, right in
                switch (left.lastHit, right.lastHit) {
                case (.some(let lhs), .some(let rhs)):
                    if lhs != rhs { return lhs > rhs }
                    return left.index < right.index
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return left.index < right.index
                }
            }
        }
    }
}

private struct RuleFacetStrip: View {
    let facets: [(value: String, count: Int)]
    let selectedValues: Set<String>
    let color: Color
    let leadingWidth: CGFloat
    let toggle: (String) -> Void
    let clear: () -> Void

    var body: some View {
        if !facets.isEmpty {
            HStack(spacing: 8) {
                RuleOptionButton(
                    title: "全部",
                    isSelected: selectedValues.isEmpty,
                    color: color,
                    height: 32,
                    fontSize: 12,
                    width: leadingWidth,
                    action: clear
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(facets, id: \.value) { facet in
                            RuleOptionButton(
                                title: "\(facet.value) \(facet.count)",
                                isSelected: selectedValues.contains(facet.value),
                                color: color,
                                height: 32,
                                fontSize: 12
                            ) {
                                toggle(facet.value)
                            }
                        }
                    }
                }
            }
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
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(isSelected ? color : ClashMeowPalette.ink.opacity(0.76))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(width: width, height: height)
                .background(backgroundColor, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        isSelected ? color.opacity(0.14) : Color(hex: 0xE7ECF3)
    }
}

private struct RuleRow: View {
    @EnvironmentObject private var state: AppState
    let rule: RuleItem

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
                Task { await state.setRule(rule, isEnabled: isEnabled) }
            })
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(!state.core.status.isHealthy)

            Text(rule.type)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(ClashMeowPalette.purple)
                .frame(width: 96, alignment: .leading)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.displayPayload)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ClashMeowPalette.ink)
                    .lineLimit(1)
                Text("命中 \(rule.hitCount) · 未命中 \(rule.missCount) · size \(rule.size) · \(lastActivityText)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ClashMeowPalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            ProfileChip(text: hitRateText)
            Text(rule.proxy)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ClashMeowPalette.muted)
                .frame(width: 110, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(12)
        .surfaceCard()
        .opacity(rule.isEnabled ? 1 : 0.58)
        .contextMenu {
            Button("复制规则") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString("\(rule.type),\(rule.payload),\(rule.proxy)", forType: .string)
            }
        }
    }
}

private struct RuleProviderRow: View {
    @EnvironmentObject private var state: AppState
    let provider: RuleProviderItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ClashMeowPalette.purple)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(provider.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ClashMeowPalette.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    ProfileChip(text: provider.displayBehavior)
                    ProfileChip(text: provider.displayVehicleType)
                    ProfileChip(text: provider.displayFormat)
                    ProfileChip(text: provider.ruleCountText)
                    if let updatedAt = provider.updatedAt, !updatedAt.isEmpty {
                        ProfileChip(text: updatedAt)
                    }
                }
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                Task { await state.updateRuleProvider(provider) }
            } label: {
                if state.isUpdatingRuleProvider(provider) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.plain)
            .disabled(!state.core.status.isHealthy || state.isUpdatingRuleProvider(provider))
            .help("更新规则集合")
        }
        .padding(12)
        .surfaceCard()
        .contextMenu {
            Button("复制名称") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(provider.name, forType: .string)
            }
            Button("更新规则集合") {
                Task { await state.updateRuleProvider(provider) }
            }
            .disabled(!state.core.status.isHealthy)
        }
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
                        stateColor: proxyToggle.isOn ? ClashMeowPalette.purple : ClashMeowPalette.orange,
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
                        stateColor: state.allowLan ? ClashMeowPalette.purple : ClashMeowPalette.orange,
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
                        stateColor: state.isTunEnabled ? ClashMeowPalette.purple : ClashMeowPalette.orange,
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
                .foregroundStyle(ClashMeowPalette.purple)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ClashMeowPalette.ink)
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClashMeowPalette.muted)
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
                        stateColor: state.systemProxyEnabled ? ClashMeowPalette.purple : ClashMeowPalette.orange,
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
                        stateColor: state.isTunEnabled ? ClashMeowPalette.purple : ClashMeowPalette.orange,
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
                        Label("导入配置开始使用", systemImage: "rectangle.stack.badge.plus")
                    } description: {
                        Text("使用远程配置 URL 或本地 YAML。")
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
        .background(ClashMeowPalette.page)
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

    private var displayedProfiles: [ClashMeowProfileSummary] {
        let profileByID = Dictionary(uniqueKeysWithValues: state.profiles.map { ($0.id, $0) })
        var usedIDs = Set<String>()
        var profiles = profileDisplayOrder.compactMap { id -> ClashMeowProfileSummary? in
            guard let profile = profileByID[id] else { return nil }
            usedIDs.insert(id)
            return profile
        }
        profiles.append(contentsOf: profilesWithCurrentFirst(state.profiles).filter { !usedIDs.contains($0.id) })
        return profiles
    }

    private func profilesWithCurrentFirst(_ profiles: [ClashMeowProfileSummary]) -> [ClashMeowProfileSummary] {
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
                .stroke(urlFieldFocused ? ClashMeowPalette.purple : ClashMeowPalette.faintLine, lineWidth: urlFieldFocused ? 2 : 1)
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
                .fill(ClashMeowPalette.purple.opacity(0.08))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    ClashMeowPalette.purple,
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28, weight: .semibold))
                Text("拖入 YAML 以导入配置")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(ClashMeowPalette.purple)
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
    let profile: ClashMeowProfileSummary
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
                        .foregroundStyle(profile.isCurrent ? ClashMeowPalette.purple : ClashMeowPalette.ink)
                        .lineLimit(1)
                    Text(profile.sourceDescription)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ClashMeowPalette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let summary {
                        Text(summary.detailText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ClashMeowPalette.muted)
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    if let modifiedAt = profile.updatedAt ?? summary?.modifiedAt {
                        Text(relativeUpdatedAtText(modifiedAt))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ClashMeowPalette.muted)
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
                    .tint(ClashMeowPalette.purple)
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
        .background(ClashMeowPalette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ClashMeowPalette.faintLine, lineWidth: 1)
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
                .foregroundStyle(ClashMeowPalette.muted)

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
            .foregroundStyle(isSelected ? Color.white : ClashMeowPalette.muted)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                isSelected ? ClashMeowPalette.purple : ClashMeowPalette.page,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
    }
}

private struct ProfileChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ClashMeowPalette.muted)
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
                .foregroundStyle(ClashMeowPalette.purple)
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
        let percentage = Int((subscription.progress ?? 0) * 100)
        return "\(formatByteCount(subscription.used)) / \(formatByteCount(subscription.total)) · \(percentage)%"
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

    private var usageIcon: String {
        subscription == nil ? "chart.bar.xaxis" : "chart.line.uptrend.xyaxis"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 12) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(ClashMeowPalette.muted)
                            .frame(width: 40, height: 40)
                            .background(Color(hex: 0xF7FAFC), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(state.currentProfileName)
                                    .font(.system(size: 16, weight: .bold))
                                Text("YAML")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(ClashMeowPalette.muted)
                                    .padding(.horizontal, 6)
                                    .frame(height: 18)
                                    .background(Color(hex: 0xF0F2F7), in: Capsule())
                            }
                            Text(usageTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ClashMeowPalette.muted)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(primaryUsageText)
                                .font(.system(size: 23, weight: .bold))
                            Text(secondaryUsageText)
                                .font(.system(size: 21, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Label(usageDetailText, systemImage: usageIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ClashMeowPalette.muted)
                    }
                }

                Spacer()

                CorePowerSwitch()
            }

            if let progress = subscription?.progress {
                GradientProgressBar(progress: progress)
            } else {
                EmptyProgressBar()
            }

            HStack(spacing: 12) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text(footerText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(alignment: .center, spacing: 12) {
                    FooterActionButton(title: "刷新", systemImage: "arrow.clockwise") {
                        Task { await state.refresh() }
                    }

                    FooterActionButton(title: "配置文件", systemImage: "doc.badge.gearshape") {
                        openProfiles()
                    }
                }
                .frame(minWidth: 128, alignment: .trailing)
            }
        }
        .padding(22)
        .frame(minHeight: 178)
        .surfaceCard()
    }

    private var primaryUsageText: String {
        guard let subscription else { return "暂无" }
        return formatByteCount(subscription.used)
    }

    private var secondaryUsageText: String {
        guard let subscription else { return "/ 无流量信息" }
        guard subscription.total > 0 else { return "/ 未提供总量" }
        return "/ \(formatByteCount(subscription.total))"
    }
}

private struct FooterActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 13, height: 13, alignment: .center)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .frame(height: 22, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

private struct CorePowerSwitch: View {
    @EnvironmentObject private var state: AppState

    private var statusColor: Color {
        switch state.core.status {
        case .running:
            ClashMeowPalette.purple
        case .starting:
            ClashMeowPalette.orange
        case .failed, .missingBinary:
            Color.red
        case .stopped:
            ClashMeowPalette.muted
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
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
            .tint(ClashMeowPalette.purple)
            .labelsHidden()
            .disabled(state.core.status == .starting)
            .help(state.core.status.isHealthy ? "内核总开关：停止内核" : "内核总开关：启动内核")

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(state.core.status.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ClashMeowPalette.muted)
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
                            colors: [ClashMeowPalette.purple, ClashMeowPalette.purple.opacity(0.72)],
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
                    .foregroundStyle(ClashMeowPalette.muted)
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
                    .foregroundStyle(selected ? ClashMeowPalette.purple : ClashMeowPalette.muted)
                    .frame(width: 34, height: 26)
                    .background((selected ? ClashMeowPalette.purple : ClashMeowPalette.muted).opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ClashMeowPalette.ink)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ClashMeowPalette.muted)
                }

                Spacer()

                Circle()
                    .fill(selected ? ClashMeowPalette.purple : ClashMeowPalette.faintLine)
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
                        .foregroundStyle(ClashMeowPalette.muted)
                }
                Spacer()
                Button("查看全部", action: openProxies)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ClashMeowPalette.purple)
            }

            VStack(spacing: 16) {
                if nodes.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "server.rack")
                            .foregroundStyle(ClashMeowPalette.muted)
                        Text("当前配置未声明 proxies 节点")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ClashMeowPalette.muted)
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
                                    .foregroundStyle(ClashMeowPalette.muted)
                                    .frame(width: 30, height: 24)
                                    .background(Color(hex: 0xF0F2F7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.node.displayName)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(ClashMeowPalette.ink)
                                        .lineLimit(1)
                                    Text(item.detailText.isEmpty ? item.node.endpointText : item.detailText)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(item.isSelected ? ClashMeowPalette.purple : ClashMeowPalette.muted)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Circle()
                                    .fill(index == 0 ? ClashMeowPalette.purple : ClashMeowPalette.faintLine)
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
                    .tint(ClashMeowPalette.purple)
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
                        accent: ClashMeowPalette.purple
                    )
                    .frame(maxWidth: .infinity)
                    ThroughputCard(
                        title: "下载",
                        value: formatByteCount(state.traffic.down),
                        samples: state.downloadSparklineSamples,
                        accent: ClashMeowPalette.purple
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
                        statusColor: state.core.status.isHealthy ? ClashMeowPalette.purple : ClashMeowPalette.orange,
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
                    .foregroundStyle(ClashMeowPalette.muted)
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
                        .foregroundStyle(ClashMeowPalette.ink)
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
                    .foregroundStyle(ClashMeowPalette.muted)
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
        case .warning: return ClashMeowPalette.orange
        case .info: return ClashMeowPalette.muted
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
                    .foregroundStyle(ClashMeowPalette.ink)
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
                Capsule().fill(ClashMeowPalette.purple.opacity(0.35)).frame(maxWidth: .infinity)
                Capsule().fill(ClashMeowPalette.purple.opacity(0.35)).frame(maxWidth: .infinity)
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
            (row.name, formatByteCount(row.bytes), ClashMeowPalette.purple)
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
                            .foregroundStyle(ClashMeowPalette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else if scopeIndex == 1 {
                    HStack(spacing: 6) {
                        TodoBadge()
                        Text("节点流量筛选尚未实现")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ClashMeowPalette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else if rows.isEmpty {
                    Text(state.core.status.isHealthy ? "暂无客户端流量数据" : "启动内核后可查看流量统计")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ClashMeowPalette.muted)
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
            .foregroundStyle(ClashMeowPalette.orange)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(ClashMeowPalette.orange.opacity(0.12), in: Capsule())
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
                    .fill(ClashMeowPalette.purple.opacity(displayedSamples.isEmpty ? 0.25 : 1))
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
                    .foregroundStyle(selection == index ? ClashMeowPalette.ink : ClashMeowPalette.muted)
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

    func surfaceCard() -> some View {
        self
            .background(ClashMeowPalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(ClashMeowPalette.faintLine, lineWidth: 1)
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
