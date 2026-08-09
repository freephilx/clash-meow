import Combine
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

    static func recentLogs(
        from fileURL: URL,
        limit: Int = 500,
        source: LogSourceFilter = .core,
        sessionStartedAt: Date? = nil
    ) -> [CoreLogEntry] {
        let lines = readLastLines(from: fileURL, count: limit)
        let visibleLines: [String]
        if source == .core, let sessionStartedAt {
            visibleLines = lines.filter {
                isCurrentSessionCoreLine($0, startedAt: sessionStartedAt)
            }
        } else {
            visibleLines = lines
        }
        return visibleLines
            .enumerated()
            .map { index, line in
                logEntry(from: line, index: index, source: source)
            }
    }

    static func readLastLines(
        from fileURL: URL,
        count: Int,
        maximumBytes: UInt64 = 1 * 1_024 * 1_024
    ) -> [String] {
        guard count > 0,
              maximumBytes > 0,
              let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return []
        }
        defer { try? handle.close() }

        do {
            let chunkSize: UInt64 = 64 * 1_024
            let fileSize = try handle.seekToEnd()
            var remainingBytes = fileSize
            var bytesRead: UInt64 = 0
            var chunks: [Data] = []
            var newlineCount = 0

            while remainingBytes > 0, newlineCount <= count, bytesRead < maximumBytes {
                let bytesToRead = min(min(chunkSize, remainingBytes), maximumBytes - bytesRead)
                remainingBytes -= bytesToRead
                try handle.seek(toOffset: remainingBytes)
                guard let chunk = try handle.read(upToCount: Int(bytesToRead)), !chunk.isEmpty else {
                    break
                }
                chunks.append(chunk)
                bytesRead += UInt64(chunk.count)
                newlineCount += chunk.reduce(into: 0) { total, byte in
                    if byte == 0x0A { total += 1 }
                }
            }

            var tailData = Data()
            tailData.reserveCapacity(chunks.reduce(0) { $0 + $1.count })
            for chunk in chunks.reversed() {
                tailData.append(chunk)
            }

            var lines = String(decoding: tailData, as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: true)
            if remainingBytes > 0, !lines.isEmpty {
                lines.removeFirst()
            }
            return lines.suffix(count).map(String.init)
        } catch {
            return []
        }
    }

    private static func logEntry(from line: String, index: Int, source: LogSourceFilter) -> CoreLogEntry {
        if source == .app {
            let parsed = parseAppLogLine(line)
            return CoreLogEntry(
                id: "\(source.rawValue)-\(index)-\(line.hashValue)",
                level: parsed.level,
                message: parsed.message,
                rawText: line,
                time: parsed.time,
                source: source
            )
        }

        let time = parseCoreLogTime(line)
        return CoreLogEntry(
            id: "\(source.rawValue)-\(index)-\(line.hashValue)",
            level: parseCoreLogLevel(line) ?? inferredLevel(in: line),
            message: value(for: "msg", in: line) ?? line,
            rawText: line,
            time: time,
            source: source
        )
    }

    private static func parseCoreLogLevel(_ line: String) -> String? {
        let pattern = #"\blevel="?([A-Za-z]+)"?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 2,
              let levelRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return normalizedLevel(String(line[levelRange]))
    }

    private static func parseCoreLogTime(_ line: String) -> String? {
        let patterns = [
            #"^\[([^\]]+)\]\s+starting\b"#,
            #"\btime="?([^"\s]+)"?"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges == 2,
                  let timeRange = Range(match.range(at: 1), in: line) else {
                continue
            }
            return LogTimeSupport.displayString(from: String(line[timeRange]))
        }
        return nil
    }

    private static func isCurrentSessionCoreLine(_ line: String, startedAt: Date) -> Bool {
        guard line.hasPrefix("time=\""),
              let timestamp = value(for: "time", in: line),
              let date = LogTimeSupport.dateValue(from: timestamp) else {
            return false
        }
        return date >= startedAt
    }

    private static func value(for key: String, in line: String) -> String? {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: key) + #"=(\"(?:\\.|[^\"])*\"|\S+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 2,
              let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        let rawValue = String(line[valueRange])
        guard rawValue.hasPrefix("\""), rawValue.hasSuffix("\"") else {
            return rawValue
        }
        let quotedData = Data(rawValue.utf8)
        return (try? JSONDecoder().decode(String.self, from: quotedData)) ?? String(rawValue.dropFirst().dropLast())
    }

    private static func parseAppLogLine(_ line: String) -> (time: String?, level: String, message: String) {
        let pattern = #"^\[([^\]]+)\]\s+\[([^\]]+)\]\s+\[([^\]]+)\]\s+(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 5,
              let timeRange = Range(match.range(at: 1), in: line),
              let levelRange = Range(match.range(at: 2), in: line),
              let moduleRange = Range(match.range(at: 3), in: line),
              let messageRange = Range(match.range(at: 4), in: line) else {
            return (nil, inferredLevel(in: line), line)
        }
        let module = String(line[moduleRange])
        let message = String(line[messageRange])
        return (
            LogTimeSupport.displayString(from: String(line[timeRange])),
            normalizedLevel(String(line[levelRange])),
            "[\(module)] \(message)"
        )
    }

}

extension CoreLogEntry {
    var normalizedLevel: String {
        CoreLogSupport.normalizedLevel(level)
    }
}

@MainActor
final class MihomoLogStore: ObservableObject {
    @Published private(set) var entries: [CoreLogEntry] = []

    func replaceEntries(with entries: [CoreLogEntry]) {
        guard entries != self.entries else { return }
        self.entries = entries
    }

    func appendEntries(_ newEntries: [CoreLogEntry], limit: Int) {
        guard !newEntries.isEmpty else { return }
        var updatedEntries = entries
        updatedEntries.append(contentsOf: newEntries)
        if updatedEntries.count > limit {
            updatedEntries.removeFirst(updatedEntries.count - limit)
        }
        entries = updatedEntries
    }

}
