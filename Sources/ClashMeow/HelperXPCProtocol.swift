import Foundation

@objc(HelperXPCProtocol)
protocol HelperXPCProtocol {
    func releasePorts(
        _ ports: [NSNumber],
        excludingPID: NSNumber,
        reply: @escaping ([String], NSError?) -> Void
    )

    func startCore(
        executablePath: String,
        configDirectory: String,
        configFile: String,
        logFile: String,
        reply: @escaping (NSNumber, NSError?) -> Void
    )

    func restartCore(
        executablePath: String,
        configDirectory: String,
        configFile: String,
        logFile: String,
        reply: @escaping (NSNumber, NSError?) -> Void
    )

    func stopCore(reply: @escaping (NSError?) -> Void)

    func version(reply: @escaping (String) -> Void)
}
