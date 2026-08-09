import AppKit
import SwiftUI

struct SettingsView: View {
    static let windowID = "preferences"

    @EnvironmentObject private var state: AppState
    @State private var selectedPane: SettingsPane = .general
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var coreEnabled = CoreAutoStartManager.isEnabled
    @State private var systemProxyEnabled = SystemProxyPreference.isEnabled
    @State private var tunEnabled = TunPreference.isEnabled
    @State private var internetLatencyTestURLs = InternetLatencyPreference.testURLsText
    @State private var internetLatencyDNSDomain = InternetLatencyPreference.dnsDomain
    @State private var internetLatencyTimeoutSeconds = InternetLatencyPreference.timeoutSeconds
    @State private var launchAtLoginErrorMessage: String?

    var body: some View {
        NavigationSplitView {
            preferencesSidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            preferenceDetail(for: selectedPane)
        }
        .frame(minWidth: 680, minHeight: 420, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .onAppear(perform: reloadPreferences)
    }

    private var preferencesSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsPalette.sidebarHeader)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)

                    ForEach(SettingsPane.allCases) { pane in
                        SettingsSidebarItem(
                            pane: pane,
                            isSelected: selectedPane == pane
                        ) {
                            selectedPane = pane
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 18)
            }
        }
        .background(SettingsPalette.sidebar)
    }

    private func preferenceDetail(for pane: SettingsPane) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(pane.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 20)
                .padding(.horizontal, 24)

            Form {
                switch pane {
                case .general:
                    generalSection
                case .network:
                    networkSection
                case .diagnostics:
                    diagnosticsSection
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(pane.title)
        .background(.background)
    }

    private var generalSection: some View {
        Section {
            PreferenceControlRow(
                title: "内核总开关",
                description: "与概览右上角总开关一致；开启后，下次打开应用会恢复启动网络内核。"
            ) {
                Toggle("内核总开关", isOn: coreEnabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(SettingsPalette.accent)
            }

            PreferenceControlRow(
                title: "登录时打开",
                description: "登录 macOS 后自动打开 \(AppInfo.displayName)，默认关闭。"
            ) {
                Toggle("登录时打开", isOn: launchAtLoginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(SettingsPalette.accent)
            }

            if let launchAtLoginErrorMessage {
                Label(launchAtLoginErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var networkSection: some View {
        Section {
            PreferenceControlRow(
                title: "系统代理",
                description: "接管 macOS 系统代理，需要网络内核已经启动。"
            ) {
                Toggle("系统代理", isOn: systemProxyBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(SettingsPalette.accent)
            }

            PreferenceControlRow(
                title: "TUN 模式",
                description: "修改后优先热重载运行配置，失败时重启网络内核。"
            ) {
                Toggle("TUN 模式", isOn: tunBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(SettingsPalette.accent)
            }
        }
    }

    private var diagnosticsSection: some View {
        Section("互联网延迟诊断") {
            PreferenceControlRow(
                title: "公网测试 URL",
                description: "使用逗号或换行分隔多个地址，诊断时依次测试。"
            ) {
                TextField("公网测试 URL", text: internetLatencyTestURLsBinding, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...4)
                    .frame(width: 280)
                    .accessibilityLabel("公网测试 URL")
            }

            PreferenceControlRow(
                title: "DNS 测试域名",
                description: "用于测量 DNS 解析延迟；路由器延迟会自动使用默认网关。"
            ) {
                TextField("DNS 测试域名", text: internetLatencyDNSDomainBinding)
                    .labelsHidden()
                    .frame(width: 220)
                    .accessibilityLabel("DNS 测试域名")
            }

            PreferenceControlRow(
                title: "诊断超时",
                description: "控制每项互联网诊断等待响应的最长时间。"
            ) {
                Stepper(
                    value: internetLatencyTimeoutBinding,
                    in: 1...10
                ) {
                    Text("\(internetLatencyTimeoutSeconds) 秒")
                        .monospacedDigit()
                }
                .frame(width: 104)
            }
        }
    }

    private func reloadPreferences() {
        launchAtLogin = LaunchAtLoginManager.isEnabled
        coreEnabled = CoreAutoStartManager.isEnabled
        systemProxyEnabled = SystemProxyPreference.isEnabled
        tunEnabled = TunPreference.isEnabled
        internetLatencyTestURLs = InternetLatencyPreference.testURLsText
        internetLatencyDNSDomain = InternetLatencyPreference.dnsDomain
        internetLatencyTimeoutSeconds = InternetLatencyPreference.timeoutSeconds
    }

    private var systemProxyBinding: Binding<Bool> {
        Binding {
            systemProxyEnabled
        } set: { value in
            systemProxyEnabled = value
            state.setSystemProxyEnabled(value)
        }
    }

    private var tunBinding: Binding<Bool> {
        Binding {
            tunEnabled
        } set: { value in
            tunEnabled = value
            state.setTunEnabled(value)
        }
    }

    private var coreEnabledBinding: Binding<Bool> {
        Binding {
            coreEnabled
        } set: { value in
            coreEnabled = value
            CoreAutoStartManager.setEnabled(value)
            if value {
                if !state.core.status.isHealthy {
                    state.connect()
                }
            } else if state.core.status.isHealthy {
                state.disconnect()
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            launchAtLogin
        } set: { value in
            launchAtLogin = value
            do {
                try LaunchAtLoginManager.setEnabled(value)
                launchAtLoginErrorMessage = nil
            } catch {
                launchAtLogin = LaunchAtLoginManager.isEnabled
                launchAtLoginErrorMessage = "无法更新登录项：\(error.localizedDescription)"
            }
        }
    }

    private var internetLatencyTestURLsBinding: Binding<String> {
        Binding {
            internetLatencyTestURLs
        } set: { value in
            internetLatencyTestURLs = value
            InternetLatencyPreference.testURLsText = value
        }
    }

    private var internetLatencyDNSDomainBinding: Binding<String> {
        Binding {
            internetLatencyDNSDomain
        } set: { value in
            internetLatencyDNSDomain = value
            InternetLatencyPreference.dnsDomain = value
        }
    }

    private var internetLatencyTimeoutBinding: Binding<Int> {
        Binding {
            internetLatencyTimeoutSeconds
        } set: { value in
            internetLatencyTimeoutSeconds = value
            InternetLatencyPreference.timeoutSeconds = value
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case network
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .network: return "网络"
        case .diagnostics: return "诊断"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "控制网络内核、登录启动和常用行为。"
        case .network: return "管理系统代理和 TUN 网络接管方式。"
        case .diagnostics: return "配置互联网延迟检测目标和超时时间。"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .network: return "network"
        case .diagnostics: return "waveform.path.ecg"
        }
    }
}

private struct SettingsSidebarItem: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: pane.systemImage)
                    .font(.system(size: 16))
                    .frame(width: 20, height: 20)
                Text(pane.title)
                    .font(.system(size: 14))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? SettingsPalette.accent : SettingsPalette.ink)
            .padding(.horizontal, 8)
            .frame(height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                isSelected ? SettingsPalette.sidebarSelection : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(pane.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PreferenceControlRow<Control: View>: View {
    let title: String
    let description: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
                .controlSize(.regular)
        }
        .padding(.vertical, 2)
    }
}

private enum SettingsPalette {
    static let accent = Color.accentColor
    static let ink = Color.primary
    static let sidebar = dynamic(light: 0xF6F8FA, dark: 0x14171C)
    static let sidebarSelection = dynamic(light: 0xE9ECEF, dark: 0x2B2E36)
    static let sidebarHeader = dynamic(light: 0x8B99AC, dark: 0x8C96A8)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
