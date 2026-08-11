import Testing
@testable import DouClash

@Suite struct InternetLatencyDiagnosticsTests {
    @Test func parseDefaultGatewayFromRouteOutput() {
        let output = """
           route to: default
        destination: default
               mask: default
            gateway: 192.168.31.1
          interface: en0
        """

        #expect(InternetLatencyDiagnostics.parseDefaultGateway(from: output) == "192.168.31.1")
    }

    @Test func parsePingLatencyRoundsFractionalMilliseconds() {
        let output = """
        PING 192.168.31.1 (192.168.31.1): 56 data bytes
        64 bytes from 192.168.31.1: icmp_seq=0 ttl=64 time=2.652 ms
        """

        #expect(InternetLatencyDiagnostics.parsePingLatency(from: output) == 3)
    }

    @Test func parseDigQueryTime() {
        let output = """
        ;; QUESTION SECTION:
        ;bing.com.                      IN      A

        ;; Query time: 18 msec
        ;; SERVER: 192.168.31.1#53(192.168.31.1)
        """

        #expect(InternetLatencyDiagnostics.parseDigQueryTime(from: output) == 18)
    }

    @Test func localDNSServersIgnoreNetworkSetupEmptyMessage() {
        let output = "There aren't any DNS Servers set on Wi-Fi."

        #expect(LocalDNSDiagnostics.networkServiceDNSServers(from: output).isEmpty)
        #expect(LocalDNSDiagnostics.networkServiceDNSServers(from: "223.5.5.5\n1.1.1.1") == ["223.5.5.5", "1.1.1.1"])
    }

    @Test func localDNSResolverSummariesIdentifySystemAndTailscaleResolvers() {
        let output = """
        DNS configuration

        resolver #1
          nameserver[0] : 223.5.5.5

        DNS configuration (for scoped queries)

        resolver #1
          domain   : tail.example.ts.net
          nameserver[0] : 100.100.100.100
          if_index : 18 (utun5)
        """

        let summaries = LocalDNSDiagnostics.resolverSummaries(
            from: output,
            tailscaleInterfaceNames: ["utun5"]
        )

        #expect(summaries == [
            "系统解析 默认：223.5.5.5",
            "Tailscale（utun5） tail.example.ts.net：100.100.100.100"
        ])
    }
}
