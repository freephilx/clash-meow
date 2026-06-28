import Foundation

/// mihomo `/traffic` WebSocket 采样，用于概览页吞吐曲线。
struct TrafficSample: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let upload: Int
    let download: Int

    var total: Int { upload + download }
}
