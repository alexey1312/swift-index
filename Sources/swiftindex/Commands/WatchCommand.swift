// MARK: - Watch Command

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

/// Command to watch a directory for changes and update the index.
///
/// Usage:
///   swiftindex watch
///   swiftindex watch /path/to/project
struct WatchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Watch for file changes and update index incrementally",
        discussion: """
        Monitors the specified directory for file changes and automatically
        updates the index. Uses debouncing to batch rapid changes.

        Press Ctrl+C to stop watching.
        """
    )

    // MARK: - Arguments

    @Argument(
        help: "Path to the directory to watch (default: current directory)"
    )
    var path: String = "."

    // MARK: - Options

    @Option(
        name: .shortAndLong,
        help: "Path to configuration file"
    )
    var config: String?

    @Option(
        name: .long,
        help: "Debounce interval in milliseconds"
    )
    var debounce: Int?

    @Flag(
        name: .shortAndLong,
        help: "Enable verbose debug output"
    )
    var verbose: Bool = false

    // MARK: - Execution

    mutating func run() async throws {
        // Capture verbose flag before escaping closure
        let verboseFlag = verbose

        // Configure logging to stderr
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = verboseFlag ? .debug : .info
            return handler
        }

        let logger = CLIUtils.makeLogger(verbose: verbose)
        logger.info("Starting watch mode")

        // Resolve path
        let resolvedPath = CLIUtils.resolvePath(path)
        logger.debug("Resolved path: \(resolvedPath)")

        // Validate path exists
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw ValidationError("Path does not exist: \(resolvedPath)")
        }

        // Load configuration
        var configuration = try CLIUtils.loadConfig(from: config, projectDirectory: resolvedPath, logger: logger)

        // Override debounce if specified
        if let debounce {
            configuration.watchDebounceMs = debounce
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

        // Create embedding provider chain
        let embeddingProvider = createEmbeddingProvider(config: configuration, logger: logger)

        // Check provider availability
        guard await embeddingProvider.isAvailable() else {
            throw ValidationError("No embedding provider available. Check your configuration.")
        }

        // Create index manager
        let indexManager = try IndexManager(
            directory: indexPath,
            dimension: embeddingProvider.dimension
        )

        // Load existing index
        try await indexManager.load()

        // Get initial stats
        let initialStats = try await indexManager.statistics()

        print("Watching: \(resolvedPath)")
        print("Index path: \(indexPath)")
        print("Debounce: \(configuration.watchDebounceMs)ms")
        print("Current index: \(initialStats.chunkCount) chunks from \(initialStats.fileCount) files")
        print("")
        print("Press Ctrl+C to stop")
        print("")

        // Create incremental indexer
        let incrementalIndexer = IncrementalIndexer(
            indexManager: indexManager,
            parser: HybridParser(),
            embeddingProvider: embeddingProvider,
            config: configuration,
            logger: logger
        )

        // Setup signal handler for stats display on Ctrl+C
        let isVerbose = verbose
        let statsTask = Task {
            // Periodically print stats if verbose
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))

                if isVerbose {
                    let stats = await incrementalIndexer.getStats()
                    if stats.totalChanges > 0 {
                        let created = stats.filesCreated
                        let modified = stats.filesModified
                        let deleted = stats.filesDeleted
                        print("\n[Stats] Created: \(created), Modified: \(modified)")
                        print("        Deleted: \(deleted), Errors: \(stats.errors)")
                    }
                }
            }
        }

        // Start watching and indexing
        do {
            try await withTaskCancellationHandler {
                try await incrementalIndexer.watchAndIndex(path: resolvedPath)
            } onCancel: {
                // Note: This Task is detached and not awaited, but we ensure
                // stop() completes via the explicit call below
                Task {
                    await incrementalIndexer.stop()
                }
            }
        } catch {
            if Task.isCancelled {
                // Normal cancellation - fall through to cleanup
            } else {
                throw error
            }
        }

        // Ensure graceful shutdown completes before process exit.
        // This is critical because the onCancel handler creates a detached Task
        // that may not complete before we reach the end of run().
        // Calling stop() again is safe - it's a no-op if already stopped.
        await incrementalIndexer.stop()

        // Cancel stats task
        statsTask.cancel()

        // Print final stats
        let finalStats = await incrementalIndexer.getStats()
        print("\n")
        print("Watch session ended")
        print("Files created: \(finalStats.filesCreated)")
        print("Files modified: \(finalStats.filesModified)")
        print("Files deleted: \(finalStats.filesDeleted)")
        print("Chunks added: \(finalStats.chunksAdded)")
        print("Chunks removed: \(finalStats.chunksRemoved)")
        if finalStats.errors > 0 {
            print("Errors: \(finalStats.errors)")
        }

        // Save index
        try await indexManager.save()

        logger.info("Watch mode stopped")
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
}
