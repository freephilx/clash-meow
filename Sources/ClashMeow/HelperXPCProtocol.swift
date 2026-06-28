import Foundation

@objc(HelperXPCProtocol)
protocol HelperXPCProtocol {
    func releasePorts(
        _ ports: [NSNumber],
        excludingPID: NSNumber,
        reply: @escaping ([String], NSError?) -> Void
    )

    func version(reply: @escaping (String) -> Void)
}
