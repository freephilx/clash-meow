import Foundation

enum MihomoYAMLSettings {
    static func setTunEnabled(_ enabled: Bool, in yaml: String) throws -> String {
        try RuntimeConfigBuilder.setTunEnabled(enabled, in: yaml)
    }
}
