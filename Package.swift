// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RedisConsole",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "RedisConsole",
            dependencies: [
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
            ],
            path: "Sources/RedisConsole"
        )
    ]
)
