import Foundation
import Testing
@testable import DouClash

struct MihomoAPITests {
    @Test func controllerURLPercentEncodesProxyNamesAsSinglePathComponents() {
        let api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)

        let url = api.controllerURL(
            pathComponents: ["proxies", "HK/01 # premium", "delay"],
            queryItems: [
                URLQueryItem(name: "url", value: "https://example.com/generate_204"),
                URLQueryItem(name: "timeout", value: "5000")
            ]
        )

        #expect(url.absoluteString == "http://127.0.0.1:9090/proxies/HK%2F01%20%23%20premium/delay?url=https://example.com/generate_204&timeout=5000")
    }

    @Test func controllerURLPercentEncodesGroupNamesAsSinglePathComponents() {
        let api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!)

        let url = api.controllerURL(pathComponents: ["group", "Auto / UrlTest #1", "delay"])

        #expect(url.absoluteString == "http://127.0.0.1:9090/group/Auto%20%2F%20UrlTest%20%231/delay")
    }

    @Test func parseDelayMapAcceptsNestedDelayObjects() {
        let map = MihomoAPI.parseDelayMap([
            "HK-01": 120,
            "JP-02": ["delay": 88],
            "US-03": 0,
            "SG-04": ["message": "timeout"]
        ])

        #expect(map == ["HK-01": 120, "JP-02": 88, "US-03": 0])
    }

    @Test func recommendedGroupDelayRequestTimeoutScalesWithNodeCount() {
        #expect(MihomoAPI.recommendedGroupDelayRequestTimeoutSeconds(nodeCount: 1) == 10)
        #expect(MihomoAPI.recommendedGroupDelayRequestTimeoutSeconds(nodeCount: 55) == 14)
        #expect(MihomoAPI.recommendedGroupDelayRequestTimeoutSeconds(nodeCount: 200) == 24)
    }

    @Test func invalidDelayTestURLFallsBackToDefault() {
        #expect(MihomoAPI.resolvedDelayTestURL("file:///tmp/probe") == "https://www.gstatic.com/generate_204")
        #expect(MihomoAPI.resolvedDelayTestURL("https://user:password@example.com") == "https://www.gstatic.com/generate_204")
        #expect(MihomoAPI.resolvedDelayTestURL("https://example.com/generate_204") == "https://example.com/generate_204")
    }

    @Test func groupDelayReturnsResultsWhenControllerIsReachable() async throws {
        MockMihomoURLProtocolSupport.reset()
        let api = MihomoAPI(
            baseURL: URL(string: "http://127.0.0.1:9090")!,
            urlSession: MihomoAPI.makeMockSession(protocolClass: MockMihomoURLProtocol.self)
        )

        let delayMap = try await api.groupDelay(
            groupName: "koyun",
            testURL: "http://www.gstatic.com/generate_204",
            timeoutMs: 12_000
        )
        #expect(delayMap == ["HK-01": 120, "JP-02": 88])
    }
}
