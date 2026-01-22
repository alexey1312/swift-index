// MARK: - Search Command

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

/// Command to search the indexed codebase.
///
/// Usage:
///   swiftindex search "authentication flow"
///   swiftindex search "error handling" --limit 10
///   swiftindex search "async patterns" --json
struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search the indexed codebase",
        discussion: """
        Performs hybrid semantic search combining BM25 keyword matching
        with vector similarity search using RRF (Reciprocal Rank Fusion).

        Results include code chunks with context, file paths, and
        relevance scores.
        """
    )

    // MARK: - Arguments

    @Argument(
        help: "Search query (natural language or code pattern)"
    )
    var query: String

    // MARK: - Options

    @Option(
        name: .shortAndLong,
        help: "Maximum number of results to return"
    )
    var limit: Int = 20

    @Flag(
        name: .long,
        help: "Output results as JSON"
    )
    var json: Bool = false

    @Option(
        name: .shortAndLong,
        help: "Path to configuration file"
    )
    var config: String?

    @Option(
        name: .shortAndLong,
        help: "Path to the indexed codebase (default: current directory)"
    )
    var path: String = "."

    @Option(
        name: .long,
        help: "Semantic weight (0.0 = BM25 only, 1.0 = semantic only)"
    )
    var semanticWeight: Float = 0.7

    @Option(
        name: .long,
        help: "Filter by file extension (comma-separated, e.g., swift,ts)"
    )
    var extensions: String?

    @Option(
        name: .long,
        help: "Filter by path pattern (glob syntax)"
    )
    var pathFilter: String?

    @Flag(
        name: .long,
        help: "Enable multi-hop reference following"
    )
    var multiHop: Bool = false

    @Flag(
        name: .shortAndLong,
        help: "Enable verbose debug output"
    )
    var verbose: Bool = false

    // MARK: - Execution

    mutating func run() async throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        logger.info("Starting search", metadata: ["query": "\(query)"])

        // Resolve path
        let resolvedPath = CLIUtils.resolvePath(path)
        logger.debug("Resolved path: \(resolvedPath)")

        // Load configuration
        let configuration = try CLIUtils.loadConfig(from: config, logger: logger)

        // Validate limit
        guard limit > 0 else {
            throw ValidationError("Limit must be greater than 0")
        }

        // Validate semantic weight
        guard semanticWeight >= 0, semanticWeight <= 1 else {
            throw ValidationError("Semantic weight must be between 0.0 and 1.0")
        }

        logger.debug("Search configuration", metadata: [
            "limit": "\(limit)",
            "semanticWeight": "\(semanticWeight)",
            "rrfK": "\(configuration.rrfK)",
        ])

        // Determine index path
        let indexPath = (resolvedPath as NSString).appendingPathComponent(configuration.indexPath)

        // Check if index exists
        guard FileManager.default.fileExists(atPath: indexPath) else {
            throw ValidationError(
                """
                Index not found at: \(indexPath)
                Run 'swiftindex index' first to create the index.
                """
            )
        }

        // Create embedding provider chain
        let embeddingProvider = createEmbeddingProvider(config: configuration, logger: logger)

        // Check provider availability
        guard await embeddingProvider.isAvailable() else {
            throw ValidationError("No embedding provider available. Check your configuration.")
        }

        // Create index manager and load index
        let indexManager = try IndexManager(
            directory: indexPath,
            dimension: embeddingProvider.dimension
        )
        try await indexManager.load()

        // Verify index has data
        let stats = try await indexManager.statistics()
        guard stats.chunkCount > 0 else {
            throw ValidationError(
                """
                Index is empty. No chunks to search.
                Run 'swiftindex index' first to populate the index.
                """
            )
        }

        if !json {
            print("Searching: \"\(query)\"")
            print("Index: \(stats.chunkCount) chunks from \(stats.fileCount) files")
            print("Limit: \(limit)")
        }

        // Create search engine using stores from index manager
        let chunkStore = await indexManager.chunkStore
        let vectorStore = await indexManager.vectorStore
        let searchEngine = HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: embeddingProvider,
            rrfK: configuration.rrfK
        )

        // Build search options
        var extensionFilter: Set<String>?
        if let extensions {
            extensionFilter = Set(extensions.split(separator: ",").map { String($0).lowercased() })
        }

        let searchOptions = SearchOptions(
            limit: limit,
            semanticWeight: semanticWeight,
            pathFilter: pathFilter,
            extensionFilter: extensionFilter,
            rrfK: configuration.rrfK,
            multiHop: multiHop,
            multiHopDepth: multiHop ? 2 : 0
        )

        // Execute search
        let startTime = Date()
        let results = try await searchEngine.search(query: query, options: searchOptions)
        let elapsed = Date().timeIntervalSince(startTime)

        logger.info("Search completed", metadata: [
            "results": "\(results.count)",
            "elapsed": "\(String(format: "%.3f", elapsed))s",
        ])

        // Output results
        if json {
            try outputJSON(results: results, query: query, elapsed: elapsed)
        } else {
            outputHumanReadable(results: results, elapsed: elapsed)
        }
    }

    // MARK: - Private Helpers

    private func createEmbeddingProvider(
        config: Config,
        logger: Logger
    ) -> EmbeddingProviderChain {
        switch config.embeddingProvider.lowercased() {
        case "mock":
            logger.debug("Using mock embedding provider")
            return EmbeddingProviderChain(
                providers: [MockEmbeddingProvider()],
                id: "mock-chain",
                name: "Mock Embeddings"
            )

        case "mlx":
            logger.debug("Using MLX embedding provider")
            return EmbeddingProviderChain(
                providers: [MLXEmbeddingProvider(), SwiftEmbeddingsProvider()],
                id: "mlx-chain",
                name: "MLX with Swift Embeddings fallback"
            )

        case "swift-embeddings", "swift", "swiftembeddings":
            logger.debug("Using Swift Embeddings provider")
            return EmbeddingProviderChain.softwareOnly

        case "ollama":
            logger.debug("Using Ollama embedding provider")
            return EmbeddingProviderChain(
                providers: [
                    OllamaEmbeddingProvider(
                        modelName: config.embeddingModel,
                        dimension: config.embeddingDimension
                    ),
                    SwiftEmbeddingsProvider(),
                ],
                id: "ollama-chain",
                name: "Ollama with fallback"
            )

        case "voyage":
            logger.debug("Using Voyage AI embedding provider")
            if let apiKey = config.voyageAPIKey {
                return EmbeddingProviderChain(
                    providers: [
                        VoyageProvider(
                            apiKey: apiKey,
                            modelName: config.embeddingModel,
                            dimension: config.embeddingDimension
                        ),
                        SwiftEmbeddingsProvider(),
                    ],
                    id: "voyage-chain",
                    name: "Voyage AI with fallback"
                )
            } else {
                logger.warning("VOYAGE_API_KEY not set, falling back to local provider")
                return EmbeddingProviderChain.default
            }

        case "openai":
            logger.debug("Using OpenAI embedding provider")
            if let apiKey = config.openAIAPIKey {
                return EmbeddingProviderChain(
                    providers: [
                        OpenAIProvider(apiKey: apiKey),
                        SwiftEmbeddingsProvider(),
                    ],
                    id: "openai-chain",
                    name: "OpenAI with fallback"
                )
            } else {
                logger.warning("OPENAI_API_KEY not set, falling back to local provider")
                return EmbeddingProviderChain.default
            }

        case "auto":
            logger.debug("Using auto provider selection")
            return EmbeddingProviderChain.default

        default:
            logger.debug("Unknown provider '\(config.embeddingProvider)', using default chain")
            return EmbeddingProviderChain.default
        }
    }

    private func outputJSON(results: [SearchResult], query: String, elapsed: TimeInterval) throws {
        var jsonResults: [[String: Any]] = []

        for result in results {
            var item: [String: Any] = [
                "id": result.chunk.id,
                "path": result.chunk.path,
                "startLine": result.chunk.startLine,
                "endLine": result.chunk.endLine,
                "kind": result.chunk.kind.rawValue,
                "symbols": result.chunk.symbols,
                "score": Double(result.score),
                "content": result.chunk.content,
            ]

            if let bm25Score = result.bm25Score {
                item["bm25Score"] = Double(bm25Score)
            }
            if let semanticScore = result.semanticScore {
                item["semanticScore"] = Double(semanticScore)
            }
            if let bm25Rank = result.bm25Rank {
                item["bm25Rank"] = bm25Rank
            }
            if let semanticRank = result.semanticRank {
                item["semanticRank"] = semanticRank
            }
            if result.isMultiHop {
                item["isMultiHop"] = true
                item["hopDepth"] = result.hopDepth
            }

            jsonResults.append(item)
        }

        let output: [String: Any] = [
            "query": query,
            "resultCount": results.count,
            "elapsedSeconds": elapsed,
            "results": jsonResults,
        ]

        if let jsonData = try? JSONSerialization.data(
            withJSONObject: output,
            options: [.prettyPrinted, .sortedKeys]
        ),
            let jsonString = String(data: jsonData, encoding: .utf8)
        {
            print(jsonString)
        }
    }

    private func outputHumanReadable(results: [SearchResult], elapsed: TimeInterval) {
        print("")

        if results.isEmpty {
            print("No results found.")
            return
        }

        print("Found \(results.count) results in \(String(format: "%.3f", elapsed))s")
        print(String(repeating: "─", count: 60))

        for (index, result) in results.enumerated() {
            let scoreStr = String(format: "%.3f", result.score)
            let hopIndicator = result.isMultiHop ? " [hop \(result.hopDepth)]" : ""

            print("\n[\(index + 1)] \(result.chunk.path):\(result.chunk.startLine)-\(result.chunk.endLine)")
            print("    Kind: \(result.chunk.kind.rawValue)\(hopIndicator)")

            if !result.chunk.symbols.isEmpty {
                print("    Symbols: \(result.chunk.symbols.joined(separator: ", "))")
            }

            print("    Score: \(scoreStr)", terminator: "")

            if let bm25 = result.bm25Score, let semantic = result.semanticScore {
                print(" (BM25: \(String(format: "%.3f", bm25)), Semantic: \(String(format: "%.3f", semantic)))")
            } else if let bm25 = result.bm25Score {
                print(" (BM25: \(String(format: "%.3f", bm25)))")
            } else if let semantic = result.semanticScore {
                print(" (Semantic: \(String(format: "%.3f", semantic)))")
            } else {
                print("")
            }

            // Show code preview (first 5 lines)
            let lines = result.chunk.content.split(separator: "\n", omittingEmptySubsequences: false)
            let preview = lines.prefix(5).joined(separator: "\n")
            print("    ────")
            for line in preview.split(separator: "\n", omittingEmptySubsequences: false) {
                print("    \(line)")
            }
            if lines.count > 5 {
                print("    ... (\(lines.count - 5) more lines)")
            }
        }

        print("")
    }
}
