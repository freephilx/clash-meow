import Foundation

enum ClashMeowProfileKind: String, Codable, Equatable {
    case local
    case remote
}

struct ClashMeowProfileSummary: Identifiable, Equatable {
    let id: String
    let name: String
    let fileURL: URL
    let sourceDescription: String
    let updatedAt: Date?
    let isCurrent: Bool
    let kind: ClashMeowProfileKind
    let remoteURL: URL?
    let useProxy: Bool
    let subscriptionUserInfo: SubscriptionUserInfo?
}

struct SubscriptionUserInfo: Codable, Equatable {
    let upload: Int
    let download: Int
    let total: Int
    let expire: Int?

    var used: Int {
        upload + download
    }

    var progress: Double? {
        guard total > 0 else { return nil }
        return min(max(Double(used) / Double(total), 0), 1)
    }
}

struct ProfileRepository {
    static var defaultSubscriptionUserAgent: String {
        "ClashMeow/\(AppInfo.version) (clash.meta)"
    }

    static let fallbackSubscriptionUserAgents = [
        "ClashMetaForAndroid/2.10.1",
        "clash-verge/v1.7.7",
        "clash.meta",
        "ClashforWindows/0.20.39",
        "ClashX Pro/1.118.1.1",
        "mihomo/1.9.27"
    ]

    private struct ProfileMetadata: Codable {
        var id: String
        var name: String
        var kind: ClashMeowProfileKind
        var remoteURLString: String?
        var updatedAt: Date?
        var useProxy: Bool
        var subscriptionUserInfo: SubscriptionUserInfo?

        var remoteURL: URL? {
            remoteURLString.flatMap(URL.init(string:))
        }
    }

    private let mihomoConfigsDirectory: URL
    private let activeConfigFile: URL
    private let currentProfileFile: URL
    private let metadataFile: URL
    private let logsDirectory: URL

    init(configDirectory: URL, activeConfigFile: URL, logsDirectory: URL? = nil) {
        self.mihomoConfigsDirectory = configDirectory
            .appending(path: "configs", directoryHint: .isDirectory)
            .appending(path: "mihomo", directoryHint: .isDirectory)
        self.activeConfigFile = activeConfigFile
        self.currentProfileFile = mihomoConfigsDirectory.appending(path: "current.txt")
        self.metadataFile = mihomoConfigsDirectory.appending(path: "profiles-metadata.json")
        self.logsDirectory = logsDirectory
            ?? configDirectory
                .appending(path: "runtime", directoryHint: .isDirectory)
                .appending(path: "logs", directoryHint: .isDirectory)
    }

    func listProfiles() throws -> [ClashMeowProfileSummary] {
        try prepareStorage()
        let currentID = try currentProfileID()
        let metadata = try loadMetadata()
        return try profileFileURLs()
            .map { url in
                let id = url.deletingPathExtension().lastPathComponent
                return try summary(for: id, url: url, metadata: metadata[id], currentID: currentID)
            }
            .sorted(by: profileSort)
    }

    @discardableResult
    func importLocalProfile(from url: URL) throws -> ClashMeowProfileSummary {
        let yaml = try String(contentsOf: url, encoding: .utf8)
        try validateProfileYAML(yaml)
        let name = url.deletingPathExtension().lastPathComponent
        let id = stableProfileID(for: name)
        let destination = profileURL(for: id)
        try prepareStorage()
        try yaml.write(to: destination, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: ruleOverrideURL(for: id))
        var metadata = try loadMetadata()
        metadata[id] = ProfileMetadata(
            id: id,
            name: name,
            kind: .local,
            remoteURLString: nil,
            updatedAt: Date(),
            useProxy: false,
            subscriptionUserInfo: nil
        )
        try saveMetadata(metadata)
        try activateProfile(id: id)
        return try summary(for: id, url: destination, metadata: metadata[id], currentID: id)
    }

    @discardableResult
    func createBlankLocalProfile() throws -> ClashMeowProfileSummary {
        let name = "未命名"
        let id = stableProfileID(for: name)
        let destination = profileURL(for: id)
        try prepareStorage()
        try "".write(to: destination, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: ruleOverrideURL(for: id))
        var metadata = try loadMetadata()
        metadata[id] = ProfileMetadata(
            id: id,
            name: name,
            kind: .local,
            remoteURLString: nil,
            updatedAt: Date(),
            useProxy: false,
            subscriptionUserInfo: nil
        )
        try saveMetadata(metadata)
        return try summary(for: id, url: destination, metadata: metadata[id], currentID: try currentProfileID())
    }

    @discardableResult
    func importRemoteProfile(from url: URL, useProxy: Bool, proxyPort: Int?) async throws -> ClashMeowProfileSummary {
        let document = try await fetchRemoteProfile(from: url, useProxy: useProxy, proxyPort: proxyPort)
        try validateProfileYAML(document.yaml)
        let name = document.name
        let id = stableProfileID(for: name)
        let destination = profileURL(for: id)
        try prepareStorage()
        try document.yaml.write(to: destination, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: ruleOverrideURL(for: id))
        var metadata = try loadMetadata()
        metadata[id] = ProfileMetadata(
            id: id,
            name: name,
            kind: .remote,
            remoteURLString: url.absoluteString,
            updatedAt: Date(),
            useProxy: useProxy,
            subscriptionUserInfo: document.subscriptionUserInfo
        )
        try saveMetadata(metadata)
        try activateProfile(id: id)
        return try summary(for: id, url: destination, metadata: metadata[id], currentID: id)
    }

    @discardableResult
    func refreshRemoteProfile(id: String, proxyPort: Int?) async throws -> ClashMeowProfileSummary {
        let metadata = try loadMetadata()
        guard let item = metadata[id], item.kind == .remote, let remoteURL = item.remoteURL else {
            throw ProfileRepositoryError.notRemoteProfile
        }

        let document = try await fetchRemoteProfile(from: remoteURL, useProxy: item.useProxy, proxyPort: proxyPort)
        try validateProfileYAML(document.yaml)
        let destination = profileURL(for: id)
        try document.yaml.write(to: destination, atomically: true, encoding: .utf8)

        var nextMetadata = metadata
        let nextName = retainedProfileName(
            currentName: item.name,
            refreshedName: document.name,
            remoteURL: remoteURL
        )
        nextMetadata[id] = ProfileMetadata(
            id: id,
            name: nextName,
            kind: .remote,
            remoteURLString: remoteURL.absoluteString,
            updatedAt: Date(),
            useProxy: item.useProxy,
            subscriptionUserInfo: document.subscriptionUserInfo
        )
        try saveMetadata(nextMetadata)

        if try currentProfileID() == id {
            try activateProfile(id: id)
        }
        return try summary(for: id, url: destination, metadata: nextMetadata[id], currentID: try currentProfileID())
    }

    func activateProfile(id: String) throws {
        try prepareStorage()
        let source = profileURL(for: id)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ProfileRepositoryError.profileNotFound
        }
        try writeRuntimeConfig(try runtimeYAML(for: id), profileID: id, reason: "activateProfile")
        try id.write(to: currentProfileFile, atomically: true, encoding: .utf8)
    }

    func restoreSelectedProfileIfNeeded() throws {
        try prepareStorage()
        let selectedID: String
        if let storedSelectedID = ProfileSelectionPreference.selectedProfileID,
           !storedSelectedID.isEmpty {
            selectedID = storedSelectedID
        } else {
            selectedID = "default"
            ProfileSelectionPreference.setSelectedProfileID(selectedID)
        }
        guard FileManager.default.fileExists(atPath: profileURL(for: selectedID).path) else {
            ProfileSelectionPreference.setSelectedProfileID(nil)
            return
        }
        let runtimeYAML = try runtimeYAML(for: selectedID)
        if try currentProfileID() != selectedID {
            logRuntimeConfig("冷启动恢复选中 Profile，准备重写 runtime config profile=\(selectedID)")
            try writeRuntimeConfig(runtimeYAML, profileID: selectedID, reason: "startupSelectedProfile")
            try selectedID.write(to: currentProfileFile, atomically: true, encoding: .utf8)
        } else if try activeConfigNeedsRefresh(expectedYAML: runtimeYAML) {
            logRuntimeConfig("冷启动检测到 runtime config 过期，准备重写 profile=\(selectedID)")
            try writeRuntimeConfig(runtimeYAML, profileID: selectedID, reason: "startupRefresh")
        } else {
            logRuntimeConfig("冷启动 runtime config 已是最新 profile=\(selectedID) path=\(activeConfigFile.path)")
        }
    }

    func profileFileURL(id: String) -> URL {
        profileURL(for: id)
    }

    func addRuleOverride(profileID: String, rule: String, placement: RuleOverridePlacement) throws {
        try updateRuleOverrides(profileID: profileID, reason: "ruleOverride") { overrides in
            overrides.add(rule, placement: placement)
        }
    }

    func setRuleDeletedOverride(profileID: String, rule: String, isDeleted: Bool) throws {
        try updateRuleOverrides(profileID: profileID, reason: "ruleDeleteOverride") { overrides in
            overrides.setDeleted(rule, isDeleted: isDeleted)
        }
    }

    private func updateRuleOverrides(
        profileID: String,
        reason: String,
        mutate: (inout RuleOverrideSet) -> Void
    ) throws {
        try prepareStorage()
        guard FileManager.default.fileExists(atPath: profileURL(for: profileID).path) else {
            throw ProfileRepositoryError.profileNotFound
        }
        var overrides = try loadRuleOverrides(for: profileID)
        mutate(&overrides)
        let overrideYAML = try overrides.renderedYAML()
        if overrideYAML.isEmpty {
            try? FileManager.default.removeItem(at: ruleOverrideURL(for: profileID))
        } else {
            try overrideYAML.write(to: ruleOverrideURL(for: profileID), atomically: true, encoding: .utf8)
        }
        if try currentProfileID() == profileID {
            try writeRuntimeConfig(try runtimeYAML(for: profileID), profileID: profileID, reason: reason)
        }
    }

    private func activeConfigNeedsRefresh(expectedYAML: String) throws -> Bool {
        guard FileManager.default.fileExists(atPath: activeConfigFile.path) else { return true }
        let activeYAML = try String(contentsOf: activeConfigFile, encoding: .utf8)
        return activeYAML != expectedYAML
    }

    private func writeRuntimeConfig(_ yaml: String, profileID: String, reason: String) throws {
        try FileManager.default.createDirectory(
            at: activeConfigFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try yaml.write(to: activeConfigFile, atomically: true, encoding: .utf8)
        let config = MihomoConfig.parsed(from: yaml)
        let mixedPort = config.mixedPort.map(String.init) ?? "-"
        let controller = config.externalController ?? "-"
        logRuntimeConfig(
            "已写入 runtime config reason=\(reason) profile=\(profileID) path=\(activeConfigFile.path) mixed-port=\(mixedPort) external-controller=\(controller) bytes=\(Data(yaml.utf8).count)"
        )
    }

    private func logRuntimeConfig(_ message: String) {
        AppLogSupport.info(message, module: "RuntimeConfig", logsDirectory: logsDirectory)
        #if DEBUG
        print("[RuntimeConfig] \(message)")
        #endif
    }

    private func runtimeYAML(for id: String) throws -> String {
        let source = profileURL(for: id)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ProfileRepositoryError.profileNotFound
        }
        let profileYAML = try String(contentsOf: source, encoding: .utf8)
        return try RuntimeConfigBuilder.build(profileYAML: profileYAML, ruleOverrides: loadRuleOverrides(for: id))
    }

    @discardableResult
    func deleteProfile(id: String) throws -> Bool {
        guard id != "default" else {
            throw ProfileRepositoryError.cannotDeleteDefault
        }

        let wasCurrent = try currentProfileID() == id
        try? FileManager.default.removeItem(at: profileURL(for: id))
        try? FileManager.default.removeItem(at: ruleOverrideURL(for: id))
        var metadata = try loadMetadata()
        metadata[id] = nil
        try saveMetadata(metadata)

        if wasCurrent, let nextID = try listProfiles().first?.id {
            try activateProfile(id: nextID)
        }
        return wasCurrent
    }

    private func prepareStorage() throws {
        try FileManager.default.createDirectory(at: mihomoConfigsDirectory, withIntermediateDirectories: true)
        let defaultURL = profileURL(for: "default")
        if !FileManager.default.fileExists(atPath: defaultURL.path) {
            try defaultProfileContent().write(to: defaultURL, atomically: true, encoding: .utf8)
        } else if let defaultContent = try? String(contentsOf: defaultURL, encoding: .utf8),
                  !Self.isLikelyMihomoYAML(defaultContent) {
            try defaultProfileContent().write(to: defaultURL, atomically: true, encoding: .utf8)
        }
        if !FileManager.default.fileExists(atPath: currentProfileFile.path) {
            try "default".write(to: currentProfileFile, atomically: true, encoding: .utf8)
        }
        var metadata = try loadMetadata()
        if metadata["default"] == nil {
            metadata["default"] = ProfileMetadata(
                id: "default",
                name: "Default",
                kind: .local,
                remoteURLString: nil,
                updatedAt: modificationDate(for: defaultURL),
                useProxy: false,
                subscriptionUserInfo: nil
            )
            try saveMetadata(metadata)
        }
    }

    private func fetchRemoteProfile(
        from url: URL,
        useProxy: Bool,
        proxyPort: Int?
    ) async throws -> (yaml: String, name: String, subscriptionUserInfo: SubscriptionUserInfo?) {
        let configuration = URLSessionConfiguration.ephemeral
        if useProxy {
            guard let proxyPort, proxyPort > 0 else {
                throw ProfileRepositoryError.proxyUnavailable
            }
            configuration.connectionProxyDictionary = [
                "HTTPEnable": true,
                "HTTPProxy": "127.0.0.1",
                "HTTPPort": proxyPort,
                "HTTPSEnable": true,
                "HTTPSProxy": "127.0.0.1",
                "HTTPSPort": proxyPort
            ]
        }

        let session = URLSession(configuration: configuration)
        var bestDocument: (data: Data, response: URLResponse, yaml: String)?
        var bestProxyCount = -1
        var lastStatusCode: Int?
        let primaryUserAgent = Self.defaultSubscriptionUserAgent
        let fallbackUserAgents = Self.fallbackSubscriptionUserAgents
            .filter { $0 != primaryUserAgent }
        let userAgents = [primaryUserAgent] + fallbackUserAgents

        for (index, userAgent) in userAgents.enumerated() {
            let phase = index == 0 ? "primary" : "fallback"
            let request = subscriptionRequest(for: url, userAgent: userAgent)
            logSubscriptionRequest(request)
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                lastStatusCode = httpResponse.statusCode
                continue
            }
            guard let raw = String(data: data, encoding: .utf8),
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            guard let yaml = try? SubscriptionDocumentNormalizer.normalize(raw) else {
                AppLogSupport.warning(
                    "远程配置响应无法归一化: phase=\(phase) ua=\(userAgent)",
                    module: "Profile",
                    logsDirectory: logsDirectory
                )
                continue
            }
            let proxyCount = SubscriptionDocumentNormalizer.proxyCount(in: yaml)
            AppLogSupport.info(
                "远程配置响应解析完成: phase=\(phase) ua=\(userAgent) nodes=\(proxyCount)",
                module: "Profile",
                logsDirectory: logsDirectory
            )
            if proxyCount > bestProxyCount {
                bestProxyCount = proxyCount
                bestDocument = (data, response, yaml)
            }
            if index == 0, proxyCount > 0 {
                break
            }
        }

        guard let bestDocument else {
            throw ProfileRepositoryError.httpStatus(lastStatusCode ?? -1)
        }
        let yaml = bestDocument.yaml
        let response = bestDocument.response
        try validateProfileYAML(yaml)
        AppLogSupport.info(
            "已选择远程配置响应: nodes=\(bestProxyCount)",
            module: "Profile",
            logsDirectory: logsDirectory
        )
        let name = remoteProfileName(from: response, fallbackURL: url)
        let subscriptionUserInfo = subscriptionUserInfo(from: response)
        return (yaml, name, subscriptionUserInfo)
    }

    private func subscriptionRequest(for url: URL, userAgent: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/yaml, application/yaml, application/octet-stream, */*", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        return request
    }

    private func logSubscriptionRequest(_ request: URLRequest) {
        guard let url = request.url else { return }
        let headers = request.allHTTPHeaderFields ?? [:]
        let headerArguments = headers
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .flatMap { ["-H", "\($0.key): \($0.value)"] }
        let command = shellCommand(
            executable: "curl",
            arguments: ["-L", "--compressed"] + headerArguments + [url.absoluteString]
        )
        AppLogSupport.info("下载远程配置请求: \(command)", module: "Profile", logsDirectory: logsDirectory)
    }

    private func shellCommand(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(shellEscaped).joined(separator: " ")
    }

    private func shellEscaped(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func subscriptionUserInfo(from response: URLResponse) -> SubscriptionUserInfo? {
        guard let httpResponse = response as? HTTPURLResponse,
              let value = headerValue(suffix: "subscription-userinfo", in: httpResponse.allHeaderFields) else {
            return nil
        }
        return parseSubscriptionUserInfo(value)
    }

    private func headerValue(suffix: String, in headers: [AnyHashable: Any]) -> String? {
        headers.first { key, _ in
            String(describing: key).lowercased().hasSuffix(suffix)
        }
        .map { String(describing: $0.value) }
    }

    private func parseSubscriptionUserInfo(_ value: String) -> SubscriptionUserInfo? {
        let pairs = value
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { item -> (String, Int)? in
                let pieces = item.split(separator: "=", maxSplits: 1).map(String.init)
                guard pieces.count == 2,
                      let number = Int(pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    return nil
                }
                return (pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), number)
            }
        let values = pairs.reduce(into: [String: Int]()) { result, pair in
            result[pair.0] = pair.1
        }
        guard let upload = values["upload"],
              let download = values["download"],
              let total = values["total"] else {
            return nil
        }
        return SubscriptionUserInfo(upload: upload, download: download, total: total, expire: values["expire"])
    }

    private func remoteProfileName(from response: URLResponse, fallbackURL: URL) -> String {
        if let httpResponse = response as? HTTPURLResponse,
           let filename = filename(from: httpResponse.allHeaderFields),
           !filename.isEmpty {
            return URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        }
        return fallbackURL.host ?? "Remote Profile"
    }

    private func filename(from headers: [AnyHashable: Any]) -> String? {
        guard let value = headerValue(suffix: "content-disposition", in: headers) else {
            return nil
        }
        if let range = value.range(of: "filename*=UTF-8''", options: .caseInsensitive) {
            return String(value[range.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                .removingPercentEncoding
        }
        guard let range = value.range(of: "filename=", options: .caseInsensitive) else {
            return nil
        }
        return String(value[range.upperBound...])
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    }

    private func retainedProfileName(currentName: String, refreshedName: String, remoteURL: URL) -> String {
        let urlFallbackName = remoteURL.deletingPathExtension().lastPathComponent
        guard !refreshedName.isEmpty,
              !urlFallbackName.isEmpty,
              currentName == urlFallbackName else {
            return currentName
        }
        return refreshedName
    }

    private func profileFileURLs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: mihomoConfigsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            let name = url.lastPathComponent.lowercased()
            return ["yaml", "yml"].contains(url.pathExtension.lowercased())
                && !name.hasSuffix(".rules.yaml")
                && !name.hasSuffix(".rules.yml")
        }
    }

    private func profileURL(for id: String) -> URL {
        mihomoConfigsDirectory.appending(path: "\(id).yaml")
    }

    private func ruleOverrideURL(for id: String) -> URL {
        mihomoConfigsDirectory.appending(path: "\(id).rules.yaml")
    }

    private func loadRuleOverrides(for id: String) throws -> RuleOverrideSet {
        let url = ruleOverrideURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return RuleOverrideSet() }
        return try RuleOverrideSet(yaml: String(contentsOf: url, encoding: .utf8))
    }

    private func currentProfileID() throws -> String {
        guard FileManager.default.fileExists(atPath: currentProfileFile.path) else {
            return "default"
        }
        let value = try String(contentsOf: currentProfileFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "default" : value
    }

    private func loadMetadata() throws -> [String: ProfileMetadata] {
        guard FileManager.default.fileExists(atPath: metadataFile.path) else {
            return [:]
        }
        let data = try Data(contentsOf: metadataFile)
        return try JSONDecoder().decode([String: ProfileMetadata].self, from: data)
    }

    private func saveMetadata(_ metadata: [String: ProfileMetadata]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: metadataFile, options: .atomic)
    }

    private func summary(
        for id: String,
        url: URL,
        metadata: ProfileMetadata?,
        currentID: String
    ) throws -> ClashMeowProfileSummary {
        let kind = metadata?.kind ?? .local
        let remoteURL = metadata?.remoteURL
        return ClashMeowProfileSummary(
            id: id,
            name: metadata?.name ?? displayName(for: url),
            fileURL: url,
            sourceDescription: sourceDescription(kind: kind, remoteURL: remoteURL),
            updatedAt: metadata?.updatedAt ?? modificationDate(for: url),
            isCurrent: id == currentID,
            kind: kind,
            remoteURL: remoteURL,
            useProxy: metadata?.useProxy ?? false,
            subscriptionUserInfo: metadata?.subscriptionUserInfo
        )
    }

    private func sourceDescription(kind: ClashMeowProfileKind, remoteURL: URL?) -> String {
        switch kind {
        case .local:
            "Local YAML"
        case .remote:
            remoteURL?.absoluteString ?? "Remote subscription"
        }
    }

    private func profileSort(_ left: ClashMeowProfileSummary, _ right: ClashMeowProfileSummary) -> Bool {
        if left.id == "default" { return true }
        if right.id == "default" { return false }
        if left.isCurrent != right.isCurrent { return left.isCurrent }
        return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }

    private func displayName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name == "default" ? "Default" : name.replacingOccurrences(of: "-", with: " ")
    }

    private func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func stableProfileID(for name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let slug = name
            .lowercased()
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let base = slug.isEmpty ? "profile" : slug
        return "\(base)-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func defaultProfileContent() throws -> String {
        if let url = AppResources.url(forResource: "sampleConfig", withExtension: "yaml") {
            return try String(contentsOf: url, encoding: .utf8)
        }
        return """
        mixed-port: 7890
        allow-lan: false
        mode: rule
        log-level: info
        ipv6: false
        find-process-mode: always
        external-controller: 127.0.0.1:9090
        secret: ""

        proxies: []

        proxy-groups:
          - name: Proxy
            type: select
            proxies:
              - DIRECT

        rules:
          - MATCH,DIRECT
        """
    }

    private func validateProfileYAML(_ yaml: String) throws {
        guard Self.isLikelyMihomoYAML(yaml) else {
            throw ProfileRepositoryError.invalidYAML
        }
    }

    static func isLikelyMihomoYAML(_ yaml: String) -> Bool {
        let meaningfulLines = yaml
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard !meaningfulLines.isEmpty else { return false }

        let requiredTopLevelKeys = ["proxies:", "proxy-groups:", "rules:"]
        if requiredTopLevelKeys.contains(where: { key in meaningfulLines.contains(where: { $0.hasPrefix(key) }) }) {
            return true
        }

        let configKeys = [
            "port:",
            "socks-port:",
            "mixed-port:",
            "redir-port:",
            "tproxy-port:",
            "mode:",
            "log-level:",
            "external-controller:",
            "tun:"
        ]
        return configKeys.contains { key in
            meaningfulLines.contains { $0.hasPrefix(key) }
        }
    }
}

enum ProfileRepositoryError: LocalizedError {
    case cannotDeleteDefault
    case emptyDocument
    case httpStatus(Int)
    case invalidYAML
    case notRemoteProfile
    case profileNotFound
    case proxyUnavailable

    var errorDescription: String? {
        switch self {
        case .cannotDeleteDefault:
            "默认配置不能删除。"
        case .emptyDocument:
            "配置文件内容为空。"
        case .httpStatus(let status):
            "远程配置下载失败（HTTP \(status)）。"
        case .invalidYAML:
            "配置内容格式无效。请确认远程配置链接有效，或导入兼容格式的 YAML。"
        case .notRemoteProfile:
            "该配置没有远程配置 URL。"
        case .profileNotFound:
            "找不到配置文件。"
        case .proxyUnavailable:
            "请先启动内核，再通过本机网络获取远程配置。"
        }
    }
}
