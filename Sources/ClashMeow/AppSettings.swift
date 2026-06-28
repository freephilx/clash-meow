import Foundation
import ServiceManagement

enum LaunchAtLoginManager {
    private static let userDefaultsKey = "app.launchAtLogin"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
    }

    static func bootstrap() {
        let desired = UserDefaults.standard.bool(forKey: userDefaultsKey)
        let registered = SMAppService.mainApp.status == .enabled
        guard desired != registered else { return }
        try? setEnabled(desired)
    }
}

enum CoreAutoStartManager {
    private static let userDefaultsKey = "mihomo.autoStartCore"

    /// Defaults to `true` on first launch.
    static var isEnabled: Bool {
        guard UserDefaults.standard.object(forKey: userDefaultsKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
    }
}

enum SystemProxyPreference {
    private static let userDefaultsKey = "mihomo.systemProxyEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
    }
}

enum TunPreference {
    private static let userDefaultsKey = "mihomo.tunEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
    }
}

#if DEBUG
enum DebugMockOverviewPreference {
    private static let userDefaultsKey = "debug.mockOverviewYAMLProfileEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
    }
}
#endif
