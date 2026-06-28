import Foundation
import Testing
@testable import ClashMeow

struct MihomoYAMLSettingsTests {
    @Test func setTunEnabledUpdatesExistingSection() {
        let yaml = """
        mixed-port: 7890
        tun:
          enable: false
          stack: system
        """
        let updated = MihomoYAMLSettings.setTunEnabled(true, in: yaml)
        #expect(updated.contains("enable: true"))
        #expect(!updated.contains("enable: false"))
    }

    @Test func setTunEnabledAppendsSectionWhenMissing() {
        let yaml = "mixed-port: 7890"
        let updated = MihomoYAMLSettings.setTunEnabled(true, in: yaml)
        #expect(updated.contains("tun:"))
        #expect(updated.contains("enable: true"))
        #expect(updated.contains("dns-hijack:"))
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
