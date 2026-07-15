import Foundation
import Yams

struct RuntimeConfigSettings: Equatable {
    var mixedPort: Int?
    var externalController: String = "127.0.0.1:9090"
    var secret: String = ""
    var mode: MihomoMode = .rule
    var allowLan: Bool = false
    var logLevel: String = "info"
    var tunEnabled: Bool?

    static var current: RuntimeConfigSettings {
        RuntimeConfigSettings(
            mode: MihomoMode(rawValue: AppPreferenceStore.string(\.forwardingMode) ?? "") ?? .rule,
            allowLan: AppPreferenceStore.bool(\.allowLan, default: false),
            tunEnabled: TunPreference.isEnabled
        )
    }
}

enum RuleOverridePlacement: String, CaseIterable, Identifiable, Codable {
    case prepend
    case append

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prepend: "前置"
        case .append: "后置"
        }
    }
}

struct RuleOverrideDraft: Equatable {
    var type: String = "DOMAIN-SUFFIX"
    var payload: String = ""
    var proxy: String = "DIRECT"
    var noResolve: Bool = false
    var source: Bool = false

    static let commonTypes = [
        "DOMAIN-SUFFIX",
        "DOMAIN",
        "DOMAIN-KEYWORD",
        "GEOSITE",
        "GEOIP",
        "IP-CIDR",
        "IP-CIDR6",
        "SRC-IP-CIDR",
        "PROCESS-NAME",
        "PROCESS-PATH",
        "RULE-SET",
        "MATCH"
    ]

    var supportsNoResolve: Bool {
        Self.noResolveTypes.contains(type)
    }

    var supportsSource: Bool {
        Self.sourceTypes.contains(type)
    }

    var requiresPayload: Bool {
        type != "MATCH"
    }

    var ruleText: String {
        var parts = [type]
        if requiresPayload {
            parts.append(payload.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        parts.append(proxy.trimmingCharacters(in: .whitespacesAndNewlines))
        if noResolve, supportsNoResolve {
            parts.append("no-resolve")
        }
        if source, supportsSource {
            parts.append("src")
        }
        return parts.joined(separator: ",")
    }

    var isValid: Bool {
        !type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !proxy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!requiresPayload || !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    mutating func normalizeForSelectedType() {
        if type == "MATCH" {
            payload = ""
        }
        if !supportsNoResolve {
            noResolve = false
        }
        if !supportsSource {
            source = false
        }
    }

    private static let noResolveTypes: Set<String> = [
        "GEOIP",
        "IP-CIDR",
        "IP-CIDR6",
        "SRC-IP-CIDR",
        "RULE-SET"
    ]

    private static let sourceTypes: Set<String> = [
        "GEOIP",
        "IP-CIDR",
        "IP-CIDR6",
        "RULE-SET"
    ]
}

struct RuleOverrideSet: Equatable {
    var prepend: [String] = []
    var append: [String] = []
    var delete: [String] = []

    var isEmpty: Bool {
        prepend.isEmpty && append.isEmpty && delete.isEmpty
    }

    init(prepend: [String] = [], append: [String] = [], delete: [String] = []) {
        self.prepend = prepend
        self.append = append
        self.delete = delete
    }

    init(yaml: String) throws {
        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let loaded = try Yams.load(yaml: yaml)
        let mapping = loaded as? [String: Any] ?? [:]
        prepend = Self.stringArray(mapping["prepend"])
        append = Self.stringArray(mapping["append"])
        delete = Self.stringArray(mapping["delete"])
    }

    func renderedYAML() throws -> String {
        var mapping: [String: Any] = [:]
        if !prepend.isEmpty { mapping["prepend"] = prepend }
        if !append.isEmpty { mapping["append"] = append }
        if !delete.isEmpty { mapping["delete"] = delete }
        guard !mapping.isEmpty else { return "" }
        return try Yams.dump(object: mapping, allowUnicode: true)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    mutating func add(_ rule: String, placement: RuleOverridePlacement) {
        let normalized = Self.normalized(rule)
        guard !normalized.isEmpty else { return }
        delete.removeAll { $0 == normalized }
        switch placement {
        case .prepend:
            if !prepend.contains(normalized) { prepend.append(normalized) }
        case .append:
            if !append.contains(normalized) { append.append(normalized) }
        }
    }

    mutating func setDeleted(_ rule: String, isDeleted: Bool) {
        let normalized = Self.normalized(rule)
        guard !normalized.isEmpty else { return }
        if isDeleted {
            if !delete.contains(normalized) { delete.append(normalized) }
        } else {
            delete.removeAll { $0 == normalized }
        }
    }

    private static func stringArray(_ value: Any?) -> [String] {
        (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func normalized(_ rule: String) -> String {
        rule.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum RuntimeConfigBuilder {
    private static let controlledTopLevelKeys: Set<String> = [
        "external-controller",
        "secret",
        "port",
        "socks-port",
        "mixed-port",
        "redir-port",
        "tproxy-port",
        "mode",
        "allow-lan",
        "log-level",
        "tun",
        "dns",
        "sniffer"
    ]

    static func build(
        profileYAML: String,
        settings: RuntimeConfigSettings = .current,
        ruleOverrides: RuleOverrideSet = RuleOverrideSet()
    ) throws -> String {
        let profileConfig = MihomoConfig.parsed(from: profileYAML)
        var document = try MihomoYAMLDocument(rawYAML: profileYAML)
        document.removeTopLevelKeys(controlledTopLevelKeys)
        document.applyRuleOverrides(ruleOverrides)
        document.merge(runtimeMapping(settings: settings, profileConfig: profileConfig))
        return try document.renderedYAML()
    }

    static func write(
        profileYAML: String,
        to url: URL,
        settings: RuntimeConfigSettings = .current,
        ruleOverrides: RuleOverrideSet = RuleOverrideSet()
    ) throws {
        let yaml = try build(profileYAML: profileYAML, settings: settings, ruleOverrides: ruleOverrides)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }

    static func setTunEnabled(_ enabled: Bool, in runtimeYAML: String) throws -> String {
        var document = try MihomoYAMLDocument(rawYAML: runtimeYAML)
        document.setNestedValue(section: "tun", key: "enable", value: enabled)
        if enabled {
            document.setNestedValueIfMissing(section: "tun", key: "stack", value: "system")
            document.setNestedValueIfMissing(section: "tun", key: "auto-route", value: true)
            document.setNestedValueIfMissing(section: "tun", key: "auto-detect-interface", value: true)
            document.setNestedValueIfMissing(section: "tun", key: "dns-hijack", value: ["any:53"])
        }
        return try document.renderedYAML()
    }

    private static func runtimeMapping(settings: RuntimeConfigSettings, profileConfig: MihomoConfig) -> [String: Any] {
        var mapping: [String: Any] = [
            "external-controller": settings.externalController,
            "secret": settings.secret,
            "mixed-port": settings.mixedPort ?? profileConfig.mixedPort ?? 7890,
            "mode": settings.mode.mihomoValue,
            "allow-lan": settings.allowLan,
            "log-level": settings.logLevel
        ]

        if let tunEnabled = settings.tunEnabled {
            mapping["tun"] = defaultTunMapping(enabled: tunEnabled)
        }

        return mapping
    }

    private static func defaultTunMapping(enabled: Bool) -> [String: Any] {
        [
            "enable": enabled,
            "stack": "system",
            "auto-route": true,
            "auto-detect-interface": true,
            "dns-hijack": ["any:53"]
        ]
    }
}

private struct MihomoYAMLDocument {
    private var mapping: [String: Any]

    init(rawYAML: String) throws {
        let trimmed = rawYAML.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            mapping = [:]
            return
        }
        let loaded = try Yams.load(yaml: rawYAML)
        mapping = loaded as? [String: Any] ?? [:]
    }

    mutating func removeTopLevelKeys(_ keys: Set<String>) {
        for key in keys {
            mapping.removeValue(forKey: key)
        }
    }

    mutating func merge(_ other: [String: Any]) {
        mapping.merge(other) { _, new in new }
    }

    mutating func applyRuleOverrides(_ overrides: RuleOverrideSet) {
        guard !overrides.isEmpty else { return }
        let deleteSet = Set(overrides.delete)
        let existingRules = mapping["rules"] as? [Any] ?? []
        let mergedRules = overrides.prepend + existingRules + overrides.append
        let retainedRules = mergedRules.filter { rule in
            guard let rule = rule as? String else { return true }
            return !deleteSet.contains(rule)
        }
        mapping["rules"] = retainedRules
    }

    mutating func setNestedValue(section: String, key: String, value: Any) {
        var sectionMapping = mapping[section] as? [String: Any] ?? [:]
        sectionMapping[key] = value
        mapping[section] = sectionMapping
    }

    mutating func setNestedValueIfMissing(section: String, key: String, value: Any) {
        var sectionMapping = mapping[section] as? [String: Any] ?? [:]
        if sectionMapping[key] == nil {
            sectionMapping[key] = value
        }
        mapping[section] = sectionMapping
    }

    func renderedYAML() throws -> String {
        guard !mapping.isEmpty else { return "" }
        return try Yams.dump(object: mapping, allowUnicode: true)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
