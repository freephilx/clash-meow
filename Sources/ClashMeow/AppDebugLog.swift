import Foundation
import os

@MainActor
enum AppDebugLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.clash.meow"
    private static let modeLogger = Logger(subsystem: subsystem, category: "Mode")

    static var recentModeMessages: [String] = []

    static func mode(_ message: String) {
        modeLogger.debug("\(message, privacy: .public)")
        recentModeMessages.append(message)
        if recentModeMessages.count > 64 {
            recentModeMessages.removeFirst(recentModeMessages.count - 64)
        }
        #if DEBUG
        print("[Mode] \(message)")
        #endif
    }

    static func resetModeMessagesForTesting() {
        recentModeMessages = []
    }
}
