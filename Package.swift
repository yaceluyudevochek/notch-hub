// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NotchHub",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchHub",
            path: "Sources/NotchHub"
        )
    ]
)
