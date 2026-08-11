import Foundation
import Testing
@testable import DouClash

enum AppPreferenceStoreTestIsolation {
    private static let lock = NSLock()

    static func withTemporaryDirectory<T>(
        prefix: String,
        _ body: (URL) throws -> T
    ) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        AppPreferenceStore.configDirectoryOverrideForTesting = directory
        defer {
            AppPreferenceStore.configDirectoryOverrideForTesting = nil
            try? FileManager.default.removeItem(at: directory)
        }
        return try body(directory)
    }
}

@Suite(.serialized)
struct AppPreferenceStoreTests {
    @Test func preferencesPersistToConfigDirectoryPreferencesFile() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-preferences") { directory in
            SystemProxyPreference.setEnabled(true)
            SystemProxyUserPreference.setEnabled(true)
            TunPreference.setEnabled(true)
            TunUserPreference.setEnabled(true)
            try AppPreferenceStore.updateMihomoSettings { settings in
                settings.selectedProfileID = "remote-profile"
            }
            CoreAutoStartManager.setEnabled(false)
            InternetLatencyPreference.testURLsText = "https://example.com/generate_204"
            InternetLatencyPreference.dnsDomain = "example.com"
            InternetLatencyPreference.timeoutSeconds = 8

            let data = try Data(contentsOf: directory.appending(path: "preferences.json"))
            let preferences = try JSONDecoder().decode(AppPreferenceStore.Preferences.self, from: data)

            #expect(preferences.systemProxyEnabled == true)
            #expect(preferences.systemProxyUserEnabled == true)
            #expect(preferences.tunEnabled == true)
            #expect(preferences.tunUserEnabled == true)
            #expect(preferences.mihomoSettings?.selectedProfileID == "remote-profile")
            #expect(preferences.coreEnabled == false)
            #expect(preferences.internetLatencyTestURLs == "https://example.com/generate_204")
            #expect(preferences.internetLatencyDNSDomain == "example.com")
            #expect(preferences.internetLatencyTimeoutSeconds == 8)
        }
    }

    @Test func corruptPreferencesFileUsesDefaults() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-preferences") { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("not-json".utf8)
                .write(to: directory.appending(path: "preferences.json"), options: .atomic)

            #expect(AppPreferenceStore.read().coreEnabled == nil)
        }
    }

    @Test func internetLatencyPreferencesSanitizeValues() {
        AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-preferences") { _ in
            InternetLatencyPreference.testURLsText = "not-a-url, https://one.example.com\nhttp://two.example.com"
            InternetLatencyPreference.dnsDomain = "  example.org  "
            InternetLatencyPreference.timeoutSeconds = 20

            let configuration = InternetLatencyPreference.configuration

            #expect(configuration.httpTestURLs.map(\.absoluteString) == ["https://one.example.com", "http://two.example.com"])
            #expect(configuration.dnsDomain == "example.org")
            #expect(configuration.timeoutSeconds == 10)
        }
    }

    @Test func actualNetworkStateCanChangeWithoutOverwritingUserState() {
        AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-preferences") { _ in
            SystemProxyUserPreference.setEnabled(true)
            SystemProxyPreference.setEnabled(false)
            TunUserPreference.setEnabled(true)
            TunPreference.setEnabled(false)

            let preferences = AppPreferenceStore.read()
            #expect(preferences.systemProxyUserEnabled == true)
            #expect(preferences.systemProxyEnabled == false)
            #expect(preferences.tunUserEnabled == true)
            #expect(preferences.tunEnabled == false)
        }
    }

    @Test func profileRepositoryRestoresLastUserSelectedProfileOnStartup() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-profiles") { directory in
            let activeConfig = Self.runtimeConfigURL(in: directory)
            let repository = ProfileRepository(configDirectory: directory, activeConfigFile: activeConfig)
            _ = try repository.listProfiles()

            let mihomoConfigsDirectory = Self.mihomoConfigsURL(in: directory)
            let selectedID = "selected-profile"
            let selectedYAML = Self.profileYAML(groupName: "Selected")
            try selectedYAML.write(
                to: mihomoConfigsDirectory.appending(path: "\(selectedID).yaml"),
                atomically: true,
                encoding: .utf8
            )
            try AppPreferenceStore.updateMihomoSettings { settings in
                settings.selectedProfileID = selectedID
            }

            try repository.restoreSelectedProfileIfNeeded()

            let activeYAML = try String(contentsOf: activeConfig, encoding: .utf8)

            #expect(activeYAML.contains("name: Selected"))
            #expect(activeYAML.contains("mixed-port: 7890"))
            #expect(activeYAML.contains("external-controller: 127.0.0.1:9090"))
            #expect(activeYAML.contains("tun:"))
            #expect(AppPreferenceStore.readMihomoSettings().selectedProfileID == selectedID)
            #expect(!FileManager.default.fileExists(atPath: mihomoConfigsDirectory.appending(path: "current.txt").path))
        }
    }

    @Test func profileRepositoryRefreshesStaleActiveConfigOnStartup() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-profiles") { directory in
            let activeConfig = Self.runtimeConfigURL(in: directory)
            let repository = ProfileRepository(configDirectory: directory, activeConfigFile: activeConfig)
            _ = try repository.listProfiles()

            let mihomoConfigsDirectory = Self.mihomoConfigsURL(in: directory)
            let selectedID = "selected-profile"
            try Self.profileYAML(groupName: "Selected", mixedPort: 7891).write(
                to: mihomoConfigsDirectory.appending(path: "\(selectedID).yaml"),
                atomically: true,
                encoding: .utf8
            )
            try FileManager.default.createDirectory(
                at: activeConfig.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.profileYAML(groupName: "Selected", mixedPort: 7890).write(
                to: activeConfig,
                atomically: true,
                encoding: .utf8
            )
            try AppPreferenceStore.updateMihomoSettings { settings in
                settings.selectedProfileID = selectedID
            }

            try repository.restoreSelectedProfileIfNeeded()
            AppLogSupport.flush()

            let activeYAML = try String(contentsOf: activeConfig, encoding: .utf8)
            let appLog = try String(contentsOf: Self.appLogURL(in: directory), encoding: .utf8)
            #expect(activeYAML.contains("mixed-port: 7891"))
            #expect(!activeYAML.contains("mixed-port: 7890"))
            #expect(appLog.contains("[RuntimeConfig]"))
            #expect(appLog.contains("reason=startupRefresh"))
            #expect(appLog.contains("mixed-port=7891"))
        }
    }

    @Test func profileRepositoryRuleOverrideUpdatesRuntimeConfig() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-profiles") { directory in
            let activeConfig = Self.runtimeConfigURL(in: directory)
            let repository = ProfileRepository(configDirectory: directory, activeConfigFile: activeConfig)
            _ = try repository.listProfiles()

            let mihomoConfigsDirectory = Self.mihomoConfigsURL(in: directory)
            let selectedID = "selected-profile"
            try Self.profileYAML(groupName: "Selected").write(
                to: mihomoConfigsDirectory.appending(path: "\(selectedID).yaml"),
                atomically: true,
                encoding: .utf8
            )
            try repository.activateProfile(id: selectedID)

            try repository.addRuleOverride(
                profileID: selectedID,
                rule: "DOMAIN-SUFFIX,example.com,Proxy",
                placement: .prepend
            )

            let activeYAML = try String(contentsOf: activeConfig, encoding: .utf8)
            let metadata = AppPreferenceStore.readMihomoSettings().profiles.first { $0.id == selectedID }
            #expect(activeYAML.contains("DOMAIN-SUFFIX,example.com,Proxy"))
            #expect(metadata?.ruleOverrides.prepend == ["DOMAIN-SUFFIX,example.com,Proxy"])
            #expect(!FileManager.default.fileExists(atPath: mihomoConfigsDirectory.appending(path: "\(selectedID).rules.yaml").path))
            #expect(!(try repository.listProfiles()).contains { $0.id == "selected-profile.rules" })
        }
    }

    @Test func profileRepositoryRuleDeleteOverrideUpdatesRuntimeConfig() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-profiles") { directory in
            let activeConfig = Self.runtimeConfigURL(in: directory)
            let repository = ProfileRepository(configDirectory: directory, activeConfigFile: activeConfig)
            _ = try repository.listProfiles()

            let mihomoConfigsDirectory = Self.mihomoConfigsURL(in: directory)
            let selectedID = "selected-profile"
            try Self.profileYAML(groupName: "Selected", extraRule: "DOMAIN-SUFFIX,example.com,Proxy").write(
                to: mihomoConfigsDirectory.appending(path: "\(selectedID).yaml"),
                atomically: true,
                encoding: .utf8
            )
            try repository.activateProfile(id: selectedID)

            try repository.setRuleDeletedOverride(
                profileID: selectedID,
                rule: "DOMAIN-SUFFIX,example.com,Proxy",
                isDeleted: true
            )

            let disabledActiveYAML = try String(contentsOf: activeConfig, encoding: .utf8)
            let disabledMetadata = AppPreferenceStore.readMihomoSettings().profiles.first { $0.id == selectedID }
            #expect(!disabledActiveYAML.contains("DOMAIN-SUFFIX,example.com,Proxy"))
            #expect(disabledMetadata?.ruleOverrides.delete == ["DOMAIN-SUFFIX,example.com,Proxy"])

            try repository.setRuleDeletedOverride(
                profileID: selectedID,
                rule: "DOMAIN-SUFFIX,example.com,Proxy",
                isDeleted: false
            )

            let enabledActiveYAML = try String(contentsOf: activeConfig, encoding: .utf8)
            let enabledMetadata = AppPreferenceStore.readMihomoSettings().profiles.first { $0.id == selectedID }
            #expect(enabledActiveYAML.contains("DOMAIN-SUFFIX,example.com,Proxy"))
            #expect(enabledMetadata?.ruleOverrides.isEmpty == true)
            #expect(!FileManager.default.fileExists(atPath: mihomoConfigsDirectory.appending(path: "\(selectedID).rules.yaml").path))
        }
    }

    @Test func profileRepositoryRuleReplacementUpdatesOverridesAndRuntimeConfig() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-profiles") { directory in
            let activeConfig = Self.runtimeConfigURL(in: directory)
            let repository = ProfileRepository(configDirectory: directory, activeConfigFile: activeConfig)
            _ = try repository.listProfiles()

            let selectedID = "selected-profile"
            try Self.profileYAML(
                groupName: "Selected",
                extraRule: "DOMAIN-SUFFIX,old.example.com,Proxy"
            ).write(
                to: Self.mihomoConfigsURL(in: directory).appending(path: "\(selectedID).yaml"),
                atomically: true,
                encoding: .utf8
            )
            try repository.activateProfile(id: selectedID)

            try repository.replaceRuleOverride(
                profileID: selectedID,
                oldRule: "DOMAIN-SUFFIX,old.example.com,Proxy",
                newRule: "DOMAIN-SUFFIX,new.example.com,DIRECT"
            )

            let activeYAML = try String(contentsOf: activeConfig, encoding: .utf8)
            let overrides = try repository.ruleOverrides(profileID: selectedID)
            #expect(activeYAML.contains("DOMAIN-SUFFIX,new.example.com,DIRECT"))
            #expect(!activeYAML.contains("DOMAIN-SUFFIX,old.example.com,Proxy"))
            #expect(overrides.prepend == ["DOMAIN-SUFFIX,new.example.com,DIRECT"])
            #expect(overrides.delete == ["DOMAIN-SUFFIX,old.example.com,Proxy"])
        }
    }

    @Test func profileRepositoryFallsBackFromMissingSelectedProfileOnStartup() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-profiles") { directory in
            let repository = ProfileRepository(
                configDirectory: directory,
                activeConfigFile: Self.runtimeConfigURL(in: directory)
            )
            _ = try repository.listProfiles()
            try AppPreferenceStore.updateMihomoSettings { settings in
                settings.selectedProfileID = "missing-profile"
            }

            try repository.restoreSelectedProfileIfNeeded()

            #expect(AppPreferenceStore.readMihomoSettings().selectedProfileID == "default")
        }
    }

    @Test func profileRepositoryInitializesDefaultSelectionWhenMissing() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-profiles") { directory in
            let repository = ProfileRepository(
                configDirectory: directory,
                activeConfigFile: Self.runtimeConfigURL(in: directory)
            )
            _ = try repository.listProfiles()
            let mihomoConfigsDirectory = Self.mihomoConfigsURL(in: directory)
            try Self.profileYAML(groupName: "IgnoredCurrent").write(
                to: mihomoConfigsDirectory.appending(path: "ignored-current.yaml"),
                atomically: true,
                encoding: .utf8
            )
            let legacyCurrent = mihomoConfigsDirectory.appending(path: "current.txt")
            let legacyMetadata = mihomoConfigsDirectory.appending(path: "profiles-metadata.json")
            let legacyRules = mihomoConfigsDirectory.appending(path: "ignored-current.rules.yaml")
            try "ignored-current".write(to: legacyCurrent, atomically: true, encoding: .utf8)
            try "legacy-metadata".write(to: legacyMetadata, atomically: true, encoding: .utf8)
            try "delete: []".write(to: legacyRules, atomically: true, encoding: .utf8)

            try repository.restoreSelectedProfileIfNeeded()

            #expect(AppPreferenceStore.readMihomoSettings().selectedProfileID == "default")
            #expect(try String(contentsOf: legacyCurrent, encoding: .utf8) == "ignored-current")
            #expect(try String(contentsOf: legacyMetadata, encoding: .utf8) == "legacy-metadata")
            #expect(try String(contentsOf: legacyRules, encoding: .utf8) == "delete: []")
            #expect(!(try repository.listProfiles()).contains { $0.id == "ignored-current.rules" })
        }
    }

    @Test func invalidProfileActivationKeepsSelectedProfile() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-profiles") { directory in
            let repository = ProfileRepository(
                configDirectory: directory,
                activeConfigFile: Self.runtimeConfigURL(in: directory)
            )
            _ = try repository.listProfiles()

            do {
                try repository.activateProfile(id: "missing-profile")
                Issue.record("Expected missing profile activation to fail")
            } catch {
                #expect(error is ProfileRepositoryError)
            }

            #expect(AppPreferenceStore.readMihomoSettings().selectedProfileID == "default")
        }
    }

    @Test func runtimeConfigIsNotUsedAsDefaultProfileSource() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-profiles") { directory in
            let activeConfig = Self.runtimeConfigURL(in: directory)
            try FileManager.default.createDirectory(
                at: activeConfig.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.profileYAML(groupName: "RuntimeOnly").write(
                to: activeConfig,
                atomically: true,
                encoding: .utf8
            )
            let repository = ProfileRepository(configDirectory: directory, activeConfigFile: activeConfig)

            _ = try repository.listProfiles()

            let defaultProfile = try String(
                contentsOf: Self.mihomoConfigsURL(in: directory).appending(path: "default.yaml"),
                encoding: .utf8
            )
            #expect(!defaultProfile.contains("RuntimeOnly"))
        }
    }

    @Test func profileDirectoryContainsOnlySourceYAMLAfterNormalOperations() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-profiles") { directory in
            let repository = ProfileRepository(
                configDirectory: directory,
                activeConfigFile: Self.runtimeConfigURL(in: directory)
            )
            _ = try repository.listProfiles()
            let createdProfile = try repository.createBlankLocalProfile()

            let filenames = try FileManager.default.contentsOfDirectory(
                atPath: Self.mihomoConfigsURL(in: directory).path
            ).sorted()
            let metadata = AppPreferenceStore.readMihomoSettings().profiles.first {
                $0.id == createdProfile.id
            }

            #expect(filenames == ["\(createdProfile.id).yaml", "default.yaml"].sorted())
            #expect(metadata?.name == createdProfile.name)
            #expect(AppPreferenceStore.readMihomoSettings().selectedProfileID == "default")
        }
    }

    @Test func importingLocalProfileDoesNotSelectItOrRewriteRuntimeConfig() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-local-import") { directory in
            let activeConfig = Self.runtimeConfigURL(in: directory)
            let repository = ProfileRepository(configDirectory: directory, activeConfigFile: activeConfig)
            _ = try repository.listProfiles()
            try repository.restoreSelectedProfileIfNeeded()
            let runtimeBeforeImport = try Data(contentsOf: activeConfig)

            let importDirectory = directory.appending(path: "imports", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: importDirectory, withIntermediateDirectories: true)
            let source = importDirectory.appending(path: "local-added.yaml")
            try Self.profileYAML(groupName: "LocalAdded", mixedPort: 7891).write(
                to: source,
                atomically: true,
                encoding: .utf8
            )

            let imported = try repository.importLocalProfile(from: source)

            #expect(imported.name == "local-added")
            #expect(imported.isCurrent == false)
            #expect(AppPreferenceStore.readMihomoSettings().selectedProfileID == "default")
            #expect(try Data(contentsOf: activeConfig) == runtimeBeforeImport)
            #expect(try repository.listProfiles().first { $0.id == imported.id }?.isCurrent == false)
        }
    }

    @Test func importingRemoteProfileDoesNotSelectItOrRewriteRuntimeConfig() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "dou-clash-remote-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        AppPreferenceStore.configDirectoryOverrideForTesting = directory
        defer {
            AppPreferenceStore.configDirectoryOverrideForTesting = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProfileImportURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let activeConfig = Self.runtimeConfigURL(in: directory)
        let repository = ProfileRepository(
            configDirectory: directory,
            activeConfigFile: activeConfig,
            urlSession: session
        )
        _ = try repository.listProfiles()
        try repository.restoreSelectedProfileIfNeeded()
        let runtimeBeforeImport = try Data(contentsOf: activeConfig)

        let imported = try await repository.importRemoteProfile(
            from: URL(string: "https://profiles.example/download")!,
            useProxy: false,
            proxyPort: nil
        )

        #expect(imported.name == "remote-added")
        #expect(imported.isCurrent == false)
        #expect(AppPreferenceStore.readMihomoSettings().selectedProfileID == "default")
        #expect(try Data(contentsOf: activeConfig) == runtimeBeforeImport)
        #expect(try repository.listProfiles().first { $0.id == imported.id }?.isCurrent == false)
    }

    @Test func rootProfilesDirectoryIsIgnored() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "dou-clash-profiles") { directory in
            let rootProfilesDirectory = directory.appending(path: "profiles", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: rootProfilesDirectory, withIntermediateDirectories: true)
            let ignoredProfile = rootProfilesDirectory.appending(path: "ignored.yaml")
            try Self.profileYAML(groupName: "Ignored").write(
                to: ignoredProfile,
                atomically: true,
                encoding: .utf8
            )
            let repository = ProfileRepository(
                configDirectory: directory,
                activeConfigFile: Self.runtimeConfigURL(in: directory)
            )

            let profiles = try repository.listProfiles()

            #expect(!profiles.contains { $0.id == "ignored" })
            #expect(FileManager.default.fileExists(atPath: ignoredProfile.path))
            #expect(FileManager.default.fileExists(
                atPath: Self.mihomoConfigsURL(in: directory).appending(path: "default.yaml").path
            ))
        }
    }

    private static func profileYAML(groupName: String, mixedPort: Int = 7890, extraRule: String? = nil) -> String {
        let rules = [
            extraRule.map { "  - \($0)" },
            "  - MATCH,DIRECT"
        ].compactMap(\.self).joined(separator: "\n")
        return """
        mixed-port: \(mixedPort)
        proxy-groups:
          - name: \(groupName)
            type: select
            proxies:
              - DIRECT
        rules:
        \(rules)
        """
    }

    private static func runtimeConfigURL(in rootDirectory: URL) -> URL {
        rootDirectory
            .appending(path: "runtime", directoryHint: .isDirectory)
            .appending(path: "mihomo", directoryHint: .isDirectory)
            .appending(path: "config.yaml")
    }

    private static func mihomoConfigsURL(in rootDirectory: URL) -> URL {
        rootDirectory
            .appending(path: "configs", directoryHint: .isDirectory)
            .appending(path: "mihomo", directoryHint: .isDirectory)
    }

    private static func appLogURL(in rootDirectory: URL) -> URL {
        rootDirectory
            .appending(path: "runtime", directoryHint: .isDirectory)
            .appending(path: "logs", directoryHint: .isDirectory)
            .appending(path: "app.log")
    }
}

private final class MockProfileImportURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "profiles.example"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let client, let url = request.url else { return }
        let yaml = """
        mixed-port: 7892
        proxy-groups:
          - name: RemoteAdded
            type: select
            proxies:
              - DIRECT
        rules:
          - MATCH,DIRECT
        """
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/yaml",
                "Content-Disposition": "attachment; filename=remote-added.yaml"
            ]
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: Data(yaml.utf8))
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
