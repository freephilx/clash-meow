import Foundation
import Testing
@testable import ClashMeow

struct PortOccupancyReleaserTests {
    @Test func administratorReleaseUsesNormalPermissionForOwnedProcessFirst() throws {
        let portFile = FileManager.default.temporaryDirectory
            .appending(path: "clash-meow-port-test-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: portFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "-c",
            """
            import signal
            import socket
            import sys

            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("127.0.0.1", 0))
            sock.listen(1)
            with open(sys.argv[1], "w") as file:
                file.write(str(sock.getsockname()[1]))
            signal.pause()
            """,
            portFile.path
        ]

        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: portFile.path), Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        let portText = try String(contentsOf: portFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let port = try #require(Int(portText))

        PortOccupancyReleaser.releaseUsingAdministratorPrivileges(ports: [port])

        let terminationDeadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < terminationDeadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }

        #expect(!process.isRunning)
    }
}
