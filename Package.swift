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
    targets: [
        .executableTarget(
            name: "ClashMeow",
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
