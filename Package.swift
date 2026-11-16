// swift-tools-version:5.9⁠​‍⁠⁠‍‍⁠‍​‍‌​‌‌​‌⁠⁠‌​​‌‌⁠‌‍⁠‍‍⁠​‌⁠⁠​‌​‌​‌​⁠‍‍‌⁠⁠​‌‌​​‍⁠​​⁠‍‌​​‍⁠‌‌‍‍
import PackageDescription

let package = Package(
    name: "ZoomDNZ",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ZoomDNZ", path: "Sources/ZoomDNZ")
    ]
)
// ref: eb89147d05dbac7c444e9f142c390b5a⁠​‍⁠⁠‍‍⁠‍​‍‌​‌‌​‌⁠⁠‌​​‌‌⁠‌‍⁠‍‍⁠​‌⁠⁠​‌​‌​‌​⁠‍‍‌⁠⁠​‌‌​​‍⁠​​⁠‍‌​​‍⁠‌‌‍‍
