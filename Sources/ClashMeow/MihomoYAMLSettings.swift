import Foundation

enum MihomoYAMLSettings {
    static func setTunEnabled(_ enabled: Bool, in yaml: String) -> String {
        if yaml.contains("\ntun:") || yaml.hasPrefix("tun:") {
            return setNestedBool(section: "tun", key: "enable", value: enabled, in: yaml)
        }
        guard enabled else { return yaml }
        let trimmed = yaml.trimmingCharacters(in: .newlines)
        return trimmed + defaultTunBlock
    }

    static func setNestedBool(section: String, key: String, value: Bool, in yaml: String) -> String {
        var lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let boolText = value ? "true" : "false"

        if let sectionIndex = lines.firstIndex(where: { isSectionHeader($0, section: section) }) {
            var insertIndex = sectionIndex + 1
            var keyUpdated = false

            for index in (sectionIndex + 1)..<lines.count {
                let line = lines[index]
                if isTopLevelEntry(line) {
                    break
                }
                if isNestedKey(line, key: key) {
                    lines[index] = "  \(key): \(boolText)"
                    keyUpdated = true
                    break
                }
                insertIndex = index + 1
            }

            if !keyUpdated {
                lines.insert("  \(key): \(boolText)", at: insertIndex)
            }
            return lines.joined(separator: "\n")
        }

        let trimmed = yaml.trimmingCharacters(in: .newlines)
        if section == "tun", value {
            return trimmed + defaultTunBlock
        }
        return yaml
    }

    private static let defaultTunBlock = """

tun:
  enable: true
  stack: system
  auto-route: true
  auto-detect-interface: true
  dns-hijack:
    - any:53
"""

    private static func isSectionHeader(_ line: String, section: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "\(section):"
    }

    private static func isTopLevelEntry(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#") else { return false }
        return !line.hasPrefix(" ") && !line.hasPrefix("\t") && trimmed.contains(":")
    }

    private static func isNestedKey(_ line: String, key: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("\(key):")
    }
}
