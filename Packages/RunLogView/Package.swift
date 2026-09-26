// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RunLogView",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "RunLogView", targets: ["RunLogView"])
    ],
    targets: [
        .target(name: "RunLogView", resources: [.process("Resources")]),
        .testTarget(name: "RunLogViewTests", dependencies: ["RunLogView"])
    ]
)
