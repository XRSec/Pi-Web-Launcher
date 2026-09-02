// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PiWeb",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(
            name: "PiWeb",
            path: "Sources/PiWeb"
        )
    ]
)
