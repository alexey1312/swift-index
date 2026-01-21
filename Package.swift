// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-index",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SwiftIndexCore",
            targets: ["SwiftIndexCore"]
        ),
        .library(
            name: "SwiftIndexMCP",
            targets: ["SwiftIndexMCP"]
        ),
        .executable(
            name: "swiftindex",
            targets: ["swiftindex"]
        ),
    ],
    dependencies: [
        // Parsing - SwiftSyntax for Swift files
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),

        // Parsing - Tree-sitter core (grammars added separately)
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter.git", from: "0.9.0"),

        // Embeddings
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.21.0"),
        .package(url: "https://github.com/jkrukowski/swift-embeddings.git", from: "0.0.25"),

        // Storage
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/unum-cloud/usearch.git", from: "2.16.0"),

        // Configuration
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),

        // CLI
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),

        // Async utilities
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),

        // Crypto (for file hashing)
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        // MARK: - Core Library
        .target(
            name: "SwiftIndexCore",
            dependencies: [
                // Parsing - Swift
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),

                // Parsing - Tree-sitter
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),

                // Embeddings
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "Embeddings", package: "swift-embeddings"),

                // Storage
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "USearch", package: "usearch"),

                // Configuration
                .product(name: "TOMLKit", package: "TOMLKit"),

                // Crypto
                .product(name: "Crypto", package: "swift-crypto"),

                // Utilities
                .product(name: "Logging", package: "swift-log"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            path: "Sources/SwiftIndexCore"
        ),

        // MARK: - MCP Server
        .target(
            name: "SwiftIndexMCP",
            dependencies: [
                "SwiftIndexCore",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/SwiftIndexMCP"
        ),

        // MARK: - CLI
        .executableTarget(
            name: "swiftindex",
            dependencies: [
                "SwiftIndexCore",
                "SwiftIndexMCP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/swiftindex"
        ),

        // MARK: - Tests
        .testTarget(
            name: "SwiftIndexCoreTests",
            dependencies: ["SwiftIndexCore"],
            path: "Tests/SwiftIndexCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "SwiftIndexMCPTests",
            dependencies: ["SwiftIndexMCP"],
            path: "Tests/SwiftIndexMCPTests"
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                "SwiftIndexCore",
                "SwiftIndexMCP",
            ],
            path: "Tests/IntegrationTests"
        ),
    ]
)
