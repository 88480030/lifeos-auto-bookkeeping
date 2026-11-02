// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LifeOSCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LifeOSCore", targets: ["LifeOSCore"])
    ],
    targets: [
        .target(
            name: "LifeOSCore",
            path: "Sources/LifeOSCore"
        ),
        .testTarget(
            name: "LifeOSCoreTests",
            dependencies: ["LifeOSCore"],
            path: "Tests/LifeOSCoreTests"
        )
    ]
)
