import Foundation
import Testing
@testable import DouClash

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
            .appending(path: "douclash-log-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "mihomo.log")
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
            .appending(path: "douclash-core-level-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "mihomo.log")
        try #"time="2026-07-04T09:38:39+08:00" level=warning msg="[TCP] connect error: timeout""#
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let logs = CoreLogSupport.recentLogs(from: fileURL)
        #expect(logs.count == 1)
        #expect(logs[0].normalizedLevel == "warning")
        #expect(logs[0].time == LogTimeSupport.displayString(from: "2026-07-04T09:38:39+08:00"))
    }

    @Test func recentLogsParsesAppLogLine() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "douclash-app-log-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "app.log")
        try "[2026-07-04T09:00:00Z] [ERROR] [Core] failed to start\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let logs = CoreLogSupport.recentLogs(from: fileURL, source: .app)
        #expect(logs.count == 1)
        #expect(logs[0].time == LogTimeSupport.displayString(from: "2026-07-04T09:00:00Z"))
        #expect(logs[0].normalizedLevel == "error")
        #expect(logs[0].message == "[Core] failed to start")
        #expect(logs[0].rawText == "[2026-07-04T09:00:00Z] [ERROR] [Core] failed to start")
        #expect(logs[0].source == .app)
    }

    @Test func recentLogsPreservesRawCoreTextAndDecodesMessage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "douclash-core-message-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "mihomo.log")
        let line = #"time="2026-07-04T09:02:00Z" level=warning msg="retry \"example.com\"""#
        try line.write(to: fileURL, atomically: true, encoding: .utf8)

        let log = try #require(CoreLogSupport.recentLogs(from: fileURL).first)
        #expect(log.message == #"retry "example.com""#)
        #expect(log.rawText == line)
        #expect(log.sortTime != nil)
    }

    @Test func recentLogsOnlyIncludesCurrentMihomoSession() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "douclash-session-log-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "mihomo.log")
        try """
        time="2026-07-04T09:00:00Z" level=info msg="previous session"
        malformed line without timestamp
        time="2026-07-04T09:02:00Z" level=info msg="current session"

        """.write(to: fileURL, atomically: true, encoding: .utf8)
        let startedAt = try #require(ISO8601DateFormatter().date(from: "2026-07-04T09:01:00Z"))

        let logs = CoreLogSupport.recentLogs(
            from: fileURL,
            source: .core,
            sessionStartedAt: startedAt
        )
        #expect(logs.map(\.message) == ["current session"])
    }

    @Test func tailReaderDropsPartialLeadingLine() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "douclash-tail-log-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "mihomo.log")
        try "discarded-prefix\nkeep-one\nkeep-two\n"
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let lines = CoreLogSupport.readLastLines(from: fileURL, count: 10, maximumBytes: 11)
        #expect(lines == ["keep-two"])
    }

    @Test func applicationLogWriterRotatesAndLimitsLines() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "douclash-app-writer-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appending(path: "app.log")
        try "previous session\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let writer = ApplicationLogWriter()
        writer.prepare(logsDirectory: directory)
        writer.append(String(repeating: "x", count: 70_000) + "\n", logsDirectory: directory)
        writer.flush()

        let archives = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("app-") }
        #expect(archives.count == 1)
        #expect(try String(contentsOf: archives[0], encoding: .utf8) == "previous session\n")

        let data = try Data(contentsOf: fileURL)
        #expect(data.count == ApplicationLogWriter.maximumApplicationLogLineBytes)
        #expect(String(decoding: data, as: UTF8.self).hasSuffix("... [log line truncated]\n"))
        let permissions = try #require(
            FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
        )
        #expect(permissions.intValue & 0o777 == 0o600)
    }

    @Test func applicationLogWriterKeepsNewestNumericArchiveSuffixes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "douclash-app-archive-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for suffix in 1...11 {
            let suffixText = suffix == 1 ? "" : "-\(suffix)"
            let url = directory.appending(path: "app-20260704-090000-000\(suffixText).log")
            try "archive \(suffix)".write(to: url, atomically: true, encoding: .utf8)
        }

        let writer = ApplicationLogWriter()
        writer.prepare(logsDirectory: directory)
        let names = try Set(
            FileManager.default.contentsOfDirectory(atPath: directory.path)
        )
        #expect(names.count == ApplicationLogWriter.maximumRuntimeLogCount - 1)
        #expect(names.contains("app-20260704-090000-000-10.log"))
        #expect(names.contains("app-20260704-090000-000-11.log"))
        #expect(!names.contains("app-20260704-090000-000.log"))
        #expect(!names.contains("app-20260704-090000-000-2.log"))
    }

    @Test @MainActor func mihomoLogStoreCapsPublishedEntries() {
        let store = MihomoLogStore()
        let entries = (0..<4).map { CoreLogEntry(id: "\($0)", message: "entry \($0)") }
        store.appendEntries(entries, limit: 3)
        #expect(store.entries.map(\.id) == ["1", "2", "3"])
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
        #expect(entry?.rawText == json)
        #expect(entry?.sortTime != nil)
    }

    @Test func oversizedMihomoWebSocketPayloadIsRejected() {
        let payload = String(repeating: "x", count: MihomoAPI.maximumLogEntryBytes + 1)
        #expect(MihomoAPI.logEntry(from: payload) == nil)
    }
}
