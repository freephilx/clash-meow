import Foundation
import Testing
@testable import ClashMeow

struct CoreLogSupportTests {
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
        #expect(logs[1].message == "error line three")
        #expect(logs[1].normalizedLevel == "error")
    }

    @Test func logEntryParsesMihomoWebSocketPayload() {
        let json = """
        {"type":"info","payload":"[TCP] example.com:443","time":"2026-06-28T08:00:00Z","id":"abc"}
        """
        let entry = MihomoAPI.logEntry(from: json)
        #expect(entry?.id == "abc")
        #expect(entry?.normalizedLevel == "info")
        #expect(entry?.message == "[TCP] example.com:443")
        #expect(entry?.time == "2026-06-28T08:00:00Z")
    }
}
