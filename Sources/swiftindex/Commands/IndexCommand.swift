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

        // Resolve path
        let resolvedPath = CLIUtils.resolvePath(path)
        logger.debug("Resolved path: \(resolvedPath)")

        // Validate path exists
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw ValidationError("Path does not exist: \(resolvedPath)")
        }

        // Load configuration
        let configuration = try CLIUtils.loadConfig(from: config, projectDirectory: resolvedPath, logger: logger)
        logger.debug("Configuration loaded", metadata: [
            "provider": "\(configuration.embeddingProvider)",
            "model": "\(configuration.embeddingModel)",
        ])

        // Create index directory
        let indexPath = (resolvedPath as NSString).appendingPathComponent(configuration.indexPath)
        try FileManager.default.createDirectory(
            atPath: indexPath,
            withIntermediateDirectories: true
        )

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

        // Create embedding provider chain
        let embeddingProvider = createEmbeddingProvider(config: configuration, logger: logger)

        // Check provider availability
        guard await embeddingProvider.isAvailable() else {
            throw ValidationError("No embedding provider available. Check your configuration.")
        }

        if let activeProvider = await embeddingProvider.activeProvider() {
            print("Embedding provider: \(activeProvider.name) (dimension: \(activeProvider.dimension))")
        } else if let firstAvailable = await embeddingProvider.firstAvailableProvider() {
            print("Embedding provider: \(firstAvailable.name) (dimension: \(firstAvailable.dimension))")
        }

        // Create index manager
        let indexManager = try IndexManager(
            directory: indexPath,
            dimension: embeddingProvider.dimension
        )

        // Load existing index if not forcing
        if !force {
            try await indexManager.load()
        } else {
            try await indexManager.clear()
        }

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

        // Index files
        var stats = IndexingStats()
        let indexingContext = IndexingContext(
            indexManager: indexManager,
            parser: parser,
            embeddingProvider: embeddingProvider,
            logger: logger
        )

        for (index, filePath) in files.enumerated() {
            do {
                let result = try await indexFile(
                    at: filePath,
                    context: indexingContext,
                    force: force
                )

                stats.filesProcessed += 1
                stats.chunksIndexed += result.chunksIndexed
                stats.filesSkipped += result.skipped ? 1 : 0

                // Progress indicator
                let progress = (index + 1) * 100 / files.count
                let progressMsg = "\r[\(progress)%] Processing: \(stats.filesProcessed)/\(files.count)"
                print("\(progressMsg) files, \(stats.chunksIndexed) chunks", terminator: "")
                fflush(stdout)
            } catch let error as VectorStoreError {
                // Handle dimension mismatch as fatal error with clear instructions
                if case .indexDimensionMismatch = error {
                    print("\n")
                    print("Error: \(error.localizedDescription)")
                    throw ExitCode.failure
                }
                stats.errors += 1
                logger.warning("Failed to index file", metadata: [
                    "path": "\(filePath)",
                    "error": "\(error.localizedDescription)",
                ])
            } catch {
                stats.errors += 1
                logger.warning("Failed to index file", metadata: [
                    "path": "\(filePath)",
                    "error": "\(error.localizedDescription)",
                ])
            }
        }

        // Save index
        try await indexManager.save()

        // Final statistics
        let elapsed = Date().timeIntervalSince(startTime)
        let statistics = try await indexManager.statistics()

        print("\n")
        print("Indexing completed in \(String(format: "%.2f", elapsed)) seconds")
        print("Files processed: \(stats.filesProcessed)")
        print("Files skipped (unchanged): \(stats.filesSkipped)")
        print("Chunks indexed: \(stats.chunksIndexed)")
        print("Total chunks in index: \(statistics.chunkCount)")
        print("Total files in index: \(statistics.fileCount)")

        if stats.errors > 0 {
            print("Errors: \(stats.errors)")
        }

        logger.info("Index operation completed")
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

    private func indexFile(
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
                return FileIndexResult(chunksIndexed: 0, skipped: true)
            }
        }

        // Parse file
        let parseResult = context.parser.parse(content: content, path: path)

        if case let .failure(error) = parseResult {
            context.logger.debug("Parse failed for \(path): \(error)")
            return FileIndexResult(chunksIndexed: 0, skipped: false)
        }

        let chunks = parseResult.chunks
        guard !chunks.isEmpty else {
            // Record file as indexed even if no chunks (to avoid re-processing)
            try await context.indexManager.recordIndexed(fileHash: fileHash, path: path)
            return FileIndexResult(chunksIndexed: 0, skipped: false)
        }

        // Generate embeddings for all chunks
        let contents = chunks.map(\.content)
        let embeddings = try await context.embeddingProvider.embed(contents)

        // Create chunk-vector pairs
        var items: [(chunk: CodeChunk, vector: [Float])] = []
        for (chunk, embedding) in zip(chunks, embeddings) {
            items.append((chunk: chunk, vector: embedding))
        }

        // Re-index the file (removes old chunks, adds new ones)
        try await context.indexManager.reindex(path: path, newChunks: items)

        context.logger.debug("Indexed file", metadata: [
            "path": "\(path)",
            "chunks": "\(chunks.count)",
        ])

        return FileIndexResult(chunksIndexed: chunks.count, skipped: false)
    }

    private func computeFileHash(_ content: String) -> String {
        // Use simple hash for quick comparison
        var hasher = Hasher()
        hasher.combine(content)
        let hash = hasher.finalize()
        return String(format: "%016x", hash)
    }
}

// MARK: - Helper Types

private struct IndexingContext {
    let indexManager: IndexManager
    let parser: HybridParser
    let embeddingProvider: EmbeddingProviderChain
    let logger: Logger
}

private struct IndexingStats {
    var filesProcessed: Int = 0
    var filesSkipped: Int = 0
    var chunksIndexed: Int = 0
    var errors: Int = 0
}

private struct FileIndexResult {
    let chunksIndexed: Int
    let skipped: Bool
}
