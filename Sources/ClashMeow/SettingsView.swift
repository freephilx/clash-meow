import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var coreEnabled = CoreAutoStartManager.isEnabled
    @State private var systemProxyEnabled = SystemProxyPreference.isEnabled
    @State private var tunEnabled = TunPreference.isEnabled
    @State private var internetLatencyTestURLs = InternetLatencyPreference.testURLsText
    @State private var internetLatencyDNSDomain = InternetLatencyPreference.dnsDomain
    @State private var internetLatencyTimeoutSeconds = InternetLatencyPreference.timeoutSeconds
    @State private var launchAtLoginErrorMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("内核总开关", isOn: coreEnabledBinding)
            } header: {
                Text("内核")
            } footer: {
                Text("与概览右上角总开关一致。开启后，每次打开 \(AppInfo.displayName) 会恢复启动网络内核。")
            }

            Section {
                Toggle("系统代理", isOn: systemProxyBinding)
                Toggle("TUN 模式", isOn: tunBinding)
            } header: {
                Text("网络")
            } footer: {
                Text("偏好保存到 ~/.config/clash-meow/preferences.json。系统代理和 TUN 需要内核已启动；TUN 修改配置后会优先热重载，失败时重启内核。")
            }

            Section {
                TextField("公网测试 URL", text: internetLatencyTestURLsBinding, axis: .vertical)
                    .lineLimit(3...5)
                TextField("DNS 测试域名", text: internetLatencyDNSDomainBinding)
                Stepper(
                    "诊断超时 \(internetLatencyTimeoutSeconds) 秒",
                    value: internetLatencyTimeoutBinding,
                    in: 1...10
                )
            } header: {
                Text("互联网延迟诊断")
            } footer: {
                Text("公网测试 URL 可用逗号或换行分隔。路由器延迟会自动使用默认网关，不需要手动配置。")
            }

            Section {
                Toggle("登录时打开", isOn: launchAtLoginBinding)
                if let launchAtLoginErrorMessage {
                    Text(launchAtLoginErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("启动")
            } footer: {
                Text("开启后，登录 macOS 时会自动启动 \(AppInfo.displayName)。")
            }

        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 820, minHeight: 620, idealHeight: 720)
        .onAppear {
            coreEnabled = CoreAutoStartManager.isEnabled
            systemProxyEnabled = SystemProxyPreference.isEnabled
            tunEnabled = TunPreference.isEnabled
            internetLatencyTestURLs = InternetLatencyPreference.testURLsText
            internetLatencyDNSDomain = InternetLatencyPreference.dnsDomain
            internetLatencyTimeoutSeconds = InternetLatencyPreference.timeoutSeconds
        }
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
