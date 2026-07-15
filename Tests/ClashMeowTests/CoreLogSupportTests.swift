import Foundation
import Testing
@testable import ClashMeow

struct CoreLogSupportTests {
    @Test func logTimeSupportFormatsDateInCurrentTimeZone() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-07-04T02:00:00Z"))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        let displayFormatter = DateFormatter()
        displayFormatter.locale = Locale(identifier: "en_US_POSIX")
        displayFormatter.timeZone = .current
        displayFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        #expect(LogTimeSupport.string(from: date) == formatter.string(from: date))
        #expect(LogTimeSupport.displayString(from: "2026-07-04T02:00:00Z") == displayFormatter.string(from: date))
    }

    @Test func inferredLevelDetectsSeverityFromMessage() {
        #expect(CoreLogSupport.inferredLevel(in: "connection error: timeout") == "error")
        #expect(CoreLogSupport.inferredLevel(in: "warning: dns fallback") == "warning")
        #expect(CoreLogSupport.inferredLevel(in: "debug trace enabled") == "debug")
        #expect(CoreLogSupport.inferredLevel(in: "started successfully") == "info")
    }

    @Test func normalizedLevelMapsWarnAliases() {
        #expect(CoreLogSupport.normalizedLevel("warn") == "warning")
        #expect(CoreLogSupport.normalizedLevel("WARNING") == "warning")
        #expect(CoreLogSupport.normalizedLevel("err") == "error")
    }

    @Test func recentLogsReadsTrailingLinesFromFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clashmeow-log-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "core.log")
        try "info line one\nwarning line two\nerror line three\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let logs = CoreLogSupport.recentLogs(from: fileURL, limit: 2)
        #expect(logs.count == 2)
        #expect(logs[0].message == "warning line two")
        #expect(logs[0].normalizedLevel == "warning")
        #expect(logs[0].source == .core)
        #expect(logs[1].message == "error line three")
        #expect(logs[1].normalizedLevel == "error")
    }

    @Test func recentLogsUsesStructuredCoreLevelBeforeMessageText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clashmeow-core-level-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "core.log")
        try #"time="2026-07-04T09:38:39+08:00" level=warning msg="[TCP] connect error: timeout""#
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let logs = CoreLogSupport.recentLogs(from: fileURL)
        #expect(logs.count == 1)
        #expect(logs[0].normalizedLevel == "warning")
        #expect(logs[0].time == LogTimeSupport.displayString(from: "2026-07-04T09:38:39+08:00"))
    }

    @Test func recentLogsParsesAppLogLine() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clashmeow-app-log-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "app.log")
        try "[2026-07-04T09:00:00Z] [ERROR] [Core] failed to start\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let logs = CoreLogSupport.recentLogs(from: fileURL, source: .app)
        #expect(logs.count == 1)
        #expect(logs[0].time == LogTimeSupport.displayString(from: "2026-07-04T09:00:00Z"))
        #expect(logs[0].normalizedLevel == "error")
        #expect(logs[0].message == "[Core] failed to start")
        #expect(logs[0].source == .app)
    }

    @Test func appendWithLimitKeepsRecentContentAndMarker() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clashmeow-capped-log-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "core.log")
        try String(repeating: "old-", count: 30).write(to: fileURL, atomically: true, encoding: .utf8)
        try CoreLogSupport.appendWithLimit("new-important-line\n", to: fileURL, maxBytes: 80)

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.contains("File truncated because size limit reached"))
        #expect(content.contains("new-important-line"))
        #expect((try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0 <= 80)
    }

    @Test func truncateClearsLogFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "clashmeow-truncate-log-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "core.log")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)
        try CoreLogSupport.truncate(fileURL)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.isEmpty)
    }

    @Test func logEntryParsesMihomoWebSocketPayload() {
        let json = """
        {"type":"info","payload":"[TCP] example.com:443","time":"2026-06-28T08:00:00Z","id":"abc"}
        """
        let entry = MihomoAPI.logEntry(from: json)
        #expect(entry?.id == "abc")
        #expect(entry?.normalizedLevel == "info")
        #expect(entry?.message == "[TCP] example.com:443")
        #expect(entry?.time == LogTimeSupport.displayString(from: "2026-06-28T08:00:00Z"))
    }
}
