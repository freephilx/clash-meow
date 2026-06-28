import Darwin
import Foundation

@MainActor
final class MihomoCoreManager: ObservableObject {
    private static let appConfigDirectoryName = ".config/clash-meow"

    @Published private(set) var status: CoreStatus = .stopped
    @Published private(set) var launchPath: String?
    @Published private(set) var lastLogLine = ""

    private var process: Process?
    private var pendingRestartWorkItem: DispatchWorkItem?
    private var logFileHandle: FileHandle?

    let configDirectory: URL
    let configFile: URL
    let logsDirectory: URL
    let coreLogFile: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.configDirectory = home.appending(path: Self.appConfigDirectoryName, directoryHint: .isDirectory)
        self.configFile = configDirectory.appending(path: "config.yaml")
        self.logsDirectory = configDirectory.appending(path: "logs", directoryHint: .isDirectory)
        self.coreLogFile = logsDirectory.appending(path: "core.log")
    }

    func prepare() {
        do {
            try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: configFile.path) {
                let sample = AppResources.url(forResource: "sampleConfig", withExtension: "yaml")
                if let sample {
                    try FileManager.default.copyItem(at: sample, to: configFile)
                }
            }
            launchPath = resolveLaunchPath()
            if launchPath == nil {
                status = .missingBinary
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func start() {
        prepare()
        guard process == nil else { return }
        guard let launchPath else {
            status = .missingBinary
            return
        }

        status = .starting

        releaseConfiguredPortsUsingAdministratorPrivileges()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = ["-d", configDirectory.path, "-f", configFile.path]
        task.currentDirectoryURL = configDirectory
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
            return
        }

        task.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.closeLogFileHandle()
                self?.process = nil
                if process.terminationStatus == 0 {
                    self?.status = .stopped
                } else {
                    self?.status = .failed("内核异常退出，代码 \(process.terminationStatus)")
                }
            }
        }

        do {
            try task.run()
            process = task
            status = .running
        } catch {
            closeLogFileHandle()
            status = .failed(error.localizedDescription)
        }
    }

    func releaseListeningPorts() {
        releaseConfiguredPortsUsingAdministratorPrivileges()
    }

    func releaseListeningPorts(for configFile: URL) {
        releaseConfiguredPortsUsingAdministratorPrivileges(configFile: configFile)
    }

    func stop() {
        pendingRestartWorkItem?.cancel()
        pendingRestartWorkItem = nil

        guard let process else {
            closeLogFileHandle()
            status = .stopped
            return
        }

        closeLogFileHandle()

        if process.isRunning {
            process.terminate()
            waitForProcessExit(process, timeout: 2)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        self.process = nil
        status = .stopped
    }

    private func openLogFileHandle() throws -> FileHandle {
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: coreLogFile.path) {
            FileManager.default.createFile(atPath: coreLogFile.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: coreLogFile)
        try handle.seekToEnd()
        return handle
    }

    private func appendSessionHeader(launchPath: String, handle: FileHandle) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
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
        stop()
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

    private func releaseConfiguredPortsUsingAdministratorPrivileges(configFile: URL? = nil) {
        let targetConfigFile = configFile ?? self.configFile
        debugPortRelease("读取 YAML 准备释放端口: \(targetConfigFile.path)")
        guard let yaml = try? String(contentsOf: targetConfigFile, encoding: .utf8) else {
            debugPortRelease("读取 YAML 失败，跳过端口释放: \(targetConfigFile.path)")
            return
        }
        let ports = MihomoConfig.listeningPorts(from: yaml)
        let portList = ports.sorted().map(String.init).joined(separator: ", ")
        debugPortRelease("YAML 解析到监听端口: \(portList)")
        PortOccupancyReleaser.releaseUsingAdministratorPrivileges(ports: ports)
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

    func applyDemoPresentation() {
        status = .running
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
