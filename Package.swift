// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Xenon",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Xenon",
            resources: [.process("Resources")]
        )
    ]
)
