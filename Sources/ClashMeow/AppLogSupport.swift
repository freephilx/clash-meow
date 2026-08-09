import Foundation

extension Notification.Name {
    static let clashMeowApplicationLogDidAppend = Notification.Name("ClashMeowApplicationLogDidAppend")
}

enum LogTimeSupport {
    private static func makeFormatter(dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = dateFormat
        return formatter
    }

    static func string(from date: Date = Date()) -> String {
        makeFormatter(dateFormat: "yyyy-MM-dd'T'HH:mm:ssZZZZZ").string(from: date)
    }

    static func displayString(from timestamp: String?) -> String? {
        guard let timestamp else { return nil }
        let trimmed = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let date = dateValue(from: trimmed) else { return trimmed }
        return makeFormatter(dateFormat: "yyyy-MM-dd HH:mm:ss").string(from: date)
    }

    static func clockString(from timestamp: String?) -> String? {
        guard let timestamp else { return nil }
        if let date = dateValue(from: timestamp) ?? displayDate(from: timestamp) {
            return makeFormatter(dateFormat: "HH:mm:ss").string(from: date)
        }
        let trimmed = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return trimmed.isEmpty ? nil : trimmed }
        return String(trimmed.suffix(8))
    }

    static func sortValue(from timestamp: String?) -> Int? {
        guard let timestamp else { return nil }
        if let date = dateValue(from: timestamp) ?? displayDate(from: timestamp) {
            return Int(date.timeIntervalSince1970)
        }
        let parts = timestamp.suffix(8).split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3_600 + parts[1] * 60 + parts[2]
    }

    static func dateValue(from timestamp: String) -> Date? {
        let isoFormatterWithFractionalSeconds = ISO8601DateFormatter()
        isoFormatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatterWithFractionalSeconds.date(from: timestamp) {
            return date
        }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: timestamp) {
            return date
        }
        return nil
    }

    private static func displayDate(from timestamp: String) -> Date? {
        makeFormatter(dateFormat: "yyyy-MM-dd HH:mm:ss").date(from: timestamp)
    }
}

enum AppLogSupport {
    private static let writer = ApplicationLogWriter()

    static func prepare(logsDirectory: URL) {
        writer.prepare(logsDirectory: logsDirectory)
    }

    static func flush() {
        writer.flush()
    }

    static func debug(_ message: String, module: String, logsDirectory: URL) {
        write(level: "debug", message: message, module: module, logsDirectory: logsDirectory)
    }

    static func info(_ message: String, module: String, logsDirectory: URL) {
        write(level: "info", message: message, module: module, logsDirectory: logsDirectory)
    }

    static func warning(_ message: String, module: String, logsDirectory: URL) {
        write(level: "warning", message: message, module: module, logsDirectory: logsDirectory)
    }

    static func error(_ message: String, module: String, logsDirectory: URL) {
        write(level: "error", message: message, module: module, logsDirectory: logsDirectory)
    }

    private static func write(level: String, message: String, module: String, logsDirectory: URL) {
        let timestamp = LogTimeSupport.string()
        let sanitized = message.replacingOccurrences(of: "\n", with: "\\n")
        let line = "[\(timestamp)] [\(level.uppercased())] [\(module)] \(sanitized)\n"
        let entry = CoreLogEntry(
            level: level,
            message: "[\(module)] \(sanitized)",
            rawText: String(line.dropLast()),
            time: LogTimeSupport.displayString(from: timestamp),
            source: .app
        )
        NotificationCenter.default.post(
            name: .clashMeowApplicationLogDidAppend,
            object: nil,
            userInfo: [ApplicationLogWriter.entryUserInfoKey: entry]
        )
        writer.append(line, logsDirectory: logsDirectory)
    }
}

final class ApplicationLogWriter: @unchecked Sendable {
    static let entryUserInfoKey = "entry"
    static let maximumRuntimeLogCount = 10
    static let maximumApplicationLogBytes: UInt64 = 10 * 1_024 * 1_024
    static let retainedApplicationLogBytes: UInt64 = 5 * 1_024 * 1_024
    static let maximumApplicationLogLineBytes = 64 * 1_024

    private let queue = DispatchQueue(label: "com.clash-meow.application-log", qos: .utility)
    private var logURL: URL?
    private var logHandle: FileHandle?

    func prepare(logsDirectory: URL) {
        queue.sync {
            prepareIfNeeded(logsDirectory: logsDirectory)
        }
    }

    func append(_ line: String, logsDirectory: URL) {
        queue.async { [self] in
            prepareIfNeeded(logsDirectory: logsDirectory)
            appendLogLine(line)
        }
    }

    func flush() {
        queue.sync {
            try? logHandle?.synchronize()
        }
    }

    private func prepareIfNeeded(logsDirectory: URL) {
        let targetURL = logsDirectory.appending(path: "app.log")
        guard targetURL.standardizedFileURL != logURL?.standardizedFileURL else { return }

        try? logHandle?.close()
        logHandle = nil
        logURL = targetURL
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        try? rotateApplicationLog(at: targetURL)
    }

    private func rotateApplicationLog(at currentLogURL: URL) throws {
        let fileManager = FileManager.default
        let directory = currentLogURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: currentLogURL.path) {
            let values = try? currentLogURL.resourceValues(
                forKeys: [.creationDateKey, .contentModificationDateKey]
            )
            let startedAt = values?.creationDate ?? values?.contentModificationDate ?? Date()
            let archiveStem = "app-\(Self.archiveTimestamp(startedAt))"
            var archiveURL = directory.appending(path: "\(archiveStem).log")
            var suffix = 2
            while fileManager.fileExists(atPath: archiveURL.path) {
                archiveURL = directory.appending(path: "\(archiveStem)-\(suffix).log")
                suffix += 1
            }
            try fileManager.moveItem(at: currentLogURL, to: archiveURL)
        }

        let archives = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { Self.isArchiveName($0.lastPathComponent) }
        .sorted { Self.isArchive($0, newerThan: $1) }
        for expiredURL in archives.dropFirst(Self.maximumRuntimeLogCount - 1) {
            try fileManager.removeItem(at: expiredURL)
        }
    }

    private func appendLogLine(_ line: String) {
        guard let logURL else { return }
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: logURL.path) {
            guard fileManager.createFile(
                atPath: logURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else { return }
        }

        var data = Data(line.utf8)
        if data.count > Self.maximumApplicationLogLineBytes {
            let marker = Data("... [log line truncated]\n".utf8)
            data = Data(data.prefix(Self.maximumApplicationLogLineBytes - marker.count))
            data.append(marker)
        }

        let handle: FileHandle
        if let logHandle {
            handle = logHandle
        } else {
            guard let openedHandle = try? FileHandle(forUpdating: logURL) else { return }
            logHandle = openedHandle
            handle = openedHandle
        }

        do {
            let currentSize = try handle.seekToEnd()
            if currentSize + UInt64(data.count) > Self.maximumApplicationLogBytes {
                try trimApplicationLog(handle, currentSize: currentSize)
            }
            try handle.write(contentsOf: data)
        } catch {
            try? handle.close()
            logHandle = nil
        }
    }

    private func trimApplicationLog(_ handle: FileHandle, currentSize: UInt64) throws {
        let tailOffset = currentSize - min(currentSize, Self.retainedApplicationLogBytes)
        try handle.seek(toOffset: tailOffset)
        var retainedData = try handle.readToEnd() ?? Data()
        if tailOffset > 0,
           let firstNewline = retainedData.firstIndex(of: 0x0A),
           firstNewline < retainedData.endIndex {
            retainedData.removeSubrange(...firstNewline)
        }

        let marker = Data("[Clash Meow application log truncated]\n".utf8)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: marker)
        try handle.write(contentsOf: retainedData)
        try handle.truncate(atOffset: UInt64(marker.count + retainedData.count))
        _ = try handle.seekToEnd()
    }

    private static func archiveTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: date)
    }

    private static func isArchiveName(_ fileName: String) -> Bool {
        fileName.range(
            of: #"^app-[0-9]{8}-[0-9]{6}-[0-9]{3}(?:-[0-9]+)?\.log$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isArchive(_ lhs: URL, newerThan rhs: URL) -> Bool {
        guard let lhsKey = archiveSortKey(lhs.lastPathComponent),
              let rhsKey = archiveSortKey(rhs.lastPathComponent) else {
            return lhs.lastPathComponent > rhs.lastPathComponent
        }
        if lhsKey.timestamp != rhsKey.timestamp {
            return lhsKey.timestamp > rhsKey.timestamp
        }
        return lhsKey.suffix > rhsKey.suffix
    }

    private static func archiveSortKey(_ fileName: String) -> (timestamp: String, suffix: Int)? {
        let prefix = "app-"
        guard fileName.hasPrefix(prefix), fileName.hasSuffix(".log") else { return nil }
        let stem = String(fileName.dropFirst(prefix.count).dropLast(4))
        guard stem.count >= 19 else { return nil }
        let timestampEnd = stem.index(stem.startIndex, offsetBy: 19)
        let timestamp = String(stem[..<timestampEnd])
        let suffixText = stem[timestampEnd...]
        if suffixText.isEmpty {
            return (timestamp, 1)
        }
        guard suffixText.first == "-", let suffix = Int(suffixText.dropFirst()) else {
            return nil
        }
        return (timestamp, suffix)
    }
}
