import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var coreEnabled = CoreAutoStartManager.isEnabled
    @State private var systemProxyEnabled = SystemProxyPreference.isEnabled
    @State private var tunEnabled = TunPreference.isEnabled
    @State private var logRetentionDays = LogPreference.retentionDays
    @State private var logMaxFileSizeMB = LogPreference.maxFileSizeMB
    @State private var appLoggingEnabled = LogPreference.isAppLoggingEnabled
    @State private var logDefaultSource = LogPreference.defaultSource
    @State private var logDefaultLevel = LogPreference.defaultLevel
    @State private var logAutoCleanupEnabled = LogPreference.isAutoCleanupEnabled
    @State private var destructiveLogActionsEnabled = LogPreference.allowsDestructiveFileActions
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

            Section {
                Stepper("日志保留 \(logRetentionDays) 天", value: logRetentionDaysBinding, in: 1...30)
                Stepper("单文件上限 \(logMaxFileSizeMB) MB", value: logMaxFileSizeBinding, in: 1...100)
                Toggle("记录应用日志", isOn: appLoggingBinding)
                Picker("默认来源", selection: logDefaultSourceBinding) {
                    ForEach(LogSourceFilter.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                Picker("默认级别", selection: logDefaultLevelBinding) {
                    Text("跟随配置").tag(LogLevelFilter.all)
                    Text("错误").tag(LogLevelFilter.error)
                    Text("警告").tag(LogLevelFilter.warning)
                    Text("信息").tag(LogLevelFilter.info)
                    Text("调试").tag(LogLevelFilter.debug)
                }
                Toggle("启动时清理过期日志", isOn: logAutoCleanupBinding)
                Toggle("显示清空日志文件入口", isOn: destructiveLogActionsBinding)
            } header: {
                Text("日志")
            } footer: {
                Text("日志保存在 ~/.config/clash-meow/runtime。重启后仍保留；超过保留天数或文件大小上限的旧内容会被清理。")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 820, minHeight: 620, idealHeight: 720)
        .onAppear {
            coreEnabled = CoreAutoStartManager.isEnabled
            systemProxyEnabled = SystemProxyPreference.isEnabled
            tunEnabled = TunPreference.isEnabled
            logRetentionDays = LogPreference.retentionDays
            logMaxFileSizeMB = LogPreference.maxFileSizeMB
            appLoggingEnabled = LogPreference.isAppLoggingEnabled
            logDefaultSource = LogPreference.defaultSource
            logDefaultLevel = LogPreference.defaultLevel
            logAutoCleanupEnabled = LogPreference.isAutoCleanupEnabled
            destructiveLogActionsEnabled = LogPreference.allowsDestructiveFileActions
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

    private var logRetentionDaysBinding: Binding<Int> {
        Binding {
            logRetentionDays
        } set: { value in
            logRetentionDays = value
            LogPreference.retentionDays = value
        }
    }

    private var logMaxFileSizeBinding: Binding<Int> {
        Binding {
            logMaxFileSizeMB
        } set: { value in
            logMaxFileSizeMB = value
            LogPreference.maxFileSizeMB = value
        }
    }

    private var appLoggingBinding: Binding<Bool> {
        Binding {
            appLoggingEnabled
        } set: { value in
            appLoggingEnabled = value
            LogPreference.isAppLoggingEnabled = value
        }
    }

    private var logDefaultSourceBinding: Binding<LogSourceFilter> {
        Binding {
            logDefaultSource
        } set: { value in
            logDefaultSource = value
            LogPreference.defaultSource = value
        }
    }

    private var logDefaultLevelBinding: Binding<LogLevelFilter> {
        Binding {
            logDefaultLevel
        } set: { value in
            logDefaultLevel = value
            LogPreference.defaultLevel = value
        }
    }

    private var logAutoCleanupBinding: Binding<Bool> {
        Binding {
            logAutoCleanupEnabled
        } set: { value in
            logAutoCleanupEnabled = value
            LogPreference.isAutoCleanupEnabled = value
        }
    }

    private var destructiveLogActionsBinding: Binding<Bool> {
        Binding {
            destructiveLogActionsEnabled
        } set: { value in
            destructiveLogActionsEnabled = value
            LogPreference.allowsDestructiveFileActions = value
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
