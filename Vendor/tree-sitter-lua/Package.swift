// swift-tools-version:5.9
//
// Vendored tree-sitter-lua grammar (local SPM package).
// Sources from https://github.com/tree-sitter-grammars/tree-sitter-lua @ v0.5.0.
//
// The upstream Package.swift conditionally includes src/scanner.c via
// FileManager.default.fileExists, which Xcode's SPM integration evaluates
// against the wrong working directory (omitting scanner.c and breaking the
// link with undefined external-scanner symbols). This local copy statically
// lists both C sources to avoid that.
import PackageDescription

let package = Package(
    name: "TreeSitterLua",
    products: [
        .library(name: "TreeSitterLua", targets: ["TreeSitterLua"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter.git", from: "0.10.0"),
    ],
    targets: [
        .target(
            name: "TreeSitterLua",
            dependencies: [],
            path: ".",
            sources: ["src/parser.c", "src/scanner.c"],
            resources: [
                .copy("queries"),
            ],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        ),
    ],
    cLanguageStandard: .c11
)
