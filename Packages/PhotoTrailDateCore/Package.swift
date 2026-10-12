// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PhotoTrailDateCore",
    products: [.library(name: "PhotoTrailDateCore", targets: ["PhotoTrailDateCore"])],
    targets: [
        .target(name: "PhotoTrailDateCore"),
        .testTarget(name: "PhotoTrailDateCoreTests", dependencies: ["PhotoTrailDateCore"],
                    resources: [.copy("Fixtures")])
    ]
)
