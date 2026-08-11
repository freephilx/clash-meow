// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DouClash",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DouClash", targets: ["DouClash"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .executableTarget(
            name: "DouClash",
            dependencies: [
                "Yams"
            ],
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DouClashTests",
            dependencies: ["DouClash"]
        )
    ]
)
