import Foundation

enum CoreLogSupport {
    private static let truncateMarker = "\n[LOG] File truncated because size limit reached.\n"
    private static let retainRatio = 0.5

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
        source: LogSourceFilter = .core
    ) -> [CoreLogEntry] {
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
                return logEntry(from: message, index: index, source: source)
            }
    }

    static func recentLogs(
        coreFile: URL,
        appFile: URL,
        source: LogSourceFilter,
        limit: Int = 500
    ) -> [CoreLogEntry] {
        switch source {
        case .core:
            return recentLogs(from: coreFile, limit: limit, source: .core)
        case .app:
            return recentLogs(from: appFile, limit: limit, source: .app)
        case .all:
            return (
                recentLogs(from: coreFile, limit: limit, source: .core)
                + recentLogs(from: appFile, limit: limit, source: .app)
            ).suffix(limit)
                .map { $0 }
        }
    }

    static func appendWithLimit(_ text: String, to fileURL: URL, maxBytes: Int = LogPreference.maxFileSizeBytes) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(text.utf8)
        guard maxBytes > 0 else {
            try append(data, to: fileURL)
            return
        }
        if data.count >= maxBytes {
            try data.suffix(maxBytes).write(to: fileURL)
            return
        }

        let existingSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0
        if existingSize + data.count <= maxBytes {
            try append(data, to: fileURL)
            return
        }

        let retainBudget = Int(Double(maxBytes) * retainRatio)
        let markerData = Data(truncateMarker.utf8)
        let keepBytes = max(0, retainBudget - data.count - markerData.count)
        let tail = tailData(from: fileURL, byteCount: keepBytes)
        var rewritten = tail + markerData + data
        if rewritten.count > maxBytes {
            rewritten = rewritten.suffix(maxBytes)
        }
        try rewritten.write(to: fileURL)
    }

    static func truncate(_ fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: fileURL)
    }

    static func cleanupOldLogs(in directory: URL, retentionDays: Int = LogPreference.retentionDays) {
        guard LogPreference.isAutoCleanupEnabled else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        let cutoff = Date().addingTimeInterval(-Double(max(retentionDays, 1)) * 24 * 60 * 60)
        let candidates = files.filter { url in
            let name = url.lastPathComponent
            guard name.hasSuffix(".log") else { return false }
            return name == "core.log" || name == "app.log" || name.hasPrefix("core-") || name.hasPrefix("app-")
        }

        for url in candidates {
            if let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date,
               modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func logEntry(from line: String, index: Int, source: LogSourceFilter) -> CoreLogEntry {
        if source == .app {
            let parsed = parseAppLogLine(line)
            return CoreLogEntry(
                id: "\(source.rawValue)-\(index)-\(line.hashValue)",
                level: parsed.level,
                message: parsed.message,
                time: parsed.time,
                source: source
            )
        }

        return CoreLogEntry(
            id: "\(source.rawValue)-\(index)-\(line.hashValue)",
            level: parseCoreLogLevel(line) ?? inferredLevel(in: line),
            message: line,
            time: parseCoreLogTime(line),
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

    private static func append(_ data: Data, to fileURL: URL) throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL)
        }
    }

    private static func tailData(from fileURL: URL, byteCount: Int) -> Data {
        guard byteCount > 0,
              let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return Data()
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(byteCount) ? size - UInt64(byteCount) : 0
        try? handle.seek(toOffset: offset)
        return (try? handle.readToEnd()) ?? Data()
    }
}

extension CoreLogEntry {
    var normalizedLevel: String {
        CoreLogSupport.normalizedLevel(level)
    }
}
