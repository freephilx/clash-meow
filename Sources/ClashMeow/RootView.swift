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
    case profiles = "配置文件"
    case proxies = "节点"
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
    @State private var selection: SidebarDestination? = .overview

    private let sidebarGroups = [
        SidebarGroup(id: "daily", title: "常用", destinations: [.overview, .profiles, .proxies]),
        SidebarGroup(id: "inspect", title: "检查", destinations: [.connections, .logs])
    ]

    var body: some View {
        NavigationSplitView {
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
        } detail: {
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
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selection) { _, newValue in
            if newValue == nil {
                selection = .overview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClashMeowPalette.page)
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
    @State private var titleOffset: CGFloat = 0

    private var headerOpacity: Double {
        Double(min(max((-titleOffset - 12) / 28, 0), 1))
    }

    private var coordinateName: String {
        "page-scroll-\(title)"
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(ClashMeowPalette.ink)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 18)
                        .background(titleOffsetReader)

                    content
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .coordinateSpace(name: coordinateName)
            .onPreferenceChange(PageTitleOffsetKey.self) { titleOffset = $0 }

            FloatingPageHeader(title: title, opacity: headerOpacity)
        }
        .navigationTitle("")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ClashMeowPalette.page)
    }

    private var titleOffsetReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: PageTitleOffsetKey.self,
                value: proxy.frame(in: .named(coordinateName)).minY
            )
        }
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

private struct PageTitleOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ViewHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FloatingPageHeader: View {
    let title: String
    let opacity: Double

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(ClashMeowPalette.faintLine.opacity(0.7))
                        .frame(height: 1)
                }

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ClashMeowPalette.ink)
                .lineLimit(1)
        }
        .frame(height: 48)
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

private struct ProxiesContent: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedGroups = Set<String>()

    var body: some View {
        PageScaffold(title: "节点") {
            Group {
                if state.visibleProxyGroups.isEmpty {
                    ContentUnavailableView {
                        Label(state.effectiveForwardingMode == .direct ? "直连模式" : "暂无节点组", systemImage: "point.3.connected.trianglepath.dotted")
                    } description: {
                        Text(state.effectiveForwardingMode == .direct ? "当前模式不展示代理组。" : (state.core.status.isHealthy ? "当前配置没有可选择的节点组。" : "启动内核或导入包含节点组的配置。"))
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
            Task { await state.refresh() }
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
        }
    }

    private var groupHeader: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(group.name)
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
                        Text(group.now)
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
            .accessibilityLabel("\(group.name)，当前 \(group.now)")

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
            .disabled(!state.core.status.isHealthy || state.isTestingDelay)
            .help("测试该节点组延迟")
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
                    Text(node.name)
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
        .help(isSelected ? "当前节点" : "切换到 \(node.name)")
        .accessibilityLabel(node.name)
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
    @State private var level: LogLevelFilter = .all

    private var filteredLogs: [CoreLogEntry] {
        state.logs.filter { log in
            let matchesLevel = level == .all || log.normalizedLevel == level.rawValue
            let matchesSearch = searchText.isEmpty
                || log.message.localizedCaseInsensitiveContains(searchText)
                || log.level.localizedCaseInsensitiveContains(searchText)
            return matchesLevel && matchesSearch
        }
    }

    var body: some View {
        PageScaffold(title: "日志") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Picker("级别", selection: $level) {
                        ForEach(LogLevelFilter.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)

                    TextField("搜索日志", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        if state.isStreamingLogs {
                            state.stopLogStream()
                        } else {
                            state.startLogStream(level: level)
                        }
                    } label: {
                        Label(state.isStreamingLogs ? "暂停" : "跟随", systemImage: state.isStreamingLogs ? "pause.circle" : "dot.radiowaves.left.and.right")
                    }
                    .disabled(!state.core.status.isHealthy)

                    Button("清空") {
                        state.clearLogs()
                    }
                    .disabled(state.logs.isEmpty)

                    Button("刷新") {
                        state.loadLogs()
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
                            state.loadLogs()
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
            state.loadLogs()
        }
        .onChange(of: level) { _, newLevel in
            if state.isStreamingLogs {
                state.startLogStream(level: newLevel)
            }
        }
    }

    private func writeToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

private struct CoreLogRow: View {
    let log: CoreLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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

    private var filteredRules: [RuleItem] {
        guard !searchText.isEmpty else { return state.rules }
        return state.rules.filter {
            $0.type.localizedCaseInsensitiveContains(searchText)
                || $0.payload.localizedCaseInsensitiveContains(searchText)
                || $0.proxy.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        PageScaffold(title: "规则") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Picker("模式", selection: Binding {
                        state.forwardingMode
                    } set: { mode in
                        state.setForwardingMode(mode)
                    }) {
                        ForEach(MihomoMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)

                    TextField("搜索规则", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        Task { await state.refresh() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }

                if filteredRules.isEmpty {
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? "暂无规则" : "没有匹配规则", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text(searchText.isEmpty ? (state.core.status.isHealthy ? "controller 暂未返回规则。" : "启动内核后可读取运行时规则。") : "换一个关键词试试。")
                    } actions: {
                        Button("刷新") {
                            Task { await state.refresh() }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)

                    YAMLRulesSummaryCard()
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredRules) { rule in
                            RuleRow(rule: rule)
                        }
                    }
                }
            }
        }
    }
}

private struct RuleRow: View {
    @EnvironmentObject private var state: AppState
    let rule: RuleItem

    private var hitRateText: String {
        guard let rate = rule.hitRate else { return "-" }
        return "\(Int((rate * 100).rounded()))%"
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
                Text(rule.payload.isEmpty ? "MATCH" : rule.payload)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ClashMeowPalette.ink)
                    .lineLimit(1)
                Text("命中 \(rule.hitCount) · 未命中 \(rule.missCount) · size \(rule.size)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ClashMeowPalette.muted)
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
        .contextMenu {
            Button("复制规则") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString("\(rule.type),\(rule.payload),\(rule.proxy)", forType: .string)
            }
        }
    }
}

private struct YAMLRulesSummaryCard: View {
    @EnvironmentObject private var state: AppState

    private var summary: (ruleCount: Int, proxyCount: Int) {
        guard let yaml = try? String(contentsOf: state.core.configFile, encoding: .utf8) else {
            return (0, 0)
        }
        let lines = yaml.split(whereSeparator: \.isNewline).map(String.init)
        return (
            lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") && $0.contains(",") }.count,
            lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("name:") }.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前配置摘要")
                .font(.system(size: 16, weight: .bold))
            HStack(spacing: 8) {
                ProfileChip(text: "mode \(state.modeText)")
                ProfileChip(text: "log \(state.logLevelText)")
                ProfileChip(text: "\(summary.ruleCount) 条规则")
                ProfileChip(text: "\(summary.proxyCount) 个节点")
            }
        }
        .padding(16)
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
                        stateText: state.isTunEnabled ? "已开启" : "已关闭",
                        stateColor: state.isTunEnabled ? ClashMeowPalette.purple : ClashMeowPalette.orange,
                        isOn: state.isTunEnabled,
                        actionImage: nil
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
                        stateText: state.systemProxyEnabled ? "已设置" : (proxyToggle?.isOn == true ? "待应用" : "未设置"),
                        stateColor: (state.systemProxyEnabled || proxyToggle?.isOn == true) ? ClashMeowPalette.purple : ClashMeowPalette.orange,
                        isOn: proxyToggle?.isOn == true,
                        actionImage: "ellipsis",
                        onToggle: { isOn in
                            if let proxyToggle {
                                state.setToggle(proxyToggle, isOn: isOn)
                            }
                        }
                    )

                    FeatureCard(
                        title: "增强模式",
                        subtitle: "未遵循系统代理的应用可经由 TUN 或规则引擎接管，保持所有流量由 \(AppInfo.displayName) 路由。",
                        stateText: state.isTunEnabled ? "已启用" : "已禁用",
                        stateColor: state.isTunEnabled ? ClashMeowPalette.purple : ClashMeowPalette.orange,
                        isOn: state.isTunEnabled,
                        actionImage: nil,
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
    @State private var profileDisplayOrder: [String] = []
    @FocusState private var urlFieldFocused: Bool

    var body: some View {
        PageScaffold(title: "配置文件") {
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
        Toggle("通过本机网络", isOn: $usesProxyForImport)
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

        self.id = url.path
        self.name = url.lastPathComponent
        self.path = url.path
        self.fileSizeText = formatByteCount(fileSize?.intValue ?? 0)
        self.lineCount = lines.count
        self.modifiedAt = modifiedAt
        self.modeText = MihomoMode(configValue: config?.mode ?? Self.scalarValue("mode", in: yaml)).displayValue
        self.mixedPortText = "\(config?.mixedPort ?? Int(Self.scalarValue("mixed-port", in: yaml) ?? "") ?? 7890)"
        let allowLan = config?.allowLan ?? Self.boolValue("allow-lan", in: yaml)
        let tunEnabled = config?.tun?.enable ?? Self.nestedBoolValue(section: "tun", key: "enable", in: yaml)
        self.allowLanText = allowLan == true ? "局域网已开启" : "局域网已关闭"
        self.tunText = tunEnabled == true ? "TUN 已开启" : "TUN 已关闭"
        self.proxyGroupCount = proxyGroupCount
    }

    var detailText: String {
        "\(fileSizeText) · \(lineCount) 行 · 本机端口 \(mixedPortText)"
    }

    private static func scalarValue(_ key: String, in yaml: String) -> String? {
        yaml.split(whereSeparator: \.isNewline)
            .lazy
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("\(key):") }?
            .split(separator: ":", maxSplits: 1)
            .last
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'"))) }
    }

    private static func boolValue(_ key: String, in yaml: String) -> Bool? {
        guard let value = scalarValue(key, in: yaml)?.lowercased() else { return nil }
        if ["true", "yes", "on"].contains(value) { return true }
        if ["false", "no", "off"].contains(value) { return false }
        return nil
    }

    private static func nestedBoolValue(section: String, key: String, in yaml: String) -> Bool? {
        var isInsideSection = false
        for rawLine in yaml.split(whereSeparator: \.isNewline).map(String.init) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(section):") {
                isInsideSection = true
                continue
            }
            if isInsideSection, !rawLine.hasPrefix(" "), !rawLine.hasPrefix("\t") {
                return nil
            }
            if isInsideSection, trimmed.hasPrefix("\(key):") {
                return boolValue(key, in: trimmed)
            }
        }
        return nil
    }
}

private struct ProfilesListRow: View {
    let profile: ClashMeowProfileSummary
    let summary: YAMLProfileSummary?
    let isRefreshing: Bool
    let use: () -> Void
    let refresh: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ProfileKindBadge(
                    text: profile.kind == .remote ? "SUB" : "YAML",
                    isSelected: profile.isCurrent
                )

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(profile.name)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(profile.isCurrent ? ClashMeowPalette.purple : ClashMeowPalette.ink)
                                Image(systemName: profile.kind == .remote ? "arrow.triangle.2.circlepath" : "doc.plaintext")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ClashMeowPalette.muted)
                            }
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

                        Spacer(minLength: 8)

                        if let modifiedAt = profile.updatedAt ?? summary?.modifiedAt {
                            Text(modifiedAt, style: .relative)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ClashMeowPalette.muted)
                        }

                        if profile.kind == .remote {
                            Button(action: refresh) {
                                if isRefreshing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(isRefreshing)
                            .help("刷新远程配置")
                        }

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
                                Button("刷新远程配置") {
                                    refresh()
                                }
                            }
                            if !profile.isCurrent {
                                Button("使用配置") {
                                    use()
                                }
                            }
                            Divider()
                            Button("删除配置", role: .destructive) {
                                delete()
                            }
                            .disabled(profile.id == "default")
                        } label: {
                            Label("更多", systemImage: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    if let summary {
                        HStack(spacing: 8) {
                            ProfileChip(text: "mode \(summary.modeText)")
                            ProfileChip(text: summary.allowLanText)
                            ProfileChip(text: summary.tunText)
                            if profile.isCurrent {
                                ProfileChip(text: "\(summary.proxyGroupCount) 组节点")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 16)
            .padding(.leading, 16)

            ProfileSelectionIndicator(isSelected: profile.isCurrent)
        }
        .surfaceCard()
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            if !profile.isCurrent {
                use()
            }
        }
        .help(profile.isCurrent ? "当前配置" : "点击切换到此配置")
    }
}

private struct ProfileKindBadge: View {
    let text: String
    let isSelected: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(isSelected ? ClashMeowPalette.purple : ClashMeowPalette.muted)
            .frame(width: 34, height: 26)
            .background(
                (isSelected ? ClashMeowPalette.purple : ClashMeowPalette.muted).opacity(0.09),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}

private struct ProfileSelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? ClashMeowPalette.purple : ClashMeowPalette.faintLine)
                .frame(width: 7, height: 7)
        }
        .frame(width: 44)
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.trailing, 4)
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
            Toggle("", isOn: Binding(
                get: { state.core.status.isHealthy },
                set: { isOn in
                    isOn ? state.connect() : state.disconnect()
                }
            ))
            .toggleStyle(.switch)
            .tint(ClashMeowPalette.purple)
            .labelsHidden()
            .disabled(state.core.status == .starting)
            .help(state.core.status.isHealthy ? "停止内核" : "启动内核")

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
                                    Text(item.node.name)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text("互联网延迟")
                    .font(.system(size: 14, weight: .bold))
                TodoBadge()
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("诊断") { Task { await state.refresh() } }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .padding(.horizontal, 12)
                    .background(Color(hex: 0xF5F7FA), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(state.core.status.isHealthy ? state.activitySelectedProxyDelayText.replacingOccurrences(of: " ms", with: "") : "--")
                    .font(.system(size: 28, weight: .bold))
                Text("ms")
                    .font(.system(size: 13, weight: .bold))
            }
            HStack(spacing: 0) {
                MiniMetric(title: "路由器", value: "TODO", showsTodo: true)
                Divider()
                MiniMetric(title: "DNS", value: "TODO", showsTodo: true)
                Divider()
                MiniMetric(title: "节点", value: state.activitySelectedProxyDelayText)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .surfaceCard()
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
