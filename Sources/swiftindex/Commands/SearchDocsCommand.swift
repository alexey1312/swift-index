// MARK: - Search Docs Command

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore
import ToonFormat

/// Command to search indexed documentation.
///
/// Usage:
///   swiftindex search-docs "install dependencies"
///   swiftindex search-docs "api authentication" --limit 5
///   swiftindex search-docs "configuration" --format json
struct SearchDocsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search-docs",
        abstract: "Search indexed documentation",
        discussion: """
        Performs full-text search on documentation content, including
        Markdown files, README sections, and other documentation snippets.
        """
    )

    // MARK: - Arguments

    @Argument(
        help: "Search query (natural language)"
    )
    var query: String

    // MARK: - Options

    @Option(
        name: .shortAndLong,
        help: "Maximum number of results to return (default: 10)"
    )
    var limit: Int = 10

    @Option(
        name: .long,
        help: "Output format: human, json, or toon (token-optimized). Default: toon"
    )
    var format: OutputFormat = .toon

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
        help: "Filter by path pattern (glob syntax)"
    )
    var pathFilter: String?

    @Flag(
        name: .shortAndLong,
        help: "Enable verbose debug output"
    )
    var verbose: Bool = false

    // MARK: - Execution

    mutating func run() async throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        logger.info("Starting documentation search", metadata: ["query": "\(query)"])

        // Resolve path
        let resolvedPath = CLIUtils.resolvePath(path)
        logger.debug("Resolved path: \(resolvedPath)")

        // Load configuration (requires initialization)
        let configuration: Config
        do {
            configuration = try CLIUtils.loadConfig(
                from: config,
                projectDirectory: resolvedPath,
                logger: logger,
                requireInitialization: true
            )
        } catch ConfigError.notInitialized {
            print("No configuration found.")
            print("")
            print("Run 'swiftindex init' first to create a configuration file,")
            print("then 'swiftindex index' to build the index.")
            throw ExitCode.failure
        }

        // Validate limit
        guard limit > 0 else {
            throw ValidationError("Limit must be greater than 0")
        }

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

        // Create embedding provider chain (needed for IndexManager, though not used for doc search which uses BM25/FTS)
        // We reuse the logic from SearchCommand to ensure correct initialization
        let embeddingProvider = try createEmbeddingProvider(config: configuration, logger: logger)

        // Create index manager and load index
        let indexManager = try IndexManager(
            directory: indexPath,
            dimension: embeddingProvider.dimension
        )
        try await indexManager.load()

        // Create search engine
        let chunkStore = await indexManager.chunkStore
        let vectorStore = await indexManager.vectorStore
        let searchEngine = HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: embeddingProvider,
            rrfK: configuration.rrfK
        )

        let startTime = Date()

        // Execute search
        let results = try await searchEngine.searchInfoSnippets(
            query: query,
            limit: limit,
            pathFilter: pathFilter
        )

        let elapsed = Date().timeIntervalSince(startTime)

        logger.info("Search completed", metadata: [
            "results": "\(results.count)",
            "elapsed": "\(String(format: "%.3f", elapsed))s",
        ])

        // Output results
        switch format {
        case .human:
            outputHumanReadable(results: results, elapsed: elapsed)
        case .json:
            try outputJSON(results: results, query: query, elapsed: elapsed)
        case .toon:
            outputTOON(results: results, query: query, elapsed: elapsed)
        }
    }

    // MARK: - Helpers

    private func createEmbeddingProvider(
        config: Config,
        logger: Logger
    ) throws -> EmbeddingProviderChain {
        // Reuse logic from SearchCommand via duplication for now to avoid refactoring shared code
        // Ideally this should be in a shared utility
        switch config.embeddingProvider.lowercased() {
        case "mock":
            return EmbeddingProviderChain(
                providers: [MockEmbeddingProvider()],
                id: "mock-chain",
                name: "Mock Embeddings"
            )

        case "mlx":
            return EmbeddingProviderChain(
                providers: [
                    MLXEmbeddingProvider(
                        huggingFaceId: config.embeddingModel,
                        dimension: config.embeddingDimension
                    ),
                    SwiftEmbeddingsProvider(),
                ],
                id: "mlx-chain",
                name: "MLX with Swift Embeddings fallback"
            )

        case "swift-embeddings", "swift", "swiftembeddings":
            return EmbeddingProviderChain.softwareOnly

        case "ollama":
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
                throw ProviderError.apiKeyMissing(provider: "Voyage AI")
            }

        case "openai":
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
                throw ProviderError.apiKeyMissing(provider: "OpenAI")
            }

        case "auto":
            return EmbeddingProviderChain.default

        default:
            return EmbeddingProviderChain.default
        }
    }

    // MARK: - Output Formatters

    private func outputHumanReadable(results: [InfoSnippetSearchResult], elapsed: TimeInterval) {
        print("")

        if results.isEmpty {
            print("No documentation found.")
            return
        }

        print("Found \(results.count) results in \(String(format: "%.3f", elapsed))s")
        print(String(repeating: "─", count: 60))

        for (index, result) in results.enumerated() {
            print("\n[\(index + 1)] \(result.snippet.path):\(result.snippet.startLine)-\(result.snippet.endLine)")
            print("    Kind: \(result.snippet.kind.rawValue)")

            if let breadcrumb = result.snippet.breadcrumb {
                print("    Location: \(breadcrumb)")
            }

            print("    Relevance: \(result.relevancePercent)%")

            // Show content preview (first 10 lines)
            let lines = result.snippet.content.split(separator: "\n", omittingEmptySubsequences: false)
            let preview = lines.prefix(10)
            print("    ────")
            for line in preview {
                print("    \(line)")
            }
            if lines.count > 10 {
                print("    ... (\(lines.count - 10) more lines)")
            }
        }
        print("")
    }

    private func outputJSON(
        results: [InfoSnippetSearchResult],
        query: String,
        elapsed: TimeInterval
    ) throws {
        var jsonResults: [[String: Any]] = []

        for result in results {
            var item: [String: Any] = [
                "id": result.snippet.id,
                "path": result.snippet.path,
                "startLine": result.snippet.startLine,
                "endLine": result.snippet.endLine,
                "kind": result.snippet.kind.rawValue,
                "content": result.snippet.content,
                "tokenCount": result.snippet.tokenCount,
                "language": result.snippet.language,
                "relevancePercent": result.relevancePercent,
            ]

            if let breadcrumb = result.snippet.breadcrumb {
                item["breadcrumb"] = breadcrumb
            }

            if let chunkId = result.snippet.chunkId {
                item["chunkId"] = chunkId
            }

            jsonResults.append(item)
        }

        let output: [String: Any] = [
            "query": query,
            "resultCount": results.count,
            "elapsedSeconds": elapsed,
            "results": jsonResults,
        ]

        if let jsonData = try? JSONCodec.serialize(output, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            print(jsonString)
        }
    }

    private func outputTOON(
        results: [InfoSnippetSearchResult],
        query: String,
        elapsed: TimeInterval
    ) {
        let elapsedMs = Int(elapsed * 1000)

        var output = "docs_search{q,n,ms}:\n"
        output += "  \"\(escapeString(query))\",\(results.count),\(elapsedMs)\n"

        if results.isEmpty {
            print(output)
            return
        }

        // Tabular results: rank, relevance%, path, lines, kind, breadcrumb, lang, tokens
        output += "\nsnippets[\(results.count)]{r,rel,p,l,k,bc,lang,tok}:\n"

        for (index, result) in results.enumerated() {
            let rank = index + 1
            let relevance = result.relevancePercent
            let path = result.snippet.path
            let lines = "[\(result.snippet.startLine),\(result.snippet.endLine)]"
            let kind = result.snippet.kind.rawValue
            let bc = result.snippet.breadcrumb.map { "\"\(escapeString($0))\"" } ?? "~"
            let lang = result.snippet.language
            let tokens = result.snippet.tokenCount

            let row = "  \(rank),\(relevance),\"\(escapeString(path))\",\(lines),"
                + "\"\(kind)\",\(bc),\"\(lang)\",\(tokens)"
            output += row + "\n"
        }

        output += "\ncontent[\(results.count)]:\n"

        for result in results {
            // Truncate content for TOON output (first 20 lines max)
            let lines = result.snippet.content.split(separator: "\n", omittingEmptySubsequences: false)
            let preview = lines.prefix(20).joined(separator: "\n")
            let truncated = lines.count > 20

            output += "  ---\n"
            for line in preview.split(separator: "\n", omittingEmptySubsequences: false) {
                output += "  \(line)\n"
            }
            if truncated {
                output += "  ...\(lines.count - 20) more lines\n"
            }
        }

        print(output)
    }

    private func escapeString(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
