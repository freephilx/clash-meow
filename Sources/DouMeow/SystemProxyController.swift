import Foundation

struct SystemProxyConfiguration: Equatable {
    var networkService: String
    var host: String
    var port: Int

    init(networkService: String = "Wi-Fi", host: String = "127.0.0.1", port: Int = 7890) {
        self.networkService = networkService
        self.host = host
        self.port = port
    }
}

enum SystemProxyError: LocalizedError {
    case commandFailed(String)
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        case .invalidPort:
            return "本机端口无效，无法设置系统代理。"
        }
    }
}

struct SystemProxyController {
    func availableNetworkServices() throws -> [String] {
        let output = try runCapture(executable: "/usr/sbin/networksetup", arguments: ["-listallnetworkservices"])
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") }
            .map { service in
                var normalized = service
                if normalized.hasPrefix("*") {
                    normalized.removeFirst()
                }
                return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }

    func activeNetworkService() throws -> String {
        let routeOutput = try runCapture(executable: "/sbin/route", arguments: ["-n", "get", "default"])
        guard let interface = routeOutput
            .split(separator: "\n")
            .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.hasPrefix("interface:") })?
            .split(separator: " ")
            .last
            .map(String.init) else {
            throw SystemProxyError.commandFailed("无法确定当前网络接口。")
        }

        let orderOutput = try runCapture(
            executable: "/usr/sbin/networksetup",
            arguments: ["-listnetworkserviceorder"]
        )
        return try Self.networkService(in: orderOutput, matchingDevice: interface)
    }

    static func networkService(in serviceOrderOutput: String, matchingDevice device: String) throws -> String {
        let blocks = serviceOrderOutput.components(separatedBy: "\n\n")
        guard let block = blocks.first(where: { $0.contains("Device: \(device)") }) else {
            throw SystemProxyError.commandFailed("找不到接口 \(device) 对应的网络服务。")
        }

        for line in block.split(separator: "\n") {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("("), let closeIndex = trimmed.firstIndex(of: ")") else {
                continue
            }
            return String(trimmed[trimmed.index(after: closeIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw SystemProxyError.commandFailed("无法解析接口 \(device) 的网络服务。")
    }

    func setEnabled(_ isEnabled: Bool, configuration: SystemProxyConfiguration) throws {
        guard (1...65535).contains(configuration.port) else {
            throw SystemProxyError.invalidPort
        }

        if isEnabled {
            let commands: [[String]] = [
                ["-setwebproxy", configuration.networkService, configuration.host, "\(configuration.port)"],
                ["-setsecurewebproxy", configuration.networkService, configuration.host, "\(configuration.port)"],
                ["-setsocksfirewallproxy", configuration.networkService, configuration.host, "\(configuration.port)"],
                ["-setwebproxystate", configuration.networkService, "on"],
                ["-setsecurewebproxystate", configuration.networkService, "on"],
                ["-setsocksfirewallproxystate", configuration.networkService, "on"]
            ]
            try commands.forEach { try run(executable: "/usr/sbin/networksetup", arguments: $0) }
        } else {
            let commands: [[String]] = [
                ["-setwebproxystate", configuration.networkService, "off"],
                ["-setsecurewebproxystate", configuration.networkService, "off"],
                ["-setsocksfirewallproxystate", configuration.networkService, "off"]
            ]
            try commands.forEach { try run(executable: "/usr/sbin/networksetup", arguments: $0) }
        }
    }

    func resolvedConfiguration(port: Int, networkService: String? = nil) throws -> SystemProxyConfiguration {
        let service: String
        if let networkService, !networkService.isEmpty {
            service = networkService
        } else {
            service = try activeNetworkService()
        }
        return SystemProxyConfiguration(networkService: service, host: "127.0.0.1", port: port)
    }

    private func run(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemProxyError.commandFailed(message?.isEmpty == false ? message! : "networksetup 执行失败。")
        }
    }

    private func runCapture(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemProxyError.commandFailed(message?.isEmpty == false ? message! : "命令执行失败。")
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
