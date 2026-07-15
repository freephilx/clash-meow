import Darwin
import Foundation

@MainActor
final class MihomoCoreManager: ObservableObject {
    @Published private(set) var status: CoreStatus = .stopped
    @Published private(set) var launchPath: String?
    @Published private(set) var lastLogLine = ""

    private var process: Process?
    private var isUsingPrivilegedCore = false
    private var privilegedCorePID: pid_t?
    private var pendingRestartWorkItem: DispatchWorkItem?
    private var logFileHandle: FileHandle?

    let configDirectory: URL
    let configFile: URL
    let logsDirectory: URL
    let coreLogFile: URL
    let appLogFile: URL

    init() {
        self.configDirectory = AppPersistencePaths.configDirectory
        self.configFile = configDirectory.appending(path: "config.yaml")
        self.logsDirectory = configDirectory.appending(path: "logs", directoryHint: .isDirectory)
        self.coreLogFile = logsDirectory.appending(path: "core.log")
        self.appLogFile = logsDirectory.appending(path: "app.log")
    }

    func prepare() {
        do {
            try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            CoreLogSupport.cleanupOldLogs(in: logsDirectory)
            if !FileManager.default.fileExists(atPath: configFile.path) {
                let sample = AppResources.url(forResource: "sampleConfig", withExtension: "yaml")
                if let sample {
                    try FileManager.default.copyItem(at: sample, to: configFile)
                    AppLogSupport.info("已创建默认配置文件: \(configFile.path)", module: "Core", logsDirectory: logsDirectory)
                }
            }
            launchPath = resolveLaunchPath()
            if launchPath == nil {
                status = .missingBinary
                AppLogSupport.error("未找到 mihomo 可执行文件", module: "Core", logsDirectory: logsDirectory)
            }
        } catch {
            status = .failed(error.localizedDescription)
            AppLogSupport.error("准备内核目录失败: \(error.localizedDescription)", module: "Core", logsDirectory: logsDirectory)
        }
    }

    func start() {
        prepare()
        guard process == nil, !isUsingPrivilegedCore else { return }
        guard let launchPath else {
            status = .missingBinary
            return
        }

        status = .starting

        releaseConfiguredPortsUsingAdministratorPrivileges()

        if PrivilegedHelperManager.shared.canInstallBundledHelper {
            startUsingPrivilegedHelper(launchPath: launchPath)
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = ["-d", configDirectory.path, "-f", configFile.path]
        task.currentDirectoryURL = configDirectory
        AppLogSupport.info("准备启动 mihomo: \(launchPath)", module: "Core", logsDirectory: logsDirectory)
        debugPortRelease("mihomo 启动命令: \(shellCommand(executable: launchPath, arguments: task.arguments ?? []))")
        debugPortRelease("mihomo 工作目录: \(configDirectory.path)")

        do {
            let logHandle = try openLogFileHandle()
            logFileHandle = logHandle
            appendSessionHeader(
                launchPath: launchPath,
                handle: logHandle
            )
            task.standardOutput = logHandle
            task.standardError = logHandle
        } catch {
            status = .failed(error.localizedDescription)
            AppLogSupport.error("打开 core.log 失败: \(error.localizedDescription)", module: "Core", logsDirectory: logsDirectory)
            return
        }

        task.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self, self.process === process else { return }
                self.closeLogFileHandle()
                self.process = nil
                if process.terminationStatus == 0 {
                    self.status = .stopped
                    AppLogSupport.info("mihomo 已退出", module: "Core", logsDirectory: self.logsDirectory)
                } else {
                    self.status = .failed("内核异常退出，代码 \(process.terminationStatus)")
                    AppLogSupport.error("mihomo 异常退出，代码 \(process.terminationStatus)", module: "Core", logsDirectory: self.logsDirectory)
                }
            }
        }

        do {
            try task.run()
            process = task
            status = .running
            AppLogSupport.info("mihomo 已启动，PID=\(task.processIdentifier)", module: "Core", logsDirectory: logsDirectory)
        } catch {
            closeLogFileHandle()
            status = .failed(error.localizedDescription)
            AppLogSupport.error("mihomo 启动失败: \(error.localizedDescription)", module: "Core", logsDirectory: logsDirectory)
        }
    }

    func releaseListeningPorts() {
        releaseConfiguredPortsUsingAdministratorPrivileges(excludingCurrentProcess: true)
    }

    func releaseListeningPorts(for configFile: URL) {
        releaseConfiguredPortsUsingAdministratorPrivileges(configFile: configFile, excludingCurrentProcess: true)
    }

    func stop() {
        stop(markStopped: true)
    }

    private func stop(markStopped: Bool) {
        pendingRestartWorkItem?.cancel()
        pendingRestartWorkItem = nil

        if PrivilegedHelperManager.shared.canInstallBundledHelper {
            AppLogSupport.info("准备停止特权 mihomo，PID=\(privilegedCorePID.map(String.init) ?? "unknown")", module: "Core", logsDirectory: logsDirectory)
            do {
                try PrivilegedHelperManager.shared.stopCore()
            } catch {
                AppLogSupport.error("停止特权 mihomo 失败: \(error.localizedDescription)", module: "Core", logsDirectory: logsDirectory)
            }
            isUsingPrivilegedCore = false
            privilegedCorePID = nil
            if markStopped {
                status = .stopped
            }
            AppLogSupport.info("特权 mihomo 已停止", module: "Core", logsDirectory: logsDirectory)
            return
        }

        guard let process else {
            closeLogFileHandle()
            if markStopped {
                status = .stopped
            }
            AppLogSupport.info("停止内核：当前无运行进程", module: "Core", logsDirectory: logsDirectory)
            return
        }

        closeLogFileHandle()
        AppLogSupport.info("准备停止 mihomo，PID=\(process.processIdentifier)", module: "Core", logsDirectory: logsDirectory)

        if process.isRunning {
            process.terminate()
            waitForProcessExit(process, timeout: 2)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                AppLogSupport.warning("mihomo 未及时退出，已发送 SIGKILL", module: "Core", logsDirectory: logsDirectory)
            }
        }

        self.process = nil
        if markStopped {
            status = .stopped
        }
        AppLogSupport.info("mihomo 已停止", module: "Core", logsDirectory: logsDirectory)
    }

    private func openLogFileHandle() throws -> FileHandle {
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: coreLogFile.path) {
            FileManager.default.createFile(atPath: coreLogFile.path, contents: nil)
        }
        try CoreLogSupport.appendWithLimit("", to: coreLogFile)
        let handle = try FileHandle(forWritingTo: coreLogFile)
        try handle.seekToEnd()
        return handle
    }

    private func appendSessionHeader(launchPath: String, handle: FileHandle) {
        let timestamp = LogTimeSupport.string()
        let header = "[\(timestamp)] starting \(launchPath) -d \(configDirectory.path) -f \(configFile.path)\n"
        if let data = header.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }

    private func closeLogFileHandle() {
        try? logFileHandle?.close()
        logFileHandle = nil
    }

    private func waitForProcessExit(_ process: Process, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }

    func restart() {
        debugPortRelease("mihomo 准备重启，将重新执行启动命令")
        AppLogSupport.info("准备重启 mihomo", module: "Core", logsDirectory: logsDirectory)
        if PrivilegedHelperManager.shared.canInstallBundledHelper {
            restartUsingPrivilegedHelper()
            return
        }
        stop(markStopped: false)
        if launchPath != nil {
            status = .starting
        }
        let work = DispatchWorkItem { [weak self] in
            self?.start()
        }
        pendingRestartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func releaseConfiguredPorts() {
        guard let yaml = try? String(contentsOf: configFile, encoding: .utf8) else { return }
        let ports = MihomoConfig.listeningPorts(from: yaml)
        PortOccupancyReleaser.release(ports: ports)
    }

    private func releaseConfiguredPortsUsingAdministratorPrivileges(
        configFile: URL? = nil,
        excludingCurrentProcess: Bool = false
    ) {
        let targetConfigFile = configFile ?? self.configFile
        debugPortRelease("读取 YAML 准备释放端口: \(targetConfigFile.path)")
        guard let yaml = try? String(contentsOf: targetConfigFile, encoding: .utf8) else {
            debugPortRelease("读取 YAML 失败，跳过端口释放: \(targetConfigFile.path)")
            return
        }
        let ports = MihomoConfig.listeningPorts(from: yaml)
        let portList = ports.sorted().map(String.init).joined(separator: ", ")
        debugPortRelease("YAML 解析到监听端口: \(portList)")
        let excludingPID: pid_t? = if excludingCurrentProcess {
            process?.processIdentifier ?? privilegedCorePID
        } else {
            nil
        }
        PortOccupancyReleaser.releaseUsingAdministratorPrivileges(ports: ports, excludingPID: excludingPID)
    }

    private func debugPortRelease(_ message: String) {
        #if DEBUG
        print("[MihomoCore] \(message)")
        #endif
    }

    private func shellCommand(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(shellEscaped).joined(separator: " ")
    }

    private func shellEscaped(_ value: String) -> String {
        if value.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "'\"\\$`"))) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func startUsingPrivilegedHelper(launchPath: String) {
        AppLogSupport.info("准备以特权模式启动 mihomo: \(launchPath)", module: "Core", logsDirectory: logsDirectory)
        debugPortRelease("mihomo 特权启动命令: \(shellCommand(executable: launchPath, arguments: ["-d", configDirectory.path, "-f", configFile.path]))")
        do {
            let pid = try PrivilegedHelperManager.shared.startCore(
                executablePath: launchPath,
                configDirectory: configDirectory,
                configFile: configFile,
                logFile: coreLogFile
            )
            isUsingPrivilegedCore = true
            privilegedCorePID = pid
            status = .running
            AppLogSupport.info("mihomo 已以特权模式启动，PID=\(pid)", module: "Core", logsDirectory: logsDirectory)
        } catch {
            isUsingPrivilegedCore = false
            privilegedCorePID = nil
            status = .failed(error.localizedDescription)
            AppLogSupport.error("mihomo 特权启动失败: \(error.localizedDescription)", module: "Core", logsDirectory: logsDirectory)
        }
    }

    private func restartUsingPrivilegedHelper() {
        prepare()
        guard let launchPath else {
            status = .missingBinary
            return
        }
        status = .starting
        releaseConfiguredPortsUsingAdministratorPrivileges(excludingCurrentProcess: true)
        AppLogSupport.info("准备通过 helper 重启 mihomo server: \(launchPath)", module: "Core", logsDirectory: logsDirectory)
        debugPortRelease("mihomo 特权重启命令: \(shellCommand(executable: launchPath, arguments: ["-d", configDirectory.path, "-f", configFile.path]))")
        do {
            let pid = try PrivilegedHelperManager.shared.restartCore(
                executablePath: launchPath,
                configDirectory: configDirectory,
                configFile: configFile,
                logFile: coreLogFile
            )
            isUsingPrivilegedCore = true
            privilegedCorePID = pid
            status = .running
            AppLogSupport.info("mihomo server 已由 helper 重启，PID=\(pid)", module: "Core", logsDirectory: logsDirectory)
        } catch {
            isUsingPrivilegedCore = false
            privilegedCorePID = nil
            status = .failed(error.localizedDescription)
            AppLogSupport.error("mihomo server 特权重启失败: \(error.localizedDescription)", module: "Core", logsDirectory: logsDirectory)
        }
    }

    private func resolveLaunchPath() -> String? {
        let candidates = [
            Bundle.main.resourceURL?.appending(path: "mihomo").path,
            AppResources.url(forResource: "mihomo", withExtension: nil)?.path,
            "/opt/homebrew/bin/mihomo",
            "/usr/local/bin/mihomo",
            "/usr/bin/mihomo"
        ].compactMap { $0 }

        return candidates.first { path in
            FileManager.default.isExecutableFile(atPath: path)
        }
    }

    func applyDemoPresentation(isRunning: Bool = true) {
        status = isRunning ? .running : .stopped
        launchPath = "/usr/local/bin/mihomo"
    }

    #if DEBUG
    func clearDemoPresentation() {
        guard process == nil, launchPath == "/usr/local/bin/mihomo" else { return }
        status = .stopped
        prepare()
    }
    #endif
}
