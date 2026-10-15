// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacCon",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MacCon"),
        .testTarget(name: "MacConTests", dependencies: ["MacCon"]),
    ]
)
