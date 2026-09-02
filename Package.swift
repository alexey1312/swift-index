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
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.2"),

        // Parsing - Tree-sitter core (grammars added separately)
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter.git", from: "0.25.0"),

        // Embeddings
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.31.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "3.31.4"),
        // swift-transformers >= 1.1.7 links ibireme/yyjson, which duplicates the yyjson.c
        // symbols vendored by swift-yyjson (Cyyjson) and fails the link. Stay on 1.1.6
        // until swift-yyjson depends on the upstream yyjson package instead of vendoring.
        // swift-embeddings 0.1.0 requires swift-transformers >= 1.3.3, so it is capped too.
        .package(url: "https://github.com/jkrukowski/swift-embeddings.git", "0.0.25" ..< "0.1.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", exact: "1.1.6"),

        // Storage
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
        .package(url: "https://github.com/unum-cloud/usearch.git", from: "2.26.2"),

        // Configuration
        .package(url: "https://github.com/mattt/swift-toml.git", from: "2.0.0"),

        // Output format
        .package(url: "https://github.com/toon-format/toon-swift.git", from: "0.4.0"),

        // CLI
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.2"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.15.0"),
        .package(url: "https://github.com/tuist/Noora.git", from: "0.57.0"),

        // Collections
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.6.0"),

        // Crypto (for file hashing)
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.5.2"),

        // JSON codec (faster than Foundation, RFC 8259 strict mode)
        .package(
            url: "https://github.com/mattt/swift-yyjson.git",
            from: "0.6.0",
            traits: ["strictStandardJSON"]
        ),

        // Signal handling
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.102.0"),
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
