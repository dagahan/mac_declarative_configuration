// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Desk",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DeskRule", path: "Sources/DeskRule"),
        .executableTarget(name: "Desk", dependencies: ["DeskRule"], path: "Sources/Desk"),
        .testTarget(
            name: "DeskRuleTests",
            dependencies: ["DeskRule"],
            path: "Tests/DeskRuleTests",
            resources: [.copy("undock-session.jsonl")]
        ),
    ]
)
