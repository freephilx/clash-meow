import AppKit
import Darwin
import Foundation

enum PortOccupancyReleaser {
    static func release(ports: Set<Int>, excludingPID: pid_t? = nil) {
        let validPorts = ports.filter { (1...65535).contains($0) }
        guard !validPorts.isEmpty else { return }

        debugLog("准备释放端口: \(portListDescription(validPorts))")
        var needsPrivilegedRelease = Set<Int>()
        for port in validPorts.sorted() {
            let pids = listeningPIDs(on: port, excluding: excludingPID)
            guard !pids.isEmpty else {
                debugLog("端口 \(port) 未被占用")
                continue
            }

            debugLog("端口 \(port) 被占用，PIDs=\(pidListDescription(pids))，尝试普通权限终止")
            terminate(pids: pids)
            usleep(150_000)

            let remainingPIDs = listeningPIDs(on: port, excluding: excludingPID)
            if !remainingPIDs.isEmpty {
                debugLog("端口 \(port) 普通权限释放失败，剩余 PIDs=\(pidListDescription(remainingPIDs))")
                needsPrivilegedRelease.insert(port)
            } else {
                debugLog("端口 \(port) 普通权限释放成功")
            }
        }

        guard !needsPrivilegedRelease.isEmpty else { return }
        releaseWithAdministratorPrivileges(ports: validPorts, excludingPID: excludingPID)
    }

    static func releaseUsingAdministratorPrivileges(ports: Set<Int>, excludingPID: pid_t? = nil) {
        let validPorts = ports.filter { (1...65535).contains($0) }
        guard !validPorts.isEmpty else { return }
        debugLog("准备使用管理员权限释放端口: \(portListDescription(validPorts))")
        for port in validPorts.sorted() {
            let pids = listeningPIDs(on: port, excluding: excludingPID)
            if pids.isEmpty {
                debugLog("端口 \(port) 未被占用")
            } else {
                debugLog("端口 \(port) 被占用，PIDs=\(pidListDescription(pids))，将请求特权助手 kill")
            }
        }
        if releaseWithPrivilegedHelper(ports: validPorts, excludingPID: excludingPID) {
            debugLog("特权助手释放端口完成")
        } else if PrivilegedHelperManager.shared.canInstallBundledHelper {
            debugLog("特权助手释放失败，跳过 AppleScript 回退，避免重复管理员密码弹窗")
        } else {
            debugLog("特权助手不可用，回退到 AppleScript 管理员授权")
            releaseWithAdministratorPrivileges(ports: validPorts, excludingPID: excludingPID)
        }
        usleep(150_000)
        for port in validPorts.sorted() {
            let pids = listeningPIDs(on: port, excluding: excludingPID)
            if pids.isEmpty {
                debugLog("端口 \(port) 管理员权限释放后未占用")
            } else {
                debugLog("端口 \(port) 管理员权限释放后仍被占用，PIDs=\(pidListDescription(pids))")
            }
        }
    }

    private static func releaseWithPrivilegedHelper(ports: Set<Int>, excludingPID: pid_t?) -> Bool {
        do {
            let logs = try PrivilegedHelperManager.shared.releasePorts(ports, excludingPID: excludingPID)
            for line in logs {
                debugLog("helper \(line)")
            }
            return true
        } catch {
            debugLog("特权助手释放失败: \(error.localizedDescription)")
            return false
        }
    }

    private static func listeningPIDs(on port: Int, excluding: pid_t?) -> [pid_t] {
        var pids = Set<pid_t>()
        pids.formUnion(pidsFromLsof(arguments: ["-n", "-P", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]))
        pids.formUnion(pidsFromLsof(arguments: ["-n", "-P", "-iUDP:\(port)", "-t"]))
        if let excluding {
            pids.remove(excluding)
        }
        return pids.sorted()
    }

    private static func pidsFromLsof(arguments: [String]) -> [pid_t] {
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

    private static func terminate(pids: [pid_t]) {
        for pid in pids where isProcessAlive(pid) {
            kill(pid, SIGTERM)
        }
        usleep(100_000)
        for pid in pids where isProcessAlive(pid) {
            kill(pid, SIGKILL)
        }
    }

    private static func isProcessAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    private static func releaseWithAdministratorPrivileges(ports: Set<Int>, excludingPID: pid_t?) {
        let scriptURL: URL
        do {
            scriptURL = try writeReleaseScript(ports: ports, excludingPID: excludingPID)
        } catch {
            debugLog("写入管理员释放脚本失败: \(error.localizedDescription)")
            return
        }
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let escapedPath = scriptURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"/bin/bash \\\"\(escapedPath)\\\"\" with administrator privileges"

        var errorInfo: NSDictionary?
        let output = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo).stringValue ?? ""
        if let errorInfo {
            debugLog("管理员释放脚本执行失败: \(errorInfo)")
        }
        for line in output.split(whereSeparator: \.isNewline) {
            debugLog(String(line))
        }
    }

    private static func writeReleaseScript(ports: Set<Int>, excludingPID: pid_t?) throws -> URL {
        let excludeClause: String
        if let excludingPID {
            excludeClause = "if [ \"$pid\" = \"\(excludingPID)\" ]; then continue; fi"
        } else {
            excludeClause = ""
        }

        let portList = ports.sorted().map(String.init).joined(separator: " ")
        let script = """
        #!/bin/bash
        for port in \(portList); do
          found=0
          for pid in $(/usr/sbin/lsof -n -P -iTCP:$port -sTCP:LISTEN -t 2>/dev/null); do
            found=1
            \(excludeClause)
            if kill -9 "$pid" 2>/dev/null; then
              echo "kill success tcp port=$port pid=$pid"
            else
              echo "kill failed tcp port=$port pid=$pid status=$?"
            fi
          done
          for pid in $(/usr/sbin/lsof -n -P -iUDP:$port -t 2>/dev/null); do
            found=1
            \(excludeClause)
            if kill -9 "$pid" 2>/dev/null; then
              echo "kill success udp port=$port pid=$pid"
            else
              echo "kill failed udp port=$port pid=$pid status=$?"
            fi
          done
          if [ "$found" = "0" ]; then
            echo "port free port=$port"
          fi
        done
        """

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clashmeow-port-release-\(UUID().uuidString).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private static func portListDescription(_ ports: Set<Int>) -> String {
        ports.sorted().map(String.init).joined(separator: ", ")
    }

    private static func pidListDescription(_ pids: [pid_t]) -> String {
        pids.map(String.init).joined(separator: ", ")
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[PortRelease] \(message)")
        #endif
    }
}
