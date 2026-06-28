import Testing
@testable import ClashMeow

struct TrafficSnapshotTests {
    @Test func parsedReadsSpeedAndTotalsFromWebSocketPayload() {
        let payload = #"{"up":1024,"down":2048,"upTotal":4096,"downTotal":8192}"#
        let snapshot = TrafficSnapshot.parsed(from: payload)
        #expect(snapshot?.up == 1024)
        #expect(snapshot?.down == 2048)
        #expect(snapshot?.upTotal == 4096)
        #expect(snapshot?.downTotal == 8192)
    }
}
