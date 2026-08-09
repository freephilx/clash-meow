// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DouMeow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DouMeow", targets: ["DouMeow"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .executableTarget(
            name: "DouMeow",
            dependencies: [
                "Yams"
            ],
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DouMeowTests",
            dependencies: ["DouMeow"]
        )
    ]
)
