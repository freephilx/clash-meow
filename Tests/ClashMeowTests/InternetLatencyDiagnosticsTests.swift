import Testing
@testable import ClashMeow

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
}
