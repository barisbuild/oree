// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Oree",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Oree", path: "Sources/Oree")
    ]
)
