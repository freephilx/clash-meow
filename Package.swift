// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClashMeow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ClashMeow", targets: ["ClashMeow"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .executableTarget(
            name: "ClashMeow",
            dependencies: [
                "Yams"
            ],
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ClashMeowTests",
            dependencies: ["ClashMeow"]
        )
    ]
)
