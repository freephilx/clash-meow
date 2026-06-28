import Darwin
import Foundation

final class HelperService: NSObject, HelperXPCProtocol, NSXPCListenerDelegate {
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

    func version(reply: @escaping (String) -> Void) {
        reply(PrivilegedHelperConstants.helperVersion)
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
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
}
