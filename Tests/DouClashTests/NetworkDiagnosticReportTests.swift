import Foundation
import Testing
@testable import DouClash

struct NetworkDiagnosticReportTests {
    @Test @MainActor func reportGenerationCreatesPrivateZipAndCompletesProgress() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "dou-clash-diagnostic-generate-\(UUID().uuidString)", directoryHint: .isDirectory)
        let logs = root.appending(path: "logs", directoryHint: .isDirectory)
        let reports = root.appending(path: "reports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appLog = logs.appending(path: "app.log")
        let mihomoLog = logs.appending(path: "mihomo.log")
        try "token=app-secret\n".write(to: appLog, atomically: true, encoding: .utf8)
        try "password: core-secret\n".write(to: mihomoLog, atomically: true, encoding: .utf8)
        let context = NetworkDiagnosticReportContext(
            createdAt: Date(timeIntervalSince1970: 1_786_214_400),
            appVersion: "test (1)",
            macOSVersion: "test macOS",
            architecture: "test architecture",
            mihomoStatus: "已停止",
            mihomoVersion: "未知",
            profileName: "default.yaml",
            tunEnabled: false,
            controllerSummary: "未响应",
            systemProxySummary: "未启用",
            localDNSSummary: "未找到",
            latencySummary: "公网 -- · 默认网关 -- · DNS --",
            diagnosticSummary: ["测试：信息；无"],
            recentErrors: [],
            managedMihomoPID: nil,
            appLogURL: appLog,
            mihomoLogURL: mihomoLog,
            reportsRootURL: reports
        )
        var progressValues: [NetworkDiagnosticReportProgress] = []

        let archive = try await NetworkDiagnosticReportService.generate(context: context) {
            progressValues.append($0)
        }

        #expect(FileManager.default.fileExists(atPath: archive.path))
        #expect(archive.lastPathComponent.hasPrefix("DouClash-Network-Diagnostics-"))
        #expect(progressValues.first == .collectingLogs)
        #expect(progressValues.last == .complete)
        let attributes = try FileManager.default.attributesOfItem(atPath: archive.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        #expect(permissions == 0o600)

        let extracted = root.appending(path: "extracted", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, extracted.path]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = FileHandle.nullDevice
        try ditto.run()
        ditto.waitUntilExit()
        #expect(ditto.terminationStatus == 0)

        let reportDirectory = extracted.appending(
            path: archive.deletingPathExtension().lastPathComponent,
            directoryHint: .isDirectory
        )
        let collectedAppLog = try String(
            contentsOf: reportDirectory.appending(path: "app.log"),
            encoding: .utf8
        )
        let collectedMihomoLog = try String(
            contentsOf: reportDirectory.appending(path: "mihomo.log"),
            encoding: .utf8
        )
        #expect(!collectedAppLog.contains("app-secret"))
        #expect(!collectedMihomoLog.contains("core-secret"))
    }

    @Test func redactionRemovesCredentialsAndHomeDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let input = """
        Authorization: Bearer bearer-secret
        token=token-secret
        Cookie: session=cookie-secret
        https://user:password@example.com/path?auth=query-secret
        https://subscribe.example/api/client/secret-path
        api_key: sk-abcdefghijklmnop
        --password command-secret
        \(home)/.config/dou-clash/runtime/logs/app.log
        /Users/another-user/private/file
        """

        let output = NetworkDiagnosticReportService.redacted(input)

        for secret in [
            "bearer-secret", "token-secret", "cookie-secret", "password@example.com",
            "query-secret", "secret-path", "sk-abcdefghijklmnop", "command-secret", "another-user"
        ] {
            #expect(!output.contains(secret))
        }
        #expect(output.contains("<redacted>"))
        #expect(output.contains("~/.config/dou-clash"))
    }

    @Test func recentLogsUseOnlyCurrentAndThreeNewestSafeArchives() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "dou-clash-diagnostic-logs-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let current = directory.appending(path: "app.log")
        try "current token=current-secret\n".write(to: current, atomically: true, encoding: .utf8)
        for index in 1...4 {
            let archive = directory.appending(path: "app-20260809-18000\(index)-000.log")
            try "archive-\(index)\n".write(to: archive, atomically: true, encoding: .utf8)
        }
        try "unrelated\n".write(
            to: directory.appending(path: "other-20260809-190000-000.log"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: directory.appending(path: "app-20260809-190000-000.log"),
            withDestinationURL: directory.appending(path: "app-20260809-180001-000.log")
        )

        let output = NetworkDiagnosticReportService.collectRecentLogs(
            currentLogURL: current,
            archivePrefix: "app"
        )

        #expect(!output.contains("archive-1"))
        #expect(output.contains("archive-2"))
        #expect(output.contains("archive-3"))
        #expect(output.contains("archive-4"))
        #expect(output.contains("app.log（当前）"))
        #expect(!output.contains("current-secret"))
        #expect(!output.contains("unrelated"))
    }

    @Test func reportRetentionKeepsNewestFiveArchives() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "dou-clash-diagnostic-retention-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for index in 1...7 {
            let archive = directory.appending(path: "DouClash-Network-Diagnostics-20260809-18000\(index)-000.zip")
            try Data("report-\(index)".utf8).write(to: archive)
        }
        let unrelated = directory.appending(path: "unrelated.zip")
        try Data("unrelated".utf8).write(to: unrelated)

        try NetworkDiagnosticReportService.retainRecentReports(in: directory)

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.filter { $0.hasPrefix("DouClash-Network-Diagnostics-") }.count == 5)
        #expect(!names.contains("DouClash-Network-Diagnostics-20260809-180001-000.zip"))
        #expect(!names.contains("DouClash-Network-Diagnostics-20260809-180002-000.zip"))
        #expect(names.contains("unrelated.zip"))
    }
}
