// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-index",
    platforms: [
        .macOS(.v14),
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
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.30.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main"),
        .package(url: "https://github.com/jkrukowski/swift-embeddings.git", from: "0.0.25"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.1.6"),

        // Storage
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0"),
        .package(url: "https://github.com/unum-cloud/usearch.git", from: "2.23.0"),

        // Configuration
        .package(url: "https://github.com/alexey1312/swift-toml.git", from: "1.0.0"),

        // Output format
        .package(url: "https://github.com/toon-format/toon-swift.git", from: "0.3.0"),

        // CLI
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.9.0"),
        .package(url: "https://github.com/tuist/Noora.git", from: "0.54.0"),

        // Async utilities
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.1.0"),

        // Collections
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),

        // Crypto (for file hashing)
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),

        // JSON codec (faster than Foundation, RFC 8259 strict mode)
        .package(
            url: "https://github.com/mattt/swift-yyjson.git",
            from: "0.3.0",
            traits: ["strictStandardJSON"]
        ),

        // Signal handling
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.62.0"),
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
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "Embeddings", package: "swift-embeddings"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "Tokenizers", package: "swift-transformers"),

                // LLM (MLX-based local text generation)
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),

                // Storage
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "USearch", package: "usearch"),

                // Configuration
                .product(name: "TOML", package: "swift-toml"),

                // Crypto
                .product(name: "Crypto", package: "swift-crypto"),

                // Utilities
                .product(name: "Logging", package: "swift-log"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),

                // JSON codec
                .product(name: "YYJSON", package: "swift-yyjson"),
            ],
            path: "Sources/SwiftIndexCore"
        ),

        // MARK: - MCP Server

        .target(
            name: "SwiftIndexMCP",
            dependencies: [
                "SwiftIndexCore",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "ToonFormat", package: "toon-swift"),
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
                .product(name: "ToonFormat", package: "toon-swift"),
                .product(name: "Noora", package: "Noora"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "Sources/swiftindex"
        ),

        // MARK: - Tests

        .testTarget(
            name: "SwiftIndexCoreTests",
            dependencies: ["SwiftIndexCore"],
            path: "Tests/SwiftIndexCoreTests",
            resources: [
                .copy("Fixtures"),
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
