import Foundation

enum ModeSwitchSelfTest {
    static let launchFlag = "-modeSwitchSelfTest"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchFlag)
    }

    @MainActor
    static func run(state: AppState) async -> Bool {
        AppDebugLog.resetModeMessagesForTesting()
        AppDebugLog.mode("出口模式自检开始")

        if !state.core.status.isHealthy {
            AppDebugLog.mode("内核未运行，尝试启动…")
            state.connect(recordPreference: false)
            try? await Task.sleep(for: .milliseconds(1200))
        }

        guard state.core.status.isHealthy else {
            AppDebugLog.mode("自检失败：内核无法启动 (\(state.core.status.title))")
            return false
        }

        await state.refresh()
        let initialMode = MihomoMode(configValue: state.config?.mode)
        AppDebugLog.mode("controller 初始模式=\(initialMode.mihomoValue)")

        let targets: [MihomoMode] = [.global, .direct, .rule]
        for target in targets {
            AppDebugLog.mode("自检切换目标 -> \(target.mihomoValue)")
            state.setForwardingMode(target)
            guard await waitForModeApply(target, state: state) else {
                AppDebugLog.mode("自检失败：未能切换到 \(target.mihomoValue)")
                dumpRecentLogs()
                return false
            }
            guard await verifyControllerMode(target) else {
                AppDebugLog.mode("自检失败：controller 模式与期望 \(target.mihomoValue) 不一致")
                dumpRecentLogs()
                return false
            }
            AppDebugLog.mode("自检通过：\(target.mihomoValue)")
        }

        AppDebugLog.mode("出口模式自检全部通过")
        dumpRecentLogs()
        return true
    }

    @MainActor
    private static func waitForModeApply(_ mode: MihomoMode, state: AppState) async -> Bool {
        for _ in 0..<50 {
            if AppDebugLog.recentModeMessages.contains(where: { $0.contains("出口模式切换成功") && $0.contains(mode.mihomoValue) }) {
                return AppState.verifyAppliedForwardingMode(expected: mode, configMode: state.config?.mode)
            }
            if AppDebugLog.recentModeMessages.contains(where: {
                $0.contains("出口模式切换失败") || $0.contains("出口模式切换校验失败")
            }) {
                return false
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return AppState.verifyAppliedForwardingMode(expected: mode, configMode: state.config?.mode)
    }

    @MainActor
    private static func verifyControllerMode(_ mode: MihomoMode) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:9090/configs") else { return false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let remoteMode = object["mode"] as? String else {
                return false
            }
            let matches = MihomoMode(configValue: remoteMode) == mode
            AppDebugLog.mode("controller HTTP 校验 mode=\(remoteMode) 期望=\(mode.mihomoValue) 结果=\(matches ? "OK" : "FAIL")")
            return matches
        } catch {
            AppDebugLog.mode("controller HTTP 校验失败：\(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    private static func dumpRecentLogs() {
        #if DEBUG
        for line in AppDebugLog.recentModeMessages {
            print("[ModeSelfTest] \(line)")
        }
        #endif
    }
}
