// MARK: - IncrementalIndexer

import Foundation
import Logging

/// Handles incremental indexing in response to file system changes.
///
/// The IncrementalIndexer coordinates between the FileWatcher and IndexManager
/// to efficiently update the index when files change.
///
/// ## Usage
///
/// ```swift
/// let indexer = IncrementalIndexer(
///     indexManager: indexManager,
///     parser: hybridParser,
///     config: config
/// )
///
/// try await indexer.watchAndIndex(path: "/path/to/project")
/// ```
public actor IncrementalIndexer {
    // MARK: - Properties

    /// The index manager for storing chunks.
    private let indexManager: IndexManager

    /// The parser for extracting chunks.
    private let parser: HybridParser

    /// The embedding provider chain.
    private let embeddingProvider: EmbeddingProviderChain

    /// Configuration.
    private let config: Config

    /// Logger for debugging.
    private let logger: Logger

    /// Currently active file watcher.
    private var watcher: FileWatcher?

    /// Statistics tracking.
    private var stats: IndexingStats

    // MARK: - Types

    /// Statistics about incremental indexing.
    public struct IndexingStats: Sendable {
        public var filesCreated: Int = 0
        public var filesModified: Int = 0
        public var filesDeleted: Int = 0
        public var chunksAdded: Int = 0
        public var chunksRemoved: Int = 0
        public var errors: Int = 0
        public var lastUpdateTime: Date?

        public var totalChanges: Int {
            filesCreated + filesModified + filesDeleted
        }
    }

    // MARK: - Initialization

    /// Creates an incremental indexer.
    ///
    /// - Parameters:
    ///   - indexManager: The index manager for storage.
    ///   - parser: The parser for extracting chunks.
    ///   - embeddingProvider: The embedding provider.
    ///   - config: Configuration options.
    ///   - logger: Logger for debugging.
    public init(
        indexManager: IndexManager,
        parser: HybridParser = HybridParser(),
        embeddingProvider: EmbeddingProviderChain = .default,
        config: Config = .default,
        logger: Logger = Logger(label: "IncrementalIndexer")
    ) {
        self.indexManager = indexManager
        self.parser = parser
        self.embeddingProvider = embeddingProvider
        self.config = config
        self.logger = logger
        stats = IndexingStats()
    }

    // MARK: - Public Methods

    /// Starts watching a directory and incrementally indexing changes.
    ///
    /// This method runs until cancelled. Use `Task.cancel()` to stop.
    ///
    /// - Parameter path: The directory to watch.
    public func watchAndIndex(path: String) async throws {
        let resolvedPath = (path as NSString).standardizingPath

        logger.info("Starting incremental indexing", metadata: [
            "path": "\(resolvedPath)",
        ])

        // Create file watcher
        let fileWatcher = FileWatcher(
            path: resolvedPath,
            debounceMs: config.watchDebounceMs,
            extensions: Set(config.includeExtensions
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }),
            excludePatterns: config.excludePatterns,
            logger: logger
        )

        watcher = fileWatcher

        // Process events
        for await event in fileWatcher.start() {
            do {
                try await handleEvent(event)
            } catch {
                stats.errors += 1
                logger.error("Error handling event", metadata: [
                    "path": "\(event.path)",
                    "error": "\(error.localizedDescription)",
                ])
            }
        }

        logger.info("Incremental indexing stopped")
    }

    /// Stops the incremental indexer.
    public func stop() async {
        await watcher?.stop()
        watcher = nil
    }

    /// Returns current indexing statistics.
    public func getStats() -> IndexingStats {
        stats
    }

    /// Resets indexing statistics.
    public func resetStats() {
        stats = IndexingStats()
    }

    // MARK: - Private Methods

    private func handleEvent(_ event: FileWatcher.Event) async throws {
        switch event {
        case let .created(path):
            try await handleFileCreated(path)
            stats.filesCreated += 1

        case let .modified(path):
            try await handleFileModified(path)
            stats.filesModified += 1

        case let .deleted(path):
            try await handleFileDeleted(path)
            stats.filesDeleted += 1
        }

        stats.lastUpdateTime = Date()
    }

    private func handleFileCreated(_ path: String) async throws {
        logger.debug("File created", metadata: ["path": "\(path)"])

        // Read file content
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            logger.warning("Could not read file", metadata: ["path": "\(path)"])
            return
        }

        // Parse file
        let parseResult = parser.parse(content: content, path: path)

        if case let .failure(error) = parseResult {
            logger.warning("Parse failed", metadata: [
                "path": "\(path)",
                "error": "\(error)",
            ])
            return
        }

        let chunks = parseResult.chunks
        let snippets = parseResult.snippets

        // Generate embeddings and index chunks
        for chunk in chunks {
            do {
                let embedding = try await embeddingProvider.embed(chunk.content)
                try await indexManager.index(chunk: chunk, vector: embedding)
                stats.chunksAdded += 1
            } catch {
                logger.error("Failed to index chunk", metadata: [
                    "chunkId": "\(chunk.id)",
                    "error": "\(error.localizedDescription)",
                ])
            }
        }

        // Store info snippets
        if !snippets.isEmpty {
            do {
                try await indexManager.chunkStore.insertSnippetBatch(snippets)
                logger.debug("Indexed info snippets", metadata: [
                    "path": "\(path)",
                    "snippets": "\(snippets.count)",
                ])
            } catch {
                logger.error("Failed to index info snippets", metadata: [
                    "path": "\(path)",
                    "error": "\(error.localizedDescription)",
                ])
            }
        }

        logger.info("Indexed new file", metadata: [
            "path": "\(path)",
            "chunks": "\(chunks.count)",
            "snippets": "\(snippets.count)",
        ])
    }

    private func handleFileModified(_ path: String) async throws {
        logger.debug("File modified", metadata: ["path": "\(path)"])

        // Read file content
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            logger.warning("Could not read file", metadata: ["path": "\(path)"])
            return
        }

        // Parse file
        let parseResult = parser.parse(content: content, path: path)

        if case let .failure(error) = parseResult {
            logger.warning("Parse failed", metadata: [
                "path": "\(path)",
                "error": "\(error)",
            ])
            return
        }

        let chunks = parseResult.chunks
        let snippets = parseResult.snippets

        // Re-index file (delete old chunks and snippets, add new)
        try await indexManager.chunkStore.deleteByPath(path)
        try await indexManager.chunkStore.deleteSnippetsByPath(path)

        for chunk in chunks {
            do {
                let embedding = try await embeddingProvider.embed(chunk.content)
                try await indexManager.index(chunk: chunk, vector: embedding)
                stats.chunksAdded += 1
            } catch {
                logger.error("Failed to index chunk", metadata: [
                    "chunkId": "\(chunk.id)",
                    "error": "\(error.localizedDescription)",
                ])
            }
        }

        // Store info snippets
        if !snippets.isEmpty {
            do {
                try await indexManager.chunkStore.insertSnippetBatch(snippets)
                logger.debug("Indexed info snippets", metadata: [
                    "path": "\(path)",
                    "snippets": "\(snippets.count)",
                ])
            } catch {
                logger.error("Failed to index info snippets", metadata: [
                    "path": "\(path)",
                    "error": "\(error.localizedDescription)",
                ])
            }
        }

        logger.info("Re-indexed modified file", metadata: [
            "path": "\(path)",
            "newChunks": "\(chunks.count)",
            "newSnippets": "\(snippets.count)",
        ])
    }

    private func handleFileDeleted(_ path: String) async throws {
        logger.debug("File deleted", metadata: ["path": "\(path)"])

        // Delete all chunks and snippets for this file
        try await indexManager.chunkStore.deleteByPath(path)
        try await indexManager.chunkStore.deleteSnippetsByPath(path)

        // Delete file hash record
        try await indexManager.chunkStore.deleteFileHash(path: path)

        logger.info("Removed deleted file from index", metadata: [
            "path": "\(path)",
        ])
    }
}
