import Foundation
import Testing
@testable import ClashMeow

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
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-preferences") { directory in
            SystemProxyPreference.setEnabled(true)
            SystemProxyUserPreference.setEnabled(true)
            TunPreference.setEnabled(true)
            TunUserPreference.setEnabled(true)
            ProfileSelectionPreference.setSelectedProfileID("remote-profile")
            CoreAutoStartManager.setEnabled(false)
            LogPreference.retentionDays = 12
            LogPreference.defaultLevel = .warning
            InternetLatencyPreference.testURLsText = "https://example.com/generate_204"
            InternetLatencyPreference.dnsDomain = "example.com"
            InternetLatencyPreference.timeoutSeconds = 8

            let data = try Data(contentsOf: directory.appending(path: "preferences.json"))
            let preferences = try JSONDecoder().decode(AppPreferenceStore.Preferences.self, from: data)

            #expect(preferences.systemProxyEnabled == true)
            #expect(preferences.systemProxyUserEnabled == true)
            #expect(preferences.tunEnabled == true)
            #expect(preferences.tunUserEnabled == true)
            #expect(preferences.selectedProfileID == "remote-profile")
            #expect(preferences.coreEnabled == false)
            #expect(preferences.logRetentionDays == 12)
            #expect(preferences.logDefaultLevel == LogLevelFilter.warning.rawValue)
            #expect(preferences.internetLatencyTestURLs == "https://example.com/generate_204")
            #expect(preferences.internetLatencyDNSDomain == "example.com")
            #expect(preferences.internetLatencyTimeoutSeconds == 8)
        }
    }

    @Test func corruptPreferencesFileUsesDefaults() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-preferences") { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("not-json".utf8)
                .write(to: directory.appending(path: "preferences.json"), options: .atomic)

            #expect(AppPreferenceStore.read().coreEnabled == nil)
        }
    }

    @Test func internetLatencyPreferencesSanitizeValues() {
        AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-preferences") { _ in
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
        AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-preferences") { _ in
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
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-profiles") { directory in
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
            ProfileSelectionPreference.setSelectedProfileID(selectedID)

            try repository.restoreSelectedProfileIfNeeded()

            let currentID = try String(contentsOf: mihomoConfigsDirectory.appending(path: "current.txt"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let activeYAML = try String(contentsOf: activeConfig, encoding: .utf8)

            #expect(currentID == selectedID)
            #expect(activeYAML.contains("name: Selected"))
            #expect(activeYAML.contains("mixed-port: 7890"))
            #expect(activeYAML.contains("external-controller: 127.0.0.1:9090"))
            #expect(activeYAML.contains("tun:"))
            #expect(ProfileSelectionPreference.selectedProfileID == selectedID)
        }
    }

    @Test func profileRepositoryRefreshesStaleActiveConfigOnStartup() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-profiles") { directory in
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
            try selectedID.write(to: mihomoConfigsDirectory.appending(path: "current.txt"), atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(
                at: activeConfig.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.profileYAML(groupName: "Selected", mixedPort: 7890).write(
                to: activeConfig,
                atomically: true,
                encoding: .utf8
            )
            ProfileSelectionPreference.setSelectedProfileID(selectedID)

            try repository.restoreSelectedProfileIfNeeded()

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
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-profiles") { directory in
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
            let overrideYAML = try String(
                contentsOf: mihomoConfigsDirectory.appending(path: "\(selectedID).rules.yaml"),
                encoding: .utf8
            )
            #expect(activeYAML.contains("DOMAIN-SUFFIX,example.com,Proxy"))
            #expect(overrideYAML.contains("prepend:"))
            #expect(overrideYAML.contains("DOMAIN-SUFFIX,example.com,Proxy"))
            #expect(!(try repository.listProfiles()).contains { $0.id == "selected-profile.rules" })
        }
    }

    @Test func profileRepositoryRuleDeleteOverrideUpdatesRuntimeConfig() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-profiles") { directory in
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
            let overrideYAML = try String(
                contentsOf: mihomoConfigsDirectory.appending(path: "\(selectedID).rules.yaml"),
                encoding: .utf8
            )
            #expect(!disabledActiveYAML.contains("DOMAIN-SUFFIX,example.com,Proxy"))
            #expect(overrideYAML.contains("delete:"))
            #expect(overrideYAML.contains("DOMAIN-SUFFIX,example.com,Proxy"))

            try repository.setRuleDeletedOverride(
                profileID: selectedID,
                rule: "DOMAIN-SUFFIX,example.com,Proxy",
                isDeleted: false
            )

            let enabledActiveYAML = try String(contentsOf: activeConfig, encoding: .utf8)
            #expect(enabledActiveYAML.contains("DOMAIN-SUFFIX,example.com,Proxy"))
            #expect(!FileManager.default.fileExists(atPath: mihomoConfigsDirectory.appending(path: "\(selectedID).rules.yaml").path))
        }
    }

    @Test func profileRepositoryClearsMissingSelectedProfileOnStartup() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-profiles") { directory in
            let repository = ProfileRepository(
                configDirectory: directory,
                activeConfigFile: Self.runtimeConfigURL(in: directory)
            )
            _ = try repository.listProfiles()
            ProfileSelectionPreference.setSelectedProfileID("missing-profile")

            try repository.restoreSelectedProfileIfNeeded()

            #expect(ProfileSelectionPreference.selectedProfileID == nil)
        }
    }

    @Test func profileRepositoryInitializesDefaultSelectionWhenMissing() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-profiles") { directory in
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
            try "ignored-current".write(
                to: mihomoConfigsDirectory.appending(path: "current.txt"),
                atomically: true,
                encoding: .utf8
            )

            try repository.restoreSelectedProfileIfNeeded()

            #expect(ProfileSelectionPreference.selectedProfileID == "default")
            let currentID = try String(
                contentsOf: mihomoConfigsDirectory.appending(path: "current.txt"),
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(currentID == "default")
        }
    }

    @Test func runtimeConfigIsNotUsedAsDefaultProfileSource() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-profiles") { directory in
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

    @Test func rootProfilesDirectoryIsIgnored() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-profiles") { directory in
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
