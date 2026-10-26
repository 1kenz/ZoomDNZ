// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZoomDNZ",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ZoomDNZ", path: "Sources/ZoomDNZ"),
        .testTarget(name: "ZoomDNZTests", dependencies: ["ZoomDNZ"], path: "Tests/ZoomDNZTests")
    ]
)
