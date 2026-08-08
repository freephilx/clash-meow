import Foundation
import ServiceManagement

enum AppPersistencePaths {
    static let configDirectoryName = ".config/clash-meow"
    nonisolated(unsafe) static var configDirectoryOverrideForTesting: URL?

    static var configDirectory: URL {
        if let configDirectoryOverrideForTesting {
            return configDirectoryOverrideForTesting
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: configDirectoryName, directoryHint: .isDirectory)
    }

    static var runtimeDirectory: URL {
        configDirectory.appending(path: "runtime", directoryHint: .isDirectory)
    }

    static var configsDirectory: URL {
        configDirectory.appending(path: "configs", directoryHint: .isDirectory)
    }

    static var mihomoConfigsDirectory: URL {
        configsDirectory.appending(path: "mihomo", directoryHint: .isDirectory)
    }

    static var mihomoRuntimeDirectory: URL {
        runtimeDirectory.appending(path: "mihomo", directoryHint: .isDirectory)
    }

    static var logsDirectory: URL {
        runtimeDirectory.appending(path: "logs", directoryHint: .isDirectory)
    }
}

enum AppPreferenceStore {
    struct Preferences: Codable, Equatable {
        var launchAtLogin: Bool?
        var coreEnabled: Bool?
        var systemProxyEnabled: Bool?
        var systemProxyUserEnabled: Bool?
        var tunEnabled: Bool?
        var tunUserEnabled: Bool?
        var selectedProfileID: String?
        var forwardingMode: String?
        var allowLan: Bool?
        var systemProxyNetworkService: String?
        var logRetentionDays: Int?
        var logMaxFileSizeMB: Int?
        var appLoggingEnabled: Bool?
        var logDefaultSource: String?
        var logDefaultLevel: String?
        var logAutoCleanupEnabled: Bool?
        var destructiveLogActionsEnabled: Bool?
        var internetLatencyTestURLs: String?
        var internetLatencyDNSDomain: String?
        var internetLatencyTimeoutSeconds: Int?
    }

    private static let preferencesFileName = "preferences.json"
    nonisolated(unsafe) static var configDirectoryOverrideForTesting: URL?

    static var configDirectory: URL {
        if let configDirectoryOverrideForTesting {
            return configDirectoryOverrideForTesting
        }
        return AppPersistencePaths.configDirectory
    }

    static var preferencesFile: URL {
        configDirectory.appending(path: preferencesFileName)
    }

    static func bool(
        _ keyPath: WritableKeyPath<Preferences, Bool?>,
        default defaultValue: Bool
    ) -> Bool {
        let preferences = read()
        return preferences[keyPath: keyPath] ?? defaultValue
    }

    static func setBool(_ value: Bool, _ keyPath: WritableKeyPath<Preferences, Bool?>) {
        update { preferences in
            preferences[keyPath: keyPath] = value
        }
    }

    static func int(
        _ keyPath: WritableKeyPath<Preferences, Int?>,
        default defaultValue: Int
    ) -> Int {
        let preferences = read()
        return preferences[keyPath: keyPath] ?? defaultValue
    }

    static func setInt(_ value: Int, _ keyPath: WritableKeyPath<Preferences, Int?>) {
        update { preferences in
            preferences[keyPath: keyPath] = value
        }
    }

    static func string(_ keyPath: WritableKeyPath<Preferences, String?>) -> String? {
        let preferences = read()
        return preferences[keyPath: keyPath]
    }

    static func setString(_ value: String?, _ keyPath: WritableKeyPath<Preferences, String?>) {
        update { preferences in
            preferences[keyPath: keyPath] = value
        }
    }

    static func read() -> Preferences {
        guard let data = try? Data(contentsOf: preferencesFile) else {
            return Preferences()
        }
        return (try? JSONDecoder().decode(Preferences.self, from: data)) ?? Preferences()
    }

    private static func update(_ mutate: (inout Preferences) -> Void) {
        var preferences = read()
        mutate(&preferences)
        write(preferences)
    }

    private static func write(_ preferences: Preferences) {
        do {
            let directory = configDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(preferences)
            try data.write(to: preferencesFile, options: .atomic)
        } catch {
            assertionFailure("Failed to write app preferences: \(error.localizedDescription)")
        }
    }
}

enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        AppPreferenceStore.bool(\.launchAtLogin, default: false)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        AppPreferenceStore.setBool(enabled, \.launchAtLogin)
    }

    static func bootstrap() {
        let desired = isEnabled
        let registered = SMAppService.mainApp.status == .enabled
        guard desired != registered else { return }
        try? setEnabled(desired)
    }
}

enum CoreAutoStartManager {
    /// Defaults to `true` on first launch.
    static var isEnabled: Bool {
        AppPreferenceStore.bool(\.coreEnabled, default: true)
    }

    static func setEnabled(_ enabled: Bool) {
        AppPreferenceStore.setBool(enabled, \.coreEnabled)
    }
}

enum ProfileSelectionPreference {
    static var selectedProfileID: String? {
        AppPreferenceStore.string(\.selectedProfileID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func setSelectedProfileID(_ id: String?) {
        let value = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        AppPreferenceStore.setString(value?.isEmpty == false ? value : nil, \.selectedProfileID)
    }

    static func clearIfSelected(_ id: String) {
        guard selectedProfileID == id else { return }
        setSelectedProfileID(nil)
    }
}

enum SystemProxyPreference {
    static var isEnabled: Bool {
        AppPreferenceStore.bool(\.systemProxyEnabled, default: false)
    }

    static func setEnabled(_ enabled: Bool) {
        AppPreferenceStore.setBool(enabled, \.systemProxyEnabled)
    }
}

enum SystemProxyUserPreference {
    static var isEnabled: Bool {
        let preferences = AppPreferenceStore.read()
        return preferences.systemProxyUserEnabled ?? false
    }

    static func setEnabled(_ enabled: Bool) {
        AppPreferenceStore.setBool(enabled, \.systemProxyUserEnabled)
    }
}

enum TunPreference {
    static var isEnabled: Bool {
        AppPreferenceStore.bool(\.tunEnabled, default: false)
    }

    static func setEnabled(_ enabled: Bool) {
        AppPreferenceStore.setBool(enabled, \.tunEnabled)
    }
}

enum TunUserPreference {
    static var isEnabled: Bool {
        let preferences = AppPreferenceStore.read()
        return preferences.tunUserEnabled ?? false
    }

    static func setEnabled(_ enabled: Bool) {
        AppPreferenceStore.setBool(enabled, \.tunUserEnabled)
    }
}

enum LogPreference {
    static var retentionDays: Int {
        get {
            min(max(AppPreferenceStore.int(\.logRetentionDays, default: 7), 1), 30)
        }
        set {
            AppPreferenceStore.setInt(min(max(newValue, 1), 30), \.logRetentionDays)
        }
    }

    static var maxFileSizeMB: Int {
        get {
            min(max(AppPreferenceStore.int(\.logMaxFileSizeMB, default: 10), 1), 100)
        }
        set {
            AppPreferenceStore.setInt(min(max(newValue, 1), 100), \.logMaxFileSizeMB)
        }
    }

    static var maxFileSizeBytes: Int {
        maxFileSizeMB * 1024 * 1024
    }

    static var isAppLoggingEnabled: Bool {
        get {
            AppPreferenceStore.bool(\.appLoggingEnabled, default: true)
        }
        set {
            AppPreferenceStore.setBool(newValue, \.appLoggingEnabled)
        }
    }

    static var defaultSource: LogSourceFilter {
        get {
            LogSourceFilter(rawValue: AppPreferenceStore.string(\.logDefaultSource) ?? "") ?? .core
        }
        set {
            AppPreferenceStore.setString(newValue.rawValue, \.logDefaultSource)
        }
    }

    static var defaultLevel: LogLevelFilter {
        get {
            LogLevelFilter(rawValue: AppPreferenceStore.string(\.logDefaultLevel) ?? "") ?? .all
        }
        set {
            AppPreferenceStore.setString(newValue.rawValue, \.logDefaultLevel)
        }
    }

    static var isAutoCleanupEnabled: Bool {
        get {
            AppPreferenceStore.bool(\.logAutoCleanupEnabled, default: true)
        }
        set {
            AppPreferenceStore.setBool(newValue, \.logAutoCleanupEnabled)
        }
    }

    static var allowsDestructiveFileActions: Bool {
        get {
            AppPreferenceStore.bool(\.destructiveLogActionsEnabled, default: true)
        }
        set {
            AppPreferenceStore.setBool(newValue, \.destructiveLogActionsEnabled)
        }
    }
}

enum InternetLatencyPreference {
    static let defaultTestURLs = [
        "https://www.apple.com/library/test/success.html",
        "https://www.cloudflare.com/cdn-cgi/trace",
        "https://github.com/"
    ]
    static let defaultDNSDomain = "bing.com"
    static let defaultTimeoutSeconds = 3

    static var testURLsText: String {
        get {
            let value = AppPreferenceStore.string(\.internetLatencyTestURLs)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value! : defaultTestURLs.joined(separator: "\n")
        }
        set {
            let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            AppPreferenceStore.setString(value.isEmpty ? nil : value, \.internetLatencyTestURLs)
        }
    }

    static var dnsDomain: String {
        get {
            let value = AppPreferenceStore.string(\.internetLatencyDNSDomain)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value! : defaultDNSDomain
        }
        set {
            let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            AppPreferenceStore.setString(value.isEmpty ? nil : value, \.internetLatencyDNSDomain)
        }
    }

    static var timeoutSeconds: Int {
        get {
            min(max(AppPreferenceStore.int(\.internetLatencyTimeoutSeconds, default: defaultTimeoutSeconds), 1), 10)
        }
        set {
            AppPreferenceStore.setInt(min(max(newValue, 1), 10), \.internetLatencyTimeoutSeconds)
        }
    }

    static var configuration: InternetLatencyConfiguration {
        InternetLatencyConfiguration(
            httpTestURLs: parsedTestURLs(from: testURLsText),
            dnsDomain: dnsDomain,
            timeoutSeconds: timeoutSeconds
        )
    }

    private static func parsedTestURLs(from value: String) -> [URL] {
        let separators = CharacterSet(charactersIn: ",\n")
        let urls = value
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { URL(string: $0) }
            .filter { $0.scheme == "http" || $0.scheme == "https" }
        return urls.isEmpty ? defaultTestURLs.compactMap(URL.init(string:)) : urls
    }
}
