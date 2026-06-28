import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var autoStartCore = CoreAutoStartManager.isEnabled
    @State private var systemProxyEnabled = SystemProxyPreference.isEnabled
    @State private var tunEnabled = TunPreference.isEnabled
    @State private var launchAtLoginErrorMessage: String?
    #if DEBUG
    @State private var debugMockOverviewEnabled = DebugMockOverviewPreference.isEnabled
    #endif

    var body: some View {
        Form {
            Section {
                Toggle("打开应用时自动启动内核", isOn: autoStartCoreBinding)
            } header: {
                Text("内核")
            } footer: {
                Text("开启后，每次打开 \(AppInfo.displayName) 会自动启动网络内核。也可在概览页开关控制。")
            }

            Section {
                Toggle("系统代理", isOn: systemProxyBinding)
                Toggle("TUN 模式", isOn: tunBinding)
            } header: {
                Text("网络")
            } footer: {
                Text("偏好会在重启应用后保留。系统代理需要内核已启动；TUN 修改配置后需重启内核。")
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

            #if DEBUG
            Section {
                Toggle("Mock 概览 YAML", isOn: debugMockOverviewBinding)
            } header: {
                Text("Debug")
            } footer: {
                Text("开启后会添加并切换到一个本地 Mock YAML，用于展示概览页数据。")
            }
            #endif
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
        .onAppear {
            autoStartCore = CoreAutoStartManager.isEnabled
            systemProxyEnabled = SystemProxyPreference.isEnabled
            tunEnabled = TunPreference.isEnabled
            #if DEBUG
            debugMockOverviewEnabled = DebugMockOverviewPreference.isEnabled
            #endif
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

    private var autoStartCoreBinding: Binding<Bool> {
        Binding {
            autoStartCore
        } set: { value in
            autoStartCore = value
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

    #if DEBUG
    private var debugMockOverviewBinding: Binding<Bool> {
        Binding {
            debugMockOverviewEnabled
        } set: { value in
            debugMockOverviewEnabled = value
            state.setDebugMockOverviewYAMLProfileEnabled(value)
        }
    }
    #endif
}
