// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "RedisConsole",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "Vendor/swift-nio-ssh"),
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
