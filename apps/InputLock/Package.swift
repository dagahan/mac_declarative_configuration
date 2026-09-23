// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "InputLock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "InputLock", path: "Sources/InputLock")
    ]
)
