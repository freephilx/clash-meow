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
    @Test func preferencesPersistToConfigDirectorySettingsFile() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-settings") { directory in
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

            let data = try Data(contentsOf: directory.appending(path: "settings.json"))
            let settings = try JSONDecoder().decode(AppPreferenceStore.Settings.self, from: data)

            #expect(settings.systemProxyEnabled == true)
            #expect(settings.systemProxyUserEnabled == true)
            #expect(settings.tunEnabled == true)
            #expect(settings.tunUserEnabled == true)
            #expect(settings.selectedProfileID == "remote-profile")
            #expect(settings.coreEnabled == false)
            #expect(settings.logRetentionDays == 12)
            #expect(settings.logDefaultLevel == LogLevelFilter.warning.rawValue)
            #expect(settings.internetLatencyTestURLs == "https://example.com/generate_204")
            #expect(settings.internetLatencyDNSDomain == "example.com")
            #expect(settings.internetLatencyTimeoutSeconds == 8)
        }
    }

    @Test func internetLatencyPreferencesSanitizeValues() {
        AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-settings") { _ in
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
        AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-settings") { _ in
            SystemProxyUserPreference.setEnabled(true)
            SystemProxyPreference.setEnabled(false)
            TunUserPreference.setEnabled(true)
            TunPreference.setEnabled(false)

            let settings = AppPreferenceStore.read()
            #expect(settings.systemProxyUserEnabled == true)
            #expect(settings.systemProxyEnabled == false)
            #expect(settings.tunUserEnabled == true)
            #expect(settings.tunEnabled == false)
        }
    }

    @Test func profileRepositoryRestoresLastUserSelectedProfileOnStartup() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-profiles") { directory in
            let activeConfig = directory.appending(path: "config.yaml")
            let repository = ProfileRepository(configDirectory: directory, activeConfigFile: activeConfig)
            _ = try repository.listProfiles()

            let profilesDirectory = directory.appending(path: "profiles", directoryHint: .isDirectory)
            let selectedID = "selected-profile"
            let selectedYAML = Self.profileYAML(groupName: "Selected")
            try selectedYAML.write(
                to: profilesDirectory.appending(path: "\(selectedID).yaml"),
                atomically: true,
                encoding: .utf8
            )
            ProfileSelectionPreference.setSelectedProfileID(selectedID)

            try repository.restoreSelectedProfileIfNeeded()

            let currentID = try String(contentsOf: profilesDirectory.appending(path: "current.txt"), encoding: .utf8)
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
            let activeConfig = directory.appending(path: "config.yaml")
            let repository = ProfileRepository(configDirectory: directory, activeConfigFile: activeConfig)
            _ = try repository.listProfiles()

            let profilesDirectory = directory.appending(path: "profiles", directoryHint: .isDirectory)
            let selectedID = "selected-profile"
            try Self.profileYAML(groupName: "Selected", mixedPort: 7891).write(
                to: profilesDirectory.appending(path: "\(selectedID).yaml"),
                atomically: true,
                encoding: .utf8
            )
            try selectedID.write(to: profilesDirectory.appending(path: "current.txt"), atomically: true, encoding: .utf8)
            try Self.profileYAML(groupName: "Selected", mixedPort: 7890).write(
                to: activeConfig,
                atomically: true,
                encoding: .utf8
            )
            ProfileSelectionPreference.setSelectedProfileID(selectedID)

            try repository.restoreSelectedProfileIfNeeded()

            let activeYAML = try String(contentsOf: activeConfig, encoding: .utf8)
            let appLog = try String(contentsOf: directory.appending(path: "logs/app.log"), encoding: .utf8)
            #expect(activeYAML.contains("mixed-port: 7891"))
            #expect(!activeYAML.contains("mixed-port: 7890"))
            #expect(appLog.contains("[RuntimeConfig]"))
            #expect(appLog.contains("reason=startupRefresh"))
            #expect(appLog.contains("mixed-port=7891"))
        }
    }

    @Test func profileRepositoryRuleOverrideUpdatesRuntimeConfig() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-profiles") { directory in
            let activeConfig = directory.appending(path: "config.yaml")
            let repository = ProfileRepository(configDirectory: directory, activeConfigFile: activeConfig)
            _ = try repository.listProfiles()

            let profilesDirectory = directory.appending(path: "profiles", directoryHint: .isDirectory)
            let selectedID = "selected-profile"
            try Self.profileYAML(groupName: "Selected").write(
                to: profilesDirectory.appending(path: "\(selectedID).yaml"),
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
                contentsOf: profilesDirectory.appending(path: "\(selectedID).rules.yaml"),
                encoding: .utf8
            )
            #expect(activeYAML.contains("DOMAIN-SUFFIX,example.com,Proxy"))
            #expect(overrideYAML.contains("prepend:"))
            #expect(overrideYAML.contains("DOMAIN-SUFFIX,example.com,Proxy"))
        }
    }

    @Test func profileRepositoryRuleDeleteOverrideUpdatesRuntimeConfig() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-profiles") { directory in
            let activeConfig = directory.appending(path: "config.yaml")
            let repository = ProfileRepository(configDirectory: directory, activeConfigFile: activeConfig)
            _ = try repository.listProfiles()

            let profilesDirectory = directory.appending(path: "profiles", directoryHint: .isDirectory)
            let selectedID = "selected-profile"
            try Self.profileYAML(groupName: "Selected", extraRule: "DOMAIN-SUFFIX,example.com,Proxy").write(
                to: profilesDirectory.appending(path: "\(selectedID).yaml"),
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
                contentsOf: profilesDirectory.appending(path: "\(selectedID).rules.yaml"),
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
            #expect(!FileManager.default.fileExists(atPath: profilesDirectory.appending(path: "\(selectedID).rules.yaml").path))
        }
    }

    @Test func profileRepositoryClearsMissingSelectedProfileOnStartup() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-profiles") { directory in
            let repository = ProfileRepository(
                configDirectory: directory,
                activeConfigFile: directory.appending(path: "config.yaml")
            )
            _ = try repository.listProfiles()
            ProfileSelectionPreference.setSelectedProfileID("missing-profile")

            try repository.restoreSelectedProfileIfNeeded()

            #expect(ProfileSelectionPreference.selectedProfileID == nil)
        }
    }

    @Test func profileRepositoryMigratesCurrentProfileToSelectedProfileWhenMissing() throws {
        try AppPreferenceStoreTestIsolation.withTemporaryDirectory(prefix: "clash-meow-profiles") { directory in
            let repository = ProfileRepository(
                configDirectory: directory,
                activeConfigFile: directory.appending(path: "config.yaml")
            )
            _ = try repository.listProfiles()

            try repository.restoreSelectedProfileIfNeeded()

            #expect(ProfileSelectionPreference.selectedProfileID == "default")
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
}
