import Foundation
import Testing
@testable import DouMeow

struct MihomoYAMLSettingsTests {
    @Test func setTunEnabledUpdatesExistingSection() throws {
        let yaml = """
        mixed-port: 7890
        tun:
          enable: false
          stack: system
        """
        let updated = try MihomoYAMLSettings.setTunEnabled(true, in: yaml)
        #expect(updated.contains("enable: true"))
        #expect(!updated.contains("enable: false"))
    }

    @Test func setTunEnabledAppendsSectionWhenMissing() throws {
        let yaml = "mixed-port: 7890"
        let updated = try MihomoYAMLSettings.setTunEnabled(true, in: yaml)
        #expect(updated.contains("tun:"))
        #expect(updated.contains("enable: true"))
        #expect(updated.contains("dns-hijack:"))
    }

    @Test func runtimeBuilderRemovesProfileControlledKeysAndAppendsAppSettings() throws {
        let profileYAML = """
        mixed-port: 6666
        external-controller: 0.0.0.0:1111
        allow-lan: true
        tun:
          enable: false
        proxies: []
        rules:
          - MATCH,DIRECT
        """

        let runtimeYAML = try RuntimeConfigBuilder.build(
            profileYAML: profileYAML,
            settings: RuntimeConfigSettings(
                mixedPort: 7890,
                externalController: "127.0.0.1:9090",
                secret: "",
                mode: .global,
                allowLan: false,
                logLevel: "info",
                tunEnabled: true
            )
        )

        #expect(runtimeYAML.contains("mixed-port: 7890"))
        #expect(runtimeYAML.contains("external-controller: 127.0.0.1:9090"))
        #expect(runtimeYAML.contains("mode: global"))
        #expect(runtimeYAML.contains("allow-lan: false"))
        #expect(runtimeYAML.contains("enable: true"))
        #expect(!runtimeYAML.contains("mixed-port: 6666"))
        #expect(!runtimeYAML.contains("0.0.0.0:1111"))
    }

    @Test func runtimeBuilderInheritsProfileMixedPortWhenAppSettingIsMissing() throws {
        let profileYAML = """
        mixed-port: 7891
        proxies: []
        rules:
          - MATCH,DIRECT
        """

        let runtimeYAML = try RuntimeConfigBuilder.build(profileYAML: profileYAML)

        #expect(runtimeYAML.contains("mixed-port: 7891"))
        #expect(!runtimeYAML.contains("mixed-port: 7890"))
    }

    @Test func runtimeBuilderUsesAppManagedFindProcessMode() throws {
        let profileYAML = """
        find-process-mode: off
        proxies: []
        rules:
          - MATCH,DIRECT
        """

        let runtimeYAML = try RuntimeConfigBuilder.build(profileYAML: profileYAML)

        #expect(runtimeYAML.contains("find-process-mode: always"))
        #expect(!runtimeYAML.contains("find-process-mode: false"))
    }

    @Test func runtimeBuilderAppliesRuleOverrides() throws {
        let profileYAML = """
        mixed-port: 7891
        rules:
          - DOMAIN-SUFFIX,old.example.com,DIRECT
          - MATCH,DIRECT
        """

        let runtimeYAML = try RuntimeConfigBuilder.build(
            profileYAML: profileYAML,
            ruleOverrides: RuleOverrideSet(
                prepend: ["DOMAIN-SUFFIX,example.com,Proxy"],
                append: ["DOMAIN-SUFFIX,tail.example.com,DIRECT"],
                delete: [
                    "DOMAIN-SUFFIX,old.example.com,DIRECT",
                    "DOMAIN-SUFFIX,tail.example.com,DIRECT"
                ]
            )
        )

        #expect(runtimeYAML.contains("DOMAIN-SUFFIX,example.com,Proxy"))
        #expect(!runtimeYAML.contains("DOMAIN-SUFFIX,tail.example.com,DIRECT"))
        #expect(!runtimeYAML.contains("DOMAIN-SUFFIX,old.example.com,DIRECT"))
        let prependIndex = try #require(runtimeYAML.range(of: "DOMAIN-SUFFIX,example.com,Proxy")?.lowerBound)
        let matchIndex = try #require(runtimeYAML.range(of: "MATCH,DIRECT")?.lowerBound)
        #expect(prependIndex < matchIndex)
    }

    @Test func ruleOverrideAddClearsMatchingDelete() throws {
        var overrides = RuleOverrideSet(delete: ["DOMAIN-SUFFIX,example.com,Proxy"])

        overrides.add("DOMAIN-SUFFIX,example.com,Proxy", placement: .prepend)

        #expect(overrides.prepend == ["DOMAIN-SUFFIX,example.com,Proxy"])
        #expect(overrides.delete.isEmpty)
    }

    @Test func ruleOverrideAddPlacesNewestRuleFirst() {
        var overrides = RuleOverrideSet(
            prepend: ["DOMAIN-SUFFIX,first.example.com,Proxy"],
            append: ["DOMAIN-SUFFIX,moved.example.com,DIRECT"]
        )

        overrides.add("DOMAIN-SUFFIX,second.example.com,Proxy", placement: .prepend)
        overrides.add("DOMAIN-SUFFIX,moved.example.com,DIRECT", placement: .prepend)

        #expect(overrides.prepend == [
            "DOMAIN-SUFFIX,moved.example.com,DIRECT",
            "DOMAIN-SUFFIX,second.example.com,Proxy",
            "DOMAIN-SUFFIX,first.example.com,Proxy"
        ])
        #expect(overrides.append.isEmpty)
    }

    @Test func ruleOverrideReplaceDeletesSourceRuleAndPrependsReplacement() {
        var overrides = RuleOverrideSet()

        overrides.replace(
            "DOMAIN-SUFFIX,old.example.com,DIRECT",
            with: "DOMAIN-SUFFIX,new.example.com,Proxy"
        )

        #expect(overrides.prepend == ["DOMAIN-SUFFIX,new.example.com,Proxy"])
        #expect(overrides.delete == ["DOMAIN-SUFFIX,old.example.com,DIRECT"])
    }

    @Test func ruleTextValidationAcceptsMatchAndRejectsIncompleteRules() {
        #expect(RuleOverrideSet.isValidRuleText("MATCH,DIRECT"))
        #expect(RuleOverrideSet.isValidRuleText("DOMAIN-SUFFIX,example.com,Proxy"))
        #expect(!RuleOverrideSet.isValidRuleText("MATCH,"))
        #expect(!RuleOverrideSet.isValidRuleText("DOMAIN-SUFFIX,,Proxy"))
        #expect(!RuleOverrideSet.isValidRuleText("DOMAIN-SUFFIX,example.com,"))
    }

    @Test func ruleOverrideDraftBuildsStructuredRuleText() {
        let domainRule = RuleOverrideDraft(
            type: "DOMAIN-SUFFIX",
            payload: "example.com",
            proxy: "Proxy"
        )
        let matchRule = RuleOverrideDraft(type: "MATCH", proxy: "DIRECT")
        let cidrRule = RuleOverrideDraft(
            type: "IP-CIDR",
            payload: "8.8.8.0/24",
            proxy: "Proxy",
            noResolve: true,
            source: true
        )

        #expect(domainRule.ruleText == "DOMAIN-SUFFIX,example.com,Proxy")
        #expect(matchRule.ruleText == "MATCH,DIRECT")
        #expect(cidrRule.ruleText == "IP-CIDR,8.8.8.0/24,Proxy,no-resolve,src")
        #expect(domainRule.isValid)
        #expect(matchRule.isValid)
    }

    @Test func ruleOverrideDraftClearsUnsupportedOptionsWhenTypeChanges() {
        var draft = RuleOverrideDraft(
            type: "IP-CIDR",
            payload: "8.8.8.0/24",
            proxy: "Proxy",
            noResolve: true,
            source: true
        )

        draft.type = "DOMAIN"
        draft.normalizeForSelectedType()

        #expect(!draft.noResolve)
        #expect(!draft.source)
    }

    @Test func runtimeBuilderKeepsUnicodeNodeNamesReadable() throws {
        let profileYAML = """
        proxies:
          - name: "[vless]剩余流量：75.04 GB"
            type: vless
            server: 199.15.77.250
            port: 443
        proxy-groups:
          - name: 自动选择
            type: select
            proxies:
              - "[vless]剩余流量：75.04 GB"
        """

        let runtimeYAML = try RuntimeConfigBuilder.build(profileYAML: profileYAML)

        #expect(runtimeYAML.contains("[vless]剩余流量：75.04 GB"))
        #expect(runtimeYAML.contains("自动选择"))
        #expect(!runtimeYAML.contains("\\u5269"))
        #expect(!runtimeYAML.contains("\\U0001F"))
    }

    @Test func networkServiceParsesActiveInterface() throws {
        let output = """
        (1) Wi-Fi
        (Hardware Port: Wi-Fi, Device: en0)

        (2) Thunderbolt Bridge
        (Hardware Port: Thunderbolt Bridge, Device: bridge0)
        """
        let service = try SystemProxyController.networkService(in: output, matchingDevice: "en0")
        #expect(service == "Wi-Fi")
    }

    @Test func systemProxyProtocolStateParsesEnabledEndpoint() throws {
        let output = """
        Enabled: Yes
        Server: 127.0.0.1
        Port: 7890
        Authenticated Proxy Enabled: 0
        """

        let state = try SystemProxyController.proxyProtocolState(from: output)

        #expect(state == SystemProxyProtocolState(isEnabled: true, host: "127.0.0.1", port: 7890))
    }

    @Test func systemProxyProtocolStateParsesDisabledEndpoint() throws {
        let output = """
        Enabled: No
        Server:
        Port: 0
        Authenticated Proxy Enabled: 0
        """

        let state = try SystemProxyController.proxyProtocolState(from: output)

        #expect(state == SystemProxyProtocolState(isEnabled: false, host: nil, port: 0))
    }

    @Test func listeningPortsIncludeControllerAndDNSListen() {
        let yaml = """
        port: 7891
        socks-port: 7892
        mixed-port: 7890
        redir-port: 7893
        tproxy-port: 7894
        external-controller: 127.0.0.1:9090
        dns:
          enable: true
          listen: ':53'
        """

        #expect(MihomoConfig.listeningPorts(from: yaml) == [53, 7890, 7891, 7892, 7893, 7894, 9090])
    }

    @Test func listeningPortsIgnoreProxyNodePorts() {
        let yaml = """
        mixed-port: 7891
        external-controller: 127.0.0.1:9090
        proxies:
          - name: tls-node
            type: vless
            server: example.com
            port: 443
        """

        #expect(MihomoConfig.listeningPorts(from: yaml) == [7891, 9090])
    }

    @Test func listeningPortsParseURLAndIPv6StyleHosts() {
        #expect(MihomoConfig.portFromHostPort("http://127.0.0.1:9090/ui") == 9090)
        #expect(MihomoConfig.portFromHostPort("[::1]:1053") == 1053)
        #expect(MihomoConfig.portFromHostPort(":53") == 53)
    }

    @Test func listeningPortsIgnoreInlineCommentsAndUseDNSDefault() {
        let yaml = """
        mixed-port: 7890 # shared proxy port
        external-controller: :9090 # controller
        dns:
          enable: true
        """

        #expect(MihomoConfig.listeningPorts(from: yaml) == [1053, 7890, 9090])
    }
}
