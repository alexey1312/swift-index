// MARK: - Index Command

import ArgumentParser
import Foundation
import Logging
import Noora
import SwiftIndexCore

/// Command to index a Swift codebase for semantic search.
///
/// Usage:
///   swiftindex index [path]
///   swiftindex index --force
///   swiftindex index --config path/to/config.toml
struct IndexCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "index",
        abstract: "Index a Swift codebase for semantic search",
        discussion: """
        Scans the specified directory for Swift files and other supported
        source files, parses them into semantic chunks, generates embeddings,
        and stores them in a local index.

        By default, only changed files are re-indexed. Use --force to
        rebuild the entire index from scratch.
        """
    )

    // MARK: - Arguments

    @Argument(
        help: "Path to the directory to index (default: current directory)"
    )
    var path: String = "."

    // MARK: - Options

    @Flag(
        name: .shortAndLong,
        help: "Force complete re-indexing, ignoring cached data"
    )
    var force: Bool = false

    @Option(
        name: .shortAndLong,
        help: "Path to configuration file"
    )
    var config: String?

    @Flag(
        name: .shortAndLong,
        help: "Enable verbose debug output"
    )
    var verbose: Bool = false

    // MARK: - Execution

    mutating func run() async throws {
        let verboseFlag = verbose
        let terminal = Terminal()
        let progressRenderer = StickyProgressRenderer(terminal: terminal)
        let descriptionState = DescriptionGenerationState()
        LoggingSystem.bootstrap { label in
            var handler = ProgressLogHandler(
                label: label,
                progressRenderer: progressRenderer,
                terminal: terminal
            )
            handler.logLevel = verboseFlag ? .debug : .info
            return handler
        }

        let logger = CLIUtils.makeLogger(verbose: verbose)
        logger.info("Starting index operation")

        // Setup graceful shutdown
        let shutdownManager = GracefulShutdownManager(logger: logger)
        await shutdownManager.start()

        let startTime = Date()

        let resolvedPath = try resolvePath(logger: logger)
        let configuration = try await loadConfigurationWithInitFallback(
            projectDirectory: FileManager.default.currentDirectoryPath,
            logger: logger
        )
        let indexPath = try createIndexDirectory(
            projectPath: resolvedPath,
            configuration: configuration
        )

        printStartupInfo(
            resolvedPath: resolvedPath,
            indexPath: indexPath,
            configuration: configuration,
            logger: logger
        )

        // Create embedding provider chain
        let embeddingProvider = try EmbeddingProviderFactory.createProvider(config: configuration, logger: logger)

        // Check provider availability
        try await ensureEmbeddingProviderAvailable(embeddingProvider)

        // Create index manager
        let indexManager = try await createIndexManager(
            indexPath: indexPath,
            embeddingProvider: embeddingProvider
        )

        // Create parser
        let parser = HybridParser()

        // Collect files to index
        print("\nScanning files...")
        let files = try FileCollector.collectFiles(
            at: resolvedPath,
            config: configuration,
            parser: parser,
            logger: logger
        )

        print("Found \(files.count) files to process")

        // Create description generator (auto-generates when LLM provider is available)
        let descriptionGenerator = DescriptionGeneratorFactory.create(config: configuration, logger: logger)
        await DescriptionGeneratorFactory.checkAvailability(descriptionGenerator, logger: logger)

        // Create embedding batcher for cross-file batching
        let batcherConfig = EmbeddingBatcher.Configuration(
            batchSize: configuration.embeddingBatchSize,
            timeoutMs: configuration.embeddingBatchTimeoutMs,
            memoryLimitMB: configuration.embeddingBatchMemoryLimitMB
        )
        let embeddingBatcher = EmbeddingBatcher(
            provider: embeddingProvider,
            configuration: batcherConfig
        )

        // Index files in parallel
        let stats = AtomicIndexingStats()
        let indexingContext = createIndexingContext(from: IndexingContextParams(
            indexManager: indexManager,
            parser: parser,
            embeddingBatcher: embeddingBatcher,
            descriptionGenerator: descriptionGenerator,
            descriptionState: descriptionState,
            progressRenderer: progressRenderer,
            terminal: terminal,
            projectPath: resolvedPath,
            logger: logger
        ))

        let maxConcurrentTasks = configuration.maxConcurrentTasks
        print("Parallel indexing with \(maxConcurrentTasks) concurrent tasks")

        // Use TaskGroup for parallel processing with bounded concurrency
        // Capture force as local constant to avoid capturing self
        let forceReindex = force
        let ui = Noora()
        var fatalError: Error?

        // Register shutdown handler to cancel indexing
        let indexingTask = Task { () -> Error? in
            var taskResult: Error?
            try await ui.progressBarStep(
                message: "Indexing files",
                successMessage: "Indexing completed",
                errorMessage: "Indexing failed",
                renderer: progressRenderer
            ) { updateProgress in
                taskResult = try await IndexCommand.runIndexingTasks(
                    files: files,
                    config: IndexingTaskConfig(
                        context: indexingContext,
                        stats: stats,
                        maxConcurrentTasks: maxConcurrentTasks,
                        forceReindex: forceReindex,
                        logger: logger,
                        reportProgress: { processed, inFlight, total in
                            let safeTotal = max(total, 1)
                            // Count in-flight files as 50% done to show clear immediate activity
                            let effectiveProcessed = Double(processed) + (Double(inFlight) * 0.5)
                            updateProgress(min(effectiveProcessed / Double(safeTotal), 1.0))
                        }
                    )
                )
            }
            return taskResult
        }

        await shutdownManager.onShutdown {
            indexingTask.cancel()
        }

        fatalError = try await indexingTask.value

        // Handle fatal errors after task group completes
        if let fatalError {
            print("\n")
            print("Error: \(fatalError.localizedDescription)")
            throw ExitCode.failure
        }

        // Flush any remaining embedding requests
        try await embeddingBatcher.flush()

        // Save index
        try await indexManager.save()

        // Final statistics
        try await printFinalStatistics(
            startTime: startTime,
            stats: stats,
            indexManager: indexManager,
            logger: logger
        )
    }

    private func printFinalStatistics(
        startTime: Date,
        stats: AtomicIndexingStats,
        indexManager: IndexManager,
        logger: Logger
    ) async throws {
        let elapsed = Date().timeIntervalSince(startTime)
        let statistics = try await indexManager.statistics()
        let finalStats = stats.snapshot()

        print("\n")
        print("Indexing completed in \(String(format: "%.2f", elapsed)) seconds")
        print("Files processed: \(finalStats.filesProcessed)")
        print("Files skipped (unchanged): \(finalStats.filesSkipped)")
        print("Chunks indexed: \(finalStats.chunksIndexed)")
        if finalStats.chunksReused > 0 {
            print("Chunks reused (no re-embedding): \(finalStats.chunksReused)")
        }
        if finalStats.snippetsIndexed > 0 {
            print("Documentation snippets indexed: \(finalStats.snippetsIndexed)")
        }
        if finalStats.descriptionsGenerated > 0 {
            print("Descriptions generated: \(finalStats.descriptionsGenerated)")
        }
        print("Total chunks in index: \(statistics.chunkCount)")
        if statistics.snippetCount > 0 {
            print("Total snippets in index: \(statistics.snippetCount)")
        }
        print("Total files in index: \(statistics.fileCount)")

        if finalStats.errors > 0 {
            print("Errors: \(finalStats.errors)")
        }

        logger.info("Index operation completed")
    }

    // MARK: - Private Helpers

    private func resolvePath(logger: Logger) throws -> String {
        let resolvedPath = CLIUtils.resolvePath(path)
        logger.debug("Resolved path: \(resolvedPath)")

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw ValidationError("Path does not exist: \(resolvedPath)")
        }

        return resolvedPath
    }

    private func loadConfigurationWithInitFallback(
        projectDirectory: String,
        logger: Logger
    ) async throws -> Config {
        do {
            return try loadConfiguration(projectDirectory: projectDirectory, logger: logger)
        } catch ConfigError.notInitialized {
            // No config file exists - offer to initialize
            return try await handleNotInitialized(projectDirectory: projectDirectory, logger: logger)
        }
    }

    private func handleNotInitialized(
        projectDirectory: String,
        logger: Logger
    ) async throws -> Config {
        let ui = Noora()
        let isInteractive = isatty(STDIN_FILENO) == 1

        print("No configuration found.")
        print("")
        print("SwiftIndex requires a configuration file to determine embedding")
        print("provider, model settings, and indexing options.")
        print("")

        if isInteractive {
            let runInit = ui.yesOrNoChoicePrompt(
                question: "Would you like to initialize configuration now?",
                defaultAnswer: true,
                description: "This will run 'swiftindex init' to create .swiftindex.toml"
            )

            if !runInit {
                print("")
                print("To initialize manually, run: swiftindex init")
                throw ExitCode.failure
            }

            print("")

            // Run init command
            var initCommand = InitCommand()
            try await initCommand.run()

            print("")
            print("Continuing with indexing...")
            print("")

            // Reload configuration after init
            return try loadConfiguration(projectDirectory: projectDirectory, logger: logger)
        } else {
            // Non-interactive mode - just show error
            print("Run 'swiftindex init' to create a configuration file.")
            print("")
            print("Example:")
            print("  swiftindex init              # Interactive setup")
            print("  swiftindex init --provider mlx  # Use MLX defaults")
            throw ExitCode.failure
        }
    }

    private func loadConfiguration(
        projectDirectory: String,
        logger: Logger
    ) throws -> Config {
        let configuration = try CLIUtils.loadConfig(
            from: config,
            projectDirectory: projectDirectory,
            logger: logger,
            requireInitialization: true
        )
        logger.debug("Configuration loaded", metadata: [
            "provider": "\(configuration.embeddingProvider)",
            "model": "\(configuration.embeddingModel)",
        ])
        return configuration
    }

    private func createIndexDirectory(
        projectPath: String,
        configuration: Config
    ) throws -> String {
        let indexPath = (projectPath as NSString).appendingPathComponent(configuration.indexPath)
        try FileManager.default.createDirectory(
            atPath: indexPath,
            withIntermediateDirectories: true
        )
        return indexPath
    }

    private func printStartupInfo(
        resolvedPath: String,
        indexPath: String,
        configuration: Config,
        logger: Logger
    ) {
        print("Indexing: \(resolvedPath)")
        print("Index path: \(indexPath)")
        print("Provider: \(configuration.embeddingProvider)")

        if force {
            logger.info("Force re-indexing enabled, clearing existing index")
            print("Mode: Force re-index")
            print("Force: true")
        } else {
            print("Mode: Incremental")
        }
    }

    private struct IndexingContextParams {
        let indexManager: IndexManager
        let parser: HybridParser
        let embeddingBatcher: EmbeddingBatcher
        let descriptionGenerator: DescriptionGenerator?
        let descriptionState: DescriptionGenerationState
        let progressRenderer: StickyProgressRenderer
        let terminal: Terminaling
        let projectPath: String
        let logger: Logger
    }

    private func createIndexingContext(from params: IndexingContextParams) -> IndexingContext {
        IndexingContext(
            indexManager: params.indexManager,
            parser: params.parser,
            embeddingBatcher: params.embeddingBatcher,
            descriptionGenerator: params.descriptionGenerator,
            descriptionState: params.descriptionState,
            descriptionProgress: { completed, total, file in
                let displayFile = (file as NSString).lastPathComponent
                let message = "  └─ Descriptions: \(completed)/\(total) (\(displayFile))"
                let pipeline: StandardPipelining = params.terminal.isInteractive
                    ? StandardOutputPipeline()
                    : StandardErrorPipeline()
                params.progressRenderer.log(message, standardPipeline: pipeline)
            },
            projectPath: params.projectPath,
            logger: params.logger
        )
    }

    private func ensureEmbeddingProviderAvailable(
        _ embeddingProvider: EmbeddingProviderChain
    ) async throws {
        guard await embeddingProvider.isAvailable() else {
            throw ValidationError("No embedding provider available. Check your configuration.")
        }

        if let activeProvider = await embeddingProvider.activeProvider() {
            print("Embedding provider: \(activeProvider.name) (dimension: \(activeProvider.dimension))")
        } else if let firstAvailable = await embeddingProvider.firstAvailableProvider() {
            print("Embedding provider: \(firstAvailable.name) (dimension: \(firstAvailable.dimension))")
        }
    }

    private func createIndexManager(
        indexPath: String,
        embeddingProvider: EmbeddingProviderChain
    ) async throws -> IndexManager {
        // Check for dimension mismatch on --force to prevent segfault from incompatible USearch index
        if force {
            let vectorPath = (indexPath as NSString).appendingPathComponent("vectors.usearch")
            if let old = USearchVectorStore.existingDimension(at: vectorPath), old != embeddingProvider.dimension {
                print("Dimension changed (\(old) → \(embeddingProvider.dimension)), recreating index...")
                try USearchVectorStore.deleteIndex(at: vectorPath)
            }
        }
        let indexManager = try IndexManager(directory: indexPath, dimension: embeddingProvider.dimension)
        if !force { try await indexManager.load() } else { try await indexManager.clear() }
        return indexManager
    }

    private struct IndexingTaskConfig {
        let context: IndexingContext
        let stats: AtomicIndexingStats
        let maxConcurrentTasks: Int
        let forceReindex: Bool
        let logger: Logger
        let reportProgress: (Int, Int, Int) -> Void
    }

    private static func runIndexingTasks(
        files: [String],
        config: IndexingTaskConfig
    ) async throws -> Error? {
        var fatalError: Error?

        try await withThrowingTaskGroup(of: (Int, FileIndexResult?, Error?).self) { group in
            var currentIndex = 0
            var inFlight = 0

            while currentIndex < files.count, inFlight < config.maxConcurrentTasks {
                enqueueIndexingTask(
                    group: &group,
                    index: currentIndex,
                    filePath: files[currentIndex],
                    context: config.context,
                    forceReindex: config.forceReindex
                )
                currentIndex += 1
                inFlight += 1
            }
            config.reportProgress(config.stats.filesProcessed, inFlight, files.count)

            for try await (_, result, error) in group {
                inFlight -= 1

                // Check for cancellation to stop early
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }

                if let error = error as? VectorStoreError {
                    if case .indexDimensionMismatch = error {
                        fatalError = error
                        group.cancelAll()
                        break
                    }
                    config.stats.incrementErrors()
                    config.logger.warning("Failed to index file", metadata: [
                        "error": "\(error.localizedDescription)",
                    ])
                } else if let error {
                    config.stats.incrementErrors()
                    config.logger.warning("Failed to index file", metadata: [
                        "error": "\(error.localizedDescription)",
                    ])
                } else if let result {
                    config.stats.incrementFilesProcessed()
                    config.stats.addChunksIndexed(result.chunksIndexed)
                    config.stats.addChunksReused(result.chunksReused)
                    config.stats.addSnippetsIndexed(result.snippetsIndexed)
                    config.stats.addDescriptionsGenerated(result.descriptionsGenerated)
                    if result.skipped {
                        config.stats.incrementFilesSkipped()
                    }
                }

                let processed = config.stats.filesProcessed
                config.reportProgress(processed, inFlight, files.count)

                if currentIndex < files.count {
                    enqueueIndexingTask(
                        group: &group,
                        index: currentIndex,
                        filePath: files[currentIndex],
                        context: config.context,
                        forceReindex: config.forceReindex
                    )
                    currentIndex += 1
                    inFlight += 1
                    config.reportProgress(processed, inFlight, files.count)
                }
            }
        }

        return fatalError
    }

    private static func enqueueIndexingTask(
        group: inout ThrowingTaskGroup<(Int, FileIndexResult?, Error?), Error>,
        index: Int,
        filePath: String,
        context: IndexingContext,
        forceReindex: Bool
    ) {
        group.addTask {
            do {
                let result = try await FileIndexer.indexFile(
                    at: filePath,
                    context: context,
                    force: forceReindex
                )
                return (index, result, nil)
            } catch {
                return (index, nil, error)
            }
        }
    }
}
