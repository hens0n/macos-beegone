// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BeeGone",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BeeGone",
            path: "BeeGone",
            exclude: ["Info.plist", "BeeGone.entitlements"],
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "BeeGoneTests",
            dependencies: ["BeeGone"],
            path: "Tests/BeeGoneTests"
        )
    ]
)
