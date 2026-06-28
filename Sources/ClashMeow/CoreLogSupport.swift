import Foundation

enum CoreLogSupport {
    static func inferredLevel(in message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("error") { return "error" }
        if lowercased.contains("warn") { return "warning" }
        if lowercased.contains("debug") { return "debug" }
        return "info"
    }

    static func normalizedLevel(_ level: String) -> String {
        switch level.lowercased() {
        case "err", "error":
            return "error"
        case "warn", "warning":
            return "warning"
        case "debug":
            return "debug"
        default:
            return "info"
        }
    }

    static func recentLogs(from fileURL: URL, limit: Int = 500) -> [CoreLogEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(limit)
            .enumerated()
            .map { index, line in
                let message = String(line)
                return CoreLogEntry(
                    id: "\(index)-\(message.hashValue)",
                    level: inferredLevel(in: message),
                    message: message
                )
            }
    }
}

extension CoreLogEntry {
    var normalizedLevel: String {
        CoreLogSupport.normalizedLevel(level)
    }
}
