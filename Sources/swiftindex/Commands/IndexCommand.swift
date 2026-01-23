// MARK: - Index Command

import ArgumentParser
import Foundation
import Logging
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
        let logger = CLIUtils.makeLogger(verbose: verbose)
        logger.info("Starting index operation")

        let startTime = Date()

        let resolvedPath = try resolvePath(logger: logger)
        let configuration = try loadConfiguration(projectDirectory: resolvedPath, logger: logger)
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
        let embeddingProvider = createEmbeddingProvider(config: configuration, logger: logger)

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
        let files = try collectFiles(
            at: resolvedPath,
            config: configuration,
            parser: parser,
            logger: logger
        )

        print("Found \(files.count) files to process")

        // Index files in parallel
        let stats = AtomicIndexingStats()
        let indexingContext = IndexingContext(
            indexManager: indexManager,
            parser: parser,
            embeddingProvider: embeddingProvider,
            logger: logger
        )

        let maxConcurrentTasks = configuration.maxConcurrentTasks
        print("Parallel indexing with \(maxConcurrentTasks) concurrent tasks")

        // Use TaskGroup for parallel processing with bounded concurrency
        // Capture force as local constant to avoid capturing self
        let forceReindex = force
        let fatalError = try await runIndexingTasks(
            files: files,
            config: IndexingTaskConfig(
                context: indexingContext,
                stats: stats,
                maxConcurrentTasks: maxConcurrentTasks,
                forceReindex: forceReindex,
                logger: logger
            )
        )

        // Handle fatal errors after task group completes
        if let fatalError {
            print("\n")
            print("Error: \(fatalError.localizedDescription)")
            throw ExitCode.failure
        }

        // Save index
        try await indexManager.save()

        // Final statistics
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
        print("Total chunks in index: \(statistics.chunkCount)")
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

    private func loadConfiguration(
        projectDirectory: String,
        logger: Logger
    ) throws -> Config {
        let configuration = try CLIUtils.loadConfig(
            from: config,
            projectDirectory: projectDirectory,
            logger: logger
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
        let indexManager = try IndexManager(
            directory: indexPath,
            dimension: embeddingProvider.dimension
        )

        if !force {
            try await indexManager.load()
        } else {
            try await indexManager.clear()
        }

        return indexManager
    }

    private struct IndexingTaskConfig {
        let context: IndexingContext
        let stats: AtomicIndexingStats
        let maxConcurrentTasks: Int
        let forceReindex: Bool
        let logger: Logger
    }

    private func runIndexingTasks(
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

            for try await (_, result, error) in group {
                inFlight -= 1

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
                    if result.skipped {
                        config.stats.incrementFilesSkipped()
                    }
                }

                let processed = config.stats.filesProcessed
                let chunks = config.stats.chunksIndexed
                let progress = processed * 100 / files.count
                let progressMsg = "\r[\(progress)%] Processing: \(processed)/\(files.count)"
                print("\(progressMsg) files, \(chunks) chunks", terminator: "")
                fflush(stdout)

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
                }
            }
        }

        return fatalError
    }

    private func enqueueIndexingTask(
        group: inout ThrowingTaskGroup<(Int, FileIndexResult?, Error?), Error>,
        index: Int,
        filePath: String,
        context: IndexingContext,
        forceReindex: Bool
    ) {
        group.addTask {
            do {
                let result = try await IndexCommand.indexFile(
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

    private func collectFiles(
        at path: String,
        config: Config,
        parser: HybridParser,
        logger: Logger
    ) throws -> [String] {
        var files: [String] = []
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ValidationError("Could not enumerate directory: \(path)")
        }

        for case let fileURL as URL in enumerator {
            let filePath = fileURL.path

            // Check exclusion patterns
            var shouldExclude = false
            for pattern in config.excludePatterns {
                if filePath.contains(pattern) {
                    shouldExclude = true
                    break
                }
            }

            if shouldExclude {
                continue
            }

            // Check if regular file
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  let isRegularFile = resourceValues.isRegularFile,
                  isRegularFile
            else {
                continue
            }

            // Check file size
            if let fileSize = resourceValues.fileSize, fileSize > config.maxFileSize {
                logger.debug("Skipping large file: \(filePath) (\(fileSize) bytes)")
                continue
            }

            // Check extension
            let ext = fileURL.pathExtension.lowercased()

            // If include extensions is specified, check against it
            if !config.includeExtensions.isEmpty {
                guard config.includeExtensions.contains(ext) ||
                    config.includeExtensions.contains(".\(ext)")
                else {
                    continue
                }
            } else {
                // Otherwise, check if parser supports the extension
                guard parser.supportedExtensions.contains(ext) else {
                    continue
                }
            }

            files.append(filePath)
        }

        return files.sorted()
    }

    private static func indexFile(
        at path: String,
        context: IndexingContext,
        force: Bool
    ) async throws -> FileIndexResult {
        // Read file content
        let content = try String(contentsOfFile: path, encoding: .utf8)

        // Compute file hash for incremental indexing
        let fileHash = computeFileHash(content)

        // Check if file needs indexing (unless force is set)
        if !force {
            let needsIndexing = try await context.indexManager.needsIndexing(fileHash: fileHash)
            if !needsIndexing {
                context.logger.debug("Skipping unchanged file: \(path)")
                return FileIndexResult(chunksIndexed: 0, chunksReused: 0, skipped: true)
            }
        }

        // Parse file
        let parseResult = context.parser.parse(content: content, path: path)

        if case let .failure(error) = parseResult {
            context.logger.debug("Parse failed for \(path): \(error)")
            return FileIndexResult(chunksIndexed: 0, chunksReused: 0, skipped: false)
        }

        let chunks = parseResult.chunks
        guard !chunks.isEmpty else {
            // Record file as indexed even if no chunks (to avoid re-processing)
            try await context.indexManager.recordIndexed(fileHash: fileHash, path: path)
            return FileIndexResult(chunksIndexed: 0, chunksReused: 0, skipped: false)
        }

        // Re-index the file with content-hash-based change detection
        // This avoids re-embedding unchanged chunks
        let reindexResult = try await context.indexManager.reindexWithChangeDetection(
            path: path,
            newChunks: chunks
        ) { chunksToEmbed in
            // Embedding closure - only called for chunks that need new embeddings
            let contents = chunksToEmbed.map(\.content)
            return try await context.embeddingProvider.embed(contents)
        }

        context.logger.debug("Indexed file", metadata: [
            "path": "\(path)",
            "total": "\(reindexResult.totalChunks)",
            "embedded": "\(reindexResult.embeddedChunks)",
            "reused": "\(reindexResult.reusedChunks)",
        ])

        return FileIndexResult(
            chunksIndexed: reindexResult.totalChunks,
            chunksReused: reindexResult.reusedChunks,
            skipped: false
        )
    }

    private static func computeFileHash(_ content: String) -> String {
        // Use simple hash for quick comparison
        var hasher = Hasher()
        hasher.combine(content)
        let hash = hasher.finalize()
        return String(format: "%016x", hash)
    }
}

// MARK: - Helper Types

private struct IndexingContext: Sendable {
    let indexManager: IndexManager
    let parser: HybridParser
    let embeddingProvider: EmbeddingProviderChain
    let logger: Logger
}

private struct IndexingStats: Sendable {
    var filesProcessed: Int = 0
    var filesSkipped: Int = 0
    var chunksIndexed: Int = 0
    var chunksReused: Int = 0
    var errors: Int = 0
}

/// Thread-safe wrapper for indexing statistics during parallel processing.
private final class AtomicIndexingStats: @unchecked Sendable {
    private let lock = NSLock()
    private var _filesProcessed: Int = 0
    private var _filesSkipped: Int = 0
    private var _chunksIndexed: Int = 0
    private var _chunksReused: Int = 0
    private var _errors: Int = 0

    var filesProcessed: Int {
        lock.lock()
        defer { lock.unlock() }
        return _filesProcessed
    }

    var filesSkipped: Int {
        lock.lock()
        defer { lock.unlock() }
        return _filesSkipped
    }

    var chunksIndexed: Int {
        lock.lock()
        defer { lock.unlock() }
        return _chunksIndexed
    }

    var chunksReused: Int {
        lock.lock()
        defer { lock.unlock() }
        return _chunksReused
    }

    var errors: Int {
        lock.lock()
        defer { lock.unlock() }
        return _errors
    }

    func incrementFilesProcessed() {
        lock.lock()
        _filesProcessed += 1
        lock.unlock()
    }

    func incrementFilesSkipped() {
        lock.lock()
        _filesSkipped += 1
        lock.unlock()
    }

    func addChunksIndexed(_ count: Int) {
        lock.lock()
        _chunksIndexed += count
        lock.unlock()
    }

    func addChunksReused(_ count: Int) {
        lock.lock()
        _chunksReused += count
        lock.unlock()
    }

    func incrementErrors() {
        lock.lock()
        _errors += 1
        lock.unlock()
    }

    func snapshot() -> IndexingStats {
        lock.lock()
        defer { lock.unlock() }
        return IndexingStats(
            filesProcessed: _filesProcessed,
            filesSkipped: _filesSkipped,
            chunksIndexed: _chunksIndexed,
            chunksReused: _chunksReused,
            errors: _errors
        )
    }
}

private struct FileIndexResult: Sendable {
    let chunksIndexed: Int
    let chunksReused: Int
    let skipped: Bool
}
