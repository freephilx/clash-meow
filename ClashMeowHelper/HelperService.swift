import Darwin
import Foundation

private enum HelperServiceError: LocalizedError {
    case invalidCoreExecutable(String)
    case invalidConfigDirectory(String)
    case invalidConfigFile(String)
    case invalidLogFile(String)

    var errorDescription: String? {
        switch self {
        case let .invalidCoreExecutable(path):
            "helper rejected mihomo executable path: \(path)"
        case let .invalidConfigDirectory(path):
            "helper rejected config directory: \(path)"
        case let .invalidConfigFile(path):
            "helper rejected config file: \(path)"
        case let .invalidLogFile(path):
            "helper rejected log file: \(path)"
        }
    }
}

final class HelperService: NSObject, HelperXPCProtocol, NSXPCListenerDelegate {
    private var coreProcess: Process?
    private var coreLogFileHandle: FileHandle?

    func releasePorts(
        _ ports: [NSNumber],
        excludingPID: NSNumber,
        reply: @escaping ([String], NSError?) -> Void
    ) {
        let excluded = excludingPID.int32Value > 0 ? excludingPID.int32Value : nil
        var logs: [String] = []
        for portNumber in ports {
            let port = portNumber.intValue
            guard (1...65535).contains(port) else { continue }
            let tcpPIDs = pidsFromLsof(arguments: ["-n", "-P", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"])
            let udpPIDs = pidsFromLsof(arguments: ["-n", "-P", "-iUDP:\(port)", "-t"])
            let pids = Array(Set(tcpPIDs + udpPIDs).subtracting(excluded.map { [$0] } ?? [])).sorted()
            if pids.isEmpty {
                logs.append("port free port=\(port)")
                continue
            }
            let pidList = pids.map(String.init).joined(separator: ",")
            logs.append("port occupied port=\(port) pids=\(pidList)")
            for pid in pids {
                if kill(pid, SIGKILL) == 0 {
                    logs.append("kill success port=\(port) pid=\(pid)")
                } else {
                    logs.append("kill failed port=\(port) pid=\(pid) errno=\(errno)")
                }
            }
        }
        reply(logs, nil)
    }

    func startCore(
        executablePath: String,
        configDirectory: String,
        configFile: String,
        logFile: String,
        reply: @escaping (NSNumber, NSError?) -> Void
    ) {
        startCoreProcess(
            executablePath: executablePath,
            configDirectory: configDirectory,
            configFile: configFile,
            logFile: logFile,
            reply: reply
        )
    }

    func restartCore(
        executablePath: String,
        configDirectory: String,
        configFile: String,
        logFile: String,
        reply: @escaping (NSNumber, NSError?) -> Void
    ) {
        startCoreProcess(
            executablePath: executablePath,
            configDirectory: configDirectory,
            configFile: configFile,
            logFile: logFile,
            reply: reply
        )
    }

    func stopCore(reply: @escaping (NSError?) -> Void) {
        stopRunningCore()
        reply(nil)
    }

    func version(reply: @escaping (String) -> Void) {
        reply(PrivilegedHelperConstants.helperVersion)
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    private func startCoreProcess(
        executablePath: String,
        configDirectory: String,
        configFile: String,
        logFile: String,
        reply: @escaping (NSNumber, NSError?) -> Void
    ) {
        do {
            try validateCoreLaunchRequest(
                executablePath: executablePath,
                configDirectory: configDirectory,
                configFile: configFile,
                logFile: logFile
            )
        } catch {
            reply(NSNumber(value: -1), error as NSError)
            return
        }

        stopRunningCore()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["-d", configDirectory, "-f", configFile]
        process.currentDirectoryURL = URL(fileURLWithPath: configDirectory)

        do {
            let logURL = URL(fileURLWithPath: logFile)
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            appendSessionHeader(executablePath: executablePath, configDirectory: configDirectory, configFile: configFile, handle: handle)
            coreLogFileHandle = handle
            process.standardOutput = handle
            process.standardError = handle
        } catch {
            reply(NSNumber(value: -1), error as NSError)
            return
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            guard let self else { return }
            if self.coreProcess === terminatedProcess {
                self.closeCoreLogFileHandle()
                self.coreProcess = nil
            }
        }

        do {
            try process.run()
            coreProcess = process
            reply(NSNumber(value: process.processIdentifier), nil)
        } catch {
            closeCoreLogFileHandle()
            reply(NSNumber(value: -1), error as NSError)
        }
    }

    private func validateCoreLaunchRequest(
        executablePath: String,
        configDirectory: String,
        configFile: String,
        logFile: String
    ) throws {
        let executable = normalizedPath(executablePath)
        let configDirectory = normalizedPath(configDirectory)
        let configFile = normalizedPath(configFile)
        let logFile = normalizedPath(logFile)

        guard isAllowedCoreExecutable(executable) else {
            throw HelperServiceError.invalidCoreExecutable(executable)
        }

        guard configDirectory.hasSuffix("/.config/clash-meow/runtime/mihomo") else {
            throw HelperServiceError.invalidConfigDirectory(configDirectory)
        }

        let expectedConfigFile = normalizedPath(
            URL(fileURLWithPath: configDirectory).appendingPathComponent("config.yaml").path
        )
        guard configFile == expectedConfigFile else {
            throw HelperServiceError.invalidConfigFile(configFile)
        }

        let expectedLogFile = normalizedPath(
            URL(fileURLWithPath: configDirectory)
                .appendingPathComponent("core.log")
                .path
        )
        guard logFile == expectedLogFile else {
            throw HelperServiceError.invalidLogFile(logFile)
        }
    }

    private func isAllowedCoreExecutable(_ path: String) -> Bool {
        let suffixes = [
            "/Contents/Resources/Mihomo/arm64/bin/mihomo",
            "/Contents/Resources/Mihomo/x86_64/bin/mihomo"
        ]
        return suffixes.contains { path.hasSuffix($0) }
            && path.contains(".app/Contents/Resources/Mihomo/")
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func pidsFromLsof(arguments: [String]) -> [pid_t] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func stopRunningCore() {
        guard let process = coreProcess else {
            closeCoreLogFileHandle()
            return
        }

        if process.isRunning {
            process.terminate()
            waitForProcessExit(process, timeout: 2)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        coreProcess = nil
        closeCoreLogFileHandle()
    }

    private func waitForProcessExit(_ process: Process, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }

    private func appendSessionHeader(executablePath: String, configDirectory: String, configFile: String, handle: FileHandle) {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
        let header = "[\(timestamp)] privileged starting \(executablePath) -d \(configDirectory) -f \(configFile)\n"
        if let data = header.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }

    private func closeCoreLogFileHandle() {
        try? coreLogFileHandle?.close()
        coreLogFileHandle = nil
    }
}
