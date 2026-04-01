// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RedisConsole",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RedisConsole",
            path: "Sources/RedisConsole"
        )
    ]
)
