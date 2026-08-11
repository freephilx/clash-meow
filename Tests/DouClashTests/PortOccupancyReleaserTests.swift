import Foundation
import Testing
@testable import DouClash

struct PortOccupancyReleaserTests {
    @Test func administratorReleaseUsesNormalPermissionForOwnedProcessFirst() throws {
        let process = Process()
        let standardOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "-c",
            """
            import signal
            import socket

            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("127.0.0.1", 0))
            sock.listen(1)
            print(sock.getsockname()[1], flush=True)
            signal.pause()
            """
        ]

        process.standardOutput = standardOutput
        process.standardError = Pipe()
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        let portText = String(data: standardOutput.fileHandleForReading.availableData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let port = try #require(portText.flatMap(Int.init))

        PortOccupancyReleaser.releaseUsingAdministratorPrivileges(ports: [port])

        let terminationDeadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < terminationDeadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }

        #expect(!process.isRunning)
    }
}
