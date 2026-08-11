import Foundation

struct NetworkDiagnosticReportProgress: Equatable, Sendable {
    let fractionCompleted: Double
    let title: String

    static let preparing = NetworkDiagnosticReportProgress(
        fractionCompleted: 0.05,
        title: "正在准备网络诊断"
    )
    static let checkingNetwork = NetworkDiagnosticReportProgress(
        fractionCompleted: 0.2,
        title: "正在检查网络连接"
    )
    static let collectingLogs = NetworkDiagnosticReportProgress(
        fractionCompleted: 0.55,
        title: "正在收集必要日志"
    )
    static let buildingReport = NetworkDiagnosticReportProgress(
        fractionCompleted: 0.72,
        title: "正在生成诊断报告"
    )
    static let compressing = NetworkDiagnosticReportProgress(
        fractionCompleted: 0.88,
        title: "正在压缩诊断报告"
    )
    static let complete = NetworkDiagnosticReportProgress(
        fractionCompleted: 1,
        title: "诊断报告已生成"
    )
}

struct NetworkDiagnosticReportContext: Sendable {
    let createdAt: Date
    let appVersion: String
    let macOSVersion: String
    let architecture: String
    let mihomoStatus: String
    let mihomoVersion: String
    let profileName: String
    let tunEnabled: Bool
    let controllerSummary: String
    let systemProxySummary: String
    let localDNSSummary: String
    let latencySummary: String
    let diagnosticSummary: [String]
    let recentErrors: [String]
    let managedMihomoPID: Int32?
    let appLogURL: URL
    let mihomoLogURL: URL
    let reportsRootURL: URL
}

private struct NetworkDiagnosticReportContents: Sendable {
    let summary: String
    let appLog: String
    let mihomoLog: String
}

private struct NetworkDiagnosticReportWorkspace: Sendable {
    let stagingRootURL: URL
    let reportDirectoryURL: URL
    let archiveURL: URL
}

extension AppState {
    func generateNetworkDiagnosticReport(
        progress: @escaping @MainActor @Sendable (NetworkDiagnosticReportProgress) -> Void
    ) async throws -> URL {
        progress(.preparing)
        AppLogSupport.info("开始收集诊断报告", module: "NetworkDiagnostics", logsDirectory: core.logsDirectory)

        do {
            progress(.checkingNetwork)
            while isDiagnosingInternetLatency {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(100))
            }
            await diagnoseInternetLatency()
            try Task.checkCancellation()

            let controllerSummary: String
            do {
                let controllerVersion = try await api.version()
                controllerSummary = "127.0.0.1:\(controllerPort) 可用 · Mihomo \(controllerVersion.version ?? "未知")"
            } catch {
                controllerSummary = "127.0.0.1:\(controllerPort) 未响应 · \(error.localizedDescription)"
            }

            let systemProxyPort = systemProxyPort
            let systemProxySummary = await Task.detached(priority: .utility) {
                let controller = SystemProxyController()
                do {
                    let configuration = try controller.resolvedConfiguration(port: systemProxyPort)
                    return switch try controller.health(configuration: configuration) {
                    case .enabled:
                        "\(configuration.networkService)：已指向 \(configuration.host):\(configuration.port)"
                    case .disabled:
                        "\(configuration.networkService)：未启用"
                    case .mismatched:
                        "\(configuration.networkService)：已启用，但未完整指向 \(configuration.host):\(configuration.port)"
                    }
                } catch {
                    return "无法读取 · \(error.localizedDescription)"
                }
            }.value
            let localDNSSummary = await Task.detached(priority: .utility) {
                LocalDNSDiagnostics.current().summary
            }.value
            try Task.checkCancellation()

            AppLogSupport.flush()
            let snapshot = internetLatencySnapshot
            let recentErrors = logs
                .filter { CoreLogSupport.normalizedLevel($0.level) == "error" }
                .suffix(10)
                .map(\.rawText)
            let context = NetworkDiagnosticReportContext(
                createdAt: Date(),
                appVersion: "\(AppInfo.version) (\(AppInfo.build))",
                macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                architecture: NetworkDiagnosticReportService.machineArchitecture,
                mihomoStatus: core.status.title,
                mihomoVersion: version?.version ?? "未知",
                profileName: currentProfileName,
                tunEnabled: isTunEnabled,
                controllerSummary: controllerSummary,
                systemProxySummary: systemProxySummary,
                localDNSSummary: localDNSSummary,
                latencySummary: "公网 \(snapshot.internetText) · 默认网关 \(snapshot.routerText) · DNS \(snapshot.dnsText)",
                diagnosticSummary: snapshot.entries.map {
                    "\($0.title)：\($0.level.reportTitle)；\($0.message)"
                },
                recentErrors: recentErrors,
                managedMihomoPID: core.managedProcessIdentifier,
                appLogURL: core.appLogFile,
                mihomoLogURL: core.coreLogFile,
                reportsRootURL: AppPersistencePaths.diagnosticReportsDirectory
            )
            let archiveURL = try await NetworkDiagnosticReportService.generate(
                context: context,
                progress: progress
            )
            AppLogSupport.info(
                "诊断报告已生成：\(archiveURL.lastPathComponent)",
                module: "NetworkDiagnostics",
                logsDirectory: core.logsDirectory
            )
            return archiveURL
        } catch is CancellationError {
            AppLogSupport.info("诊断报告生成已取消", module: "NetworkDiagnostics", logsDirectory: core.logsDirectory)
            throw CancellationError()
        } catch {
            AppLogSupport.error(
                "诊断报告生成失败：\(error.localizedDescription)",
                module: "NetworkDiagnostics",
                logsDirectory: core.logsDirectory
            )
            throw error
        }
    }
}

private extension InternetDiagnosticEntry.Level {
    var reportTitle: String {
        switch self {
        case .success: "正常"
        case .warning: "异常"
        case .info: "信息"
        }
    }
}

enum NetworkDiagnosticReportService {
    static let maximumReportCount = 5
    static let maximumArchivedLogCount = 3
    static let maximumLogLineCountPerFile = 500
    static let maximumCombinedLogBytes = 2 * 1_024 * 1_024
    static let maximumLogLineLength = 4_000
    static let maximumRecentErrorLength = 4_000

    static var machineArchitecture: String {
        #if arch(arm64)
        "Apple Silicon"
        #elseif arch(x86_64)
        "Intel"
        #else
        "未知架构"
        #endif
    }

    private static var maximumLogSectionBytes: Int {
        let maximumCollectedFileCount = maximumArchivedLogCount + 1
        let separatorBytes = (maximumCollectedFileCount - 1) * 2
        return (maximumCombinedLogBytes - separatorBytes) / maximumCollectedFileCount
    }

    static func generate(
        context: NetworkDiagnosticReportContext,
        progress: @escaping @MainActor @Sendable (NetworkDiagnosticReportProgress) -> Void
    ) async throws -> URL {
        var workspace: NetworkDiagnosticReportWorkspace?

        do {
            await progress(.collectingLogs)
            let contents = try await runOnUtilityQueue {
                try makeContents(context: context)
            }

            await progress(.buildingReport)
            let createdWorkspace = try await runOnUtilityQueue {
                try write(contents: contents, context: context)
            }
            workspace = createdWorkspace

            await progress(.compressing)
            let archiveURL = try await runOnUtilityQueue {
                try compress(workspace: createdWorkspace)
                try retainRecentReports(in: context.reportsRootURL)
                return createdWorkspace.archiveURL
            }

            try? FileManager.default.removeItem(at: createdWorkspace.stagingRootURL)
            await progress(.complete)
            return archiveURL
        } catch is CancellationError {
            cleanup(workspace)
            throw CancellationError()
        } catch {
            cleanup(workspace)
            if let reportError = error as? NetworkDiagnosticReportError {
                throw reportError
            }
            throw NetworkDiagnosticReportError.generationFailed
        }
    }

    private static func makeContents(
        context: NetworkDiagnosticReportContext
    ) throws -> NetworkDiagnosticReportContents {
        try Task.checkCancellation()

        let appLog = collectRecentLogs(
            currentLogURL: context.appLogURL,
            archivePrefix: "app"
        )
        let mihomoLog = collectRecentLogs(
            currentLogURL: context.mihomoLogURL,
            archivePrefix: "mihomo"
        )
        let processDetails = try makeProxyProcessDetails(
            managedMihomoPID: context.managedMihomoPID
        )
        let dnsDetails = try makeDNSDetails()
        let summary = makeSummary(
            context: context,
            processDetails: processDetails,
            dnsDetails: dnsDetails
        )
        try Task.checkCancellation()

        return NetworkDiagnosticReportContents(
            summary: redacted(summary),
            appLog: appLog,
            mihomoLog: mihomoLog
        )
    }

    private static func makeSummary(
        context: NetworkDiagnosticReportContext,
        processDetails: String,
        dnsDetails: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let diagnosticText = context.diagnosticSummary.isEmpty
            ? "- 无诊断结果"
            : context.diagnosticSummary.map { "- \($0)" }.joined(separator: "\n")
        let errorText = context.recentErrors.isEmpty
            ? "无"
            : context.recentErrors
                .map { limited($0, maxLength: maximumRecentErrorLength) }
                .joined(separator: "\n")

        return """
        DouClash 网络诊断报告

        生成时间：\(formatter.string(from: context.createdAt))
        DouClash：\(context.appVersion)
        macOS：\(context.macOSVersion)
        芯片：\(context.architecture)

        运行状态
        - Mihomo：\(context.mihomoStatus)
        - Mihomo 版本：\(context.mihomoVersion)
        - 当前配置：\(context.profileName)
        - TUN：\(context.tunEnabled ? "开启" : "关闭")
        - Controller：\(context.controllerSummary)
        - 系统代理：\(context.systemProxySummary)
        - 本机 DNS：\(context.localDNSSummary)
        - 延迟摘要：\(context.latencySummary)

        网络诊断
        \(diagnosticText)

        Mihomo 和 Clash 进程明细
        \(processDetails)

        DNS 明细
        \(dnsDetails)

        最近错误
        \(errorText)

        隐私说明
        报告仅包含脱敏后的运行状态、进程与 DNS 明细和近期日志，不包含 Mihomo YAML、偏好文件、订阅地址、API Key、Token、Cookie、密码或完整配置。
        """
    }

    private static func makeProxyProcessDetails(
        managedMihomoPID: Int32?
    ) throws -> String {
        try Task.checkCancellation()
        let processList = runCommand(
            executable: "/bin/ps",
            arguments: ["-ww", "-axo", "pid=,comm="]
        )
        guard processList.succeeded else {
            return "进程表采集失败：\(processList.summary)"
        }

        let processes = processList.output
            .components(separatedBy: .newlines)
            .compactMap(proxyProcess(from:))
            .sorted {
                $0.category == $1.category ? $0.pid < $1.pid : $0.category < $1.category
            }
        var sections = ["枚举范围：系统进程表中可见且可执行文件名包含 mihomo 或 clash 的进程。"]

        for category in ["Mihomo", "Clash"] {
            try Task.checkCancellation()
            let matchingProcesses = processes.filter { $0.category == category }
            sections.append("\(category)（\(matchingProcesses.count) 个）")
            guard !matchingProcesses.isEmpty else {
                sections.append("  未发现")
                continue
            }

            for process in matchingProcesses {
                try Task.checkCancellation()
                let managedLabel = category == "Mihomo" && process.pid == managedMihomoPID
                    ? "；DouClash 管理：是"
                    : ""
                sections.append("  PID \(process.pid)；可执行文件：\(process.executable)\(managedLabel)")
                let detail = runCommand(
                    executable: "/bin/ps",
                    arguments: [
                        "-ww", "-p", String(process.pid),
                        "-o", "pid=,ppid=,uid=,user=,state=,lstart=,etime=,%cpu=,%mem=,comm=,command="
                    ]
                )
                sections.append(
                    detail.succeeded
                        ? indented(diagnosticCommandOutput(detail), by: "  ")
                        : "  进程详情采集失败或进程已经退出：\(detail.summary)"
                )
            }
        }
        return sections.joined(separator: "\n")
    }

    private static func makeDNSDetails() throws -> String {
        try Task.checkCancellation()
        var sections = ["networksetup（全部网络服务）"]
        let serviceList = runCommand(
            executable: "/usr/sbin/networksetup",
            arguments: ["-listallnetworkservices"]
        )
        if serviceList.succeeded {
            let services = networkServices(from: serviceList.output)
            if services.isEmpty {
                sections.append("  未发现网络服务")
            }
            for service in services {
                try Task.checkCancellation()
                sections.append("  [\(service.isEnabled ? "启用" : "停用")] \(service.name)")
                let dnsServers = runCommand(
                    executable: "/usr/sbin/networksetup",
                    arguments: ["-getdnsservers", service.name]
                )
                sections.append("    DNS 服务器：")
                sections.append(indented(diagnosticCommandOutput(dnsServers), by: "      "))
                let searchDomains = runCommand(
                    executable: "/usr/sbin/networksetup",
                    arguments: ["-getsearchdomains", service.name]
                )
                sections.append("    搜索域：")
                sections.append(indented(diagnosticCommandOutput(searchDomains), by: "      "))
            }
        } else {
            sections.append(indented("采集失败：\(serviceList.summary)", by: "  "))
        }

        try Task.checkCancellation()
        sections.append("\nscutil --dns（系统当前有效解析器）")
        sections.append(diagnosticCommandOutput(runCommand(
            executable: "/usr/sbin/scutil",
            arguments: ["--dns"]
        )))

        try Task.checkCancellation()
        sections.append("\n/etc/resolv.conf")
        sections.append(fileContents(atPath: "/etc/resolv.conf"))

        try Task.checkCancellation()
        sections.append("\n/etc/resolver")
        let resolverDirectoryURL = URL(fileURLWithPath: "/etc/resolver", isDirectory: true)
        do {
            let resolverURLs = try FileManager.default.contentsOfDirectory(
                at: resolverDirectoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            let safeResolverURLs = resolverURLs.filter(isSafeRegularFile)
            if safeResolverURLs.isEmpty {
                sections.append("目录为空")
            }
            for resolverURL in safeResolverURLs {
                try Task.checkCancellation()
                sections.append("[\(resolverURL.lastPathComponent)]")
                sections.append(fileContents(atPath: resolverURL.path))
            }
        } catch CocoaError.fileReadNoSuchFile {
            sections.append("目录不存在")
        } catch {
            sections.append("目录读取失败：\(error.localizedDescription)")
        }
        return sections.joined(separator: "\n")
    }

    private static func proxyProcess(
        from line: String
    ) -> (category: String, pid: Int32, executable: String)? {
        let fields = line.split(
            maxSplits: 1,
            omittingEmptySubsequences: true,
            whereSeparator: { $0.isWhitespace }
        )
        guard fields.count == 2, let pid = Int32(fields[0]), pid > 0 else { return nil }
        let executable = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        if name.contains("mihomo") {
            return ("Mihomo", pid, executable)
        }
        if name.contains("clash") {
            return ("Clash", pid, executable)
        }
        return nil
    }

    private static func networkServices(
        from output: String
    ) -> [(name: String, isEnabled: Bool)] {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk (*) denotes") }
            .compactMap { line in
                let isEnabled = !line.hasPrefix("*")
                let name = isEnabled
                    ? line
                    : String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : (name, isEnabled)
            }
    }

    private static func diagnosticCommandOutput(_ result: DiagnosticCommandResult) -> String {
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.succeeded {
            return output.isEmpty ? "命令成功，无输出" : output
        }
        let detail = output.isEmpty ? result.error : output
        return detail.isEmpty
            ? "采集失败（退出码 \(result.exitCode)）"
            : "采集失败（退出码 \(result.exitCode)）：\(detail)"
    }

    private static func fileContents(atPath path: String) -> String {
        do {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return contents.isEmpty ? "文件为空" : contents
        } catch CocoaError.fileReadNoSuchFile {
            return "文件不存在"
        } catch {
            return "文件读取失败：\(error.localizedDescription)"
        }
    }

    private static func indented(_ text: String, by prefix: String) -> String {
        text.components(separatedBy: .newlines)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    private static func write(
        contents: NetworkDiagnosticReportContents,
        context: NetworkDiagnosticReportContext
    ) throws -> NetworkDiagnosticReportWorkspace {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: context.reportsRootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: context.reportsRootURL.path
        )

        let baseName = reportBaseName(for: context.createdAt)
        let stagingRootURL = context.reportsRootURL.appending(
            path: ".staging-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let reportDirectoryURL = stagingRootURL.appending(path: baseName, directoryHint: .isDirectory)
        let archiveURL = uniqueArchiveURL(
            in: context.reportsRootURL,
            baseName: baseName,
            fileManager: fileManager
        )

        do {
            try fileManager.createDirectory(
                at: stagingRootURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.createDirectory(
                at: reportDirectoryURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            try write(contents.summary, to: reportDirectoryURL.appending(path: "report.txt"))
            try write(contents.appLog, to: reportDirectoryURL.appending(path: "app.log"))
            try write(contents.mihomoLog, to: reportDirectoryURL.appending(path: "mihomo.log"))
            try Task.checkCancellation()
            return NetworkDiagnosticReportWorkspace(
                stagingRootURL: stagingRootURL,
                reportDirectoryURL: reportDirectoryURL,
                archiveURL: archiveURL
            )
        } catch {
            try? fileManager.removeItem(at: stagingRootURL)
            try? fileManager.removeItem(at: archiveURL)
            throw error
        }
    }

    private static func write(_ content: String, to url: URL) throws {
        try "\(content)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static func compress(workspace: NetworkDiagnosticReportWorkspace) throws {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--noacl", "--keepParent",
            workspace.reportDirectoryURL.path,
            workspace.archiveURL.path
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw NetworkDiagnosticReportError.compressionFailed
        }
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: workspace.archiveURL.path) else {
            throw NetworkDiagnosticReportError.compressionFailed
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: workspace.archiveURL.path
        )
        try Task.checkCancellation()
    }

    static func retainRecentReports(in reportsRootURL: URL) throws {
        let archives = try FileManager.default.contentsOfDirectory(
            at: reportsRootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        .filter {
            $0.pathExtension.lowercased() == "zip"
                && $0.deletingPathExtension().lastPathComponent.hasPrefix("DouClash-Network-Diagnostics-")
                && isSafeRegularFile($0)
        }
        .sorted { $0.lastPathComponent > $1.lastPathComponent }

        for expiredArchiveURL in archives.dropFirst(maximumReportCount) {
            try FileManager.default.removeItem(at: expiredArchiveURL)
        }
    }

    static func reportBaseName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return "DouClash-Network-Diagnostics-\(formatter.string(from: date))"
    }

    private static func uniqueArchiveURL(
        in directoryURL: URL,
        baseName: String,
        fileManager: FileManager
    ) -> URL {
        var archiveURL = directoryURL.appending(path: "\(baseName).zip")
        var suffix = 2
        while fileManager.fileExists(atPath: archiveURL.path) {
            archiveURL = directoryURL.appending(path: "\(baseName)-\(suffix).zip")
            suffix += 1
        }
        return archiveURL
    }

    static func collectRecentLogs(
        currentLogURL: URL,
        archivePrefix: String
    ) -> String {
        let sections = recentLogURLs(
            currentLogURL: currentLogURL,
            archivePrefix: archivePrefix
        ).compactMap { logURL in
            logSection(from: logURL, currentLogURL: currentLogURL)
        }
        return sections.isEmpty ? "无可用日志" : sections.joined(separator: "\n\n")
    }

    private static func recentLogURLs(
        currentLogURL: URL,
        archivePrefix: String
    ) -> [URL] {
        let directoryURL = currentLogURL.deletingLastPathComponent()
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let archives = entries
            .filter {
                isRuntimeLogArchiveName($0.lastPathComponent, prefix: archivePrefix)
                    && isSafeRegularFile($0)
            }
            .sorted {
                isRuntimeLogArchive($0, newerThan: $1, prefix: archivePrefix)
            }

        var result = Array(archives.prefix(maximumArchivedLogCount).reversed())
        if isSafeRegularFile(currentLogURL) {
            result.append(currentLogURL)
        }
        return result
    }

    private static func isRuntimeLogArchiveName(_ fileName: String, prefix: String) -> Bool {
        let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
        return fileName.range(
            of: "^\(escapedPrefix)-[0-9]{8}-[0-9]{6}-[0-9]{3}(?:-[0-9]+)?\\.log$",
            options: .regularExpression
        ) != nil
    }

    private static func isRuntimeLogArchive(
        _ lhs: URL,
        newerThan rhs: URL,
        prefix: String
    ) -> Bool {
        guard let lhsKey = runtimeLogArchiveSortKey(lhs.lastPathComponent, prefix: prefix),
              let rhsKey = runtimeLogArchiveSortKey(rhs.lastPathComponent, prefix: prefix) else {
            return lhs.lastPathComponent > rhs.lastPathComponent
        }
        if lhsKey.timestamp != rhsKey.timestamp {
            return lhsKey.timestamp > rhsKey.timestamp
        }
        return lhsKey.suffix > rhsKey.suffix
    }

    private static func runtimeLogArchiveSortKey(
        _ fileName: String,
        prefix: String
    ) -> (timestamp: String, suffix: Int)? {
        let leadingText = "\(prefix)-"
        guard fileName.hasPrefix(leadingText), fileName.hasSuffix(".log") else { return nil }
        let stem = String(fileName.dropFirst(leadingText.count).dropLast(4))
        guard stem.count >= 19 else { return nil }
        let timestampEnd = stem.index(stem.startIndex, offsetBy: 19)
        let timestamp = String(stem[..<timestampEnd])
        let suffixText = stem[timestampEnd...]
        if suffixText.isEmpty {
            return (timestamp, 1)
        }
        guard suffixText.first == "-", let suffix = Int(suffixText.dropFirst()) else { return nil }
        return (timestamp, suffix)
    }

    private static func isSafeRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private static func logSection(from url: URL, currentLogURL: URL) -> String? {
        let lines = readLastLines(
            from: url,
            count: maximumLogLineCountPerFile,
            maximumBytes: maximumLogSectionBytes
        ).map {
            limited(redacted($0), maxLength: maximumLogLineLength)
        }
        guard !lines.isEmpty else { return nil }

        let isCurrent = url.standardizedFileURL == currentLogURL.standardizedFileURL
        let title = isCurrent ? "\(url.lastPathComponent)（当前）" : url.lastPathComponent
        let header = "===== \(title) ====="
        let bodyByteLimit = maximumLogSectionBytes - header.utf8.count - 1
        var selectedLines: [String] = []
        var selectedByteCount = 0
        for line in lines.reversed() {
            let lineByteCount = line.utf8.count + (selectedLines.isEmpty ? 0 : 1)
            guard selectedByteCount + lineByteCount <= bodyByteLimit else { break }
            selectedLines.append(line)
            selectedByteCount += lineByteCount
        }
        guard !selectedLines.isEmpty else { return nil }
        return ([header] + Array(selectedLines.reversed())).joined(separator: "\n")
    }

    private static func readLastLines(
        from url: URL,
        count: Int,
        maximumBytes: Int
    ) -> [String] {
        guard count > 0, maximumBytes > 0,
              let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        do {
            let chunkSize: UInt64 = 64 * 1_024
            let fileSize = try handle.seekToEnd()
            var remainingBytes = fileSize
            var chunks: [Data] = []
            var newlineCount = 0
            var collectedByteCount: UInt64 = 0

            while remainingBytes > 0,
                  newlineCount <= count,
                  collectedByteCount < UInt64(maximumBytes) {
                try Task.checkCancellation()
                let remainingLimit = UInt64(maximumBytes) - collectedByteCount
                let bytesToRead = min(chunkSize, min(remainingBytes, remainingLimit))
                remainingBytes -= bytesToRead
                try handle.seek(toOffset: remainingBytes)
                guard let chunk = try handle.read(upToCount: Int(bytesToRead)), !chunk.isEmpty else { break }
                chunks.append(chunk)
                collectedByteCount += UInt64(chunk.count)
                newlineCount += chunk.reduce(into: 0) { total, byte in
                    if byte == 0x0A { total += 1 }
                }
            }

            var tailData = Data()
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

    static func limited(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<end]) + "…内容已截断"
    }

    static func redacted(_ text: String) -> String {
        var output = text
        let replacements = [
            (#"(?i)(authorization\s*:\s*bearer\s+)[^\s\"']+"#, "$1<redacted>"),
            (#"(?i)((?:api[_-]?key|token|secret|password|credential|experimental_bearer_token)\s*[:=]\s*[\"']?)[^\"'\s,;}]+(\"?)"#, "$1<redacted>$2"),
            (#"(?i)((?:cookie|set-cookie)\s*:\s*)[^\r\n]+"#, "$1<redacted>"),
            (#"(?i)([?&](?:api[_-]?key|token|secret|password|credential|auth)=)[^&#\s]+"#, "$1<redacted>"),
            (#"(?i)(https?://)[^/@\s]+:[^/@\s]+@"#, "$1<redacted>@"),
            (#"(?i)(https?://)(?:[^/@\s]+@)?([^/\s?#]+)(?:/[^\s]*)?"#, "$1$2/<redacted-path>"),
            (#"sk-[A-Za-z0-9_\-]{12,}"#, "<redacted-api-key>"),
            (#"(?i)((?:--?)(?:api[_-]?key|token|secret|password|credential|auth-user-pass|http-proxy-user-pass)(?:=|\s+))(?:\"[^\"]*\"|'[^']*'|[^\s]+)"#, "$1<redacted>"),
            (#"(?i)(\bauth-user-pass\s+)(?:\"[^\"]*\"|'[^']*'|[^\s]+)"#, "$1<redacted>")
        ]
        for (pattern, replacement) in replacements {
            output = output.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        output = output.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
        output = output.replacingOccurrences(
            of: #"/Users/[^/\s]+"#,
            with: "~",
            options: .regularExpression
        )
        return output
    }

    private static func cleanup(_ workspace: NetworkDiagnosticReportWorkspace?) {
        guard let workspace else { return }
        try? FileManager.default.removeItem(at: workspace.stagingRootURL)
        try? FileManager.default.removeItem(at: workspace.archiveURL)
    }

    private static func runOnUtilityQueue<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let task = Task.detached(priority: .utility) {
            try operation()
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func runCommand(
        executable: String,
        arguments: [String]
    ) -> DiagnosticCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "dou-clash-diagnostic-command-\(UUID().uuidString).log")

        do {
            try Data().write(to: outputURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: outputURL.path
            )
            let outputHandle = try FileHandle(forWritingTo: outputURL)
            defer { try? outputHandle.close() }
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = outputHandle
            process.standardError = outputHandle
            try process.run()
            process.waitUntilExit()
            let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
            try? FileManager.default.removeItem(at: outputURL)
            return DiagnosticCommandResult(
                exitCode: process.terminationStatus,
                output: output,
                error: ""
            )
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            return DiagnosticCommandResult(exitCode: -1, output: "", error: error.localizedDescription)
        }
    }
}

private struct DiagnosticCommandResult: Sendable {
    let exitCode: Int32
    let output: String
    let error: String

    var succeeded: Bool { exitCode == 0 }

    var summary: String {
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if succeeded {
            return detail.isEmpty ? "命令成功，无输出" : detail
        }
        return detail.isEmpty ? (error.isEmpty ? "退出码 \(exitCode)" : error) : detail
    }
}

private enum NetworkDiagnosticReportError: LocalizedError {
    case compressionFailed
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            "压缩诊断报告失败，请重试"
        case .generationFailed:
            "生成诊断报告失败，请重试"
        }
    }
}
