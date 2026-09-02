// MARK: - IncrementalIndexer

import Foundation
import Logging

/// Handles incremental indexing in response to file system changes.
///
/// The IncrementalIndexer coordinates between the FileWatcher and IndexManager
/// to efficiently update the index when files change.
///
/// ## Durability
///
/// Chunks are written to SQLite immediately, but vectors live in the in-memory
/// USearch index until `save()` is called. Because stdio MCP servers are routinely
/// killed without warning, this indexer persists the vector index after each burst
/// of changes rather than only at shutdown. Saves are coalesced so that a burst of
/// edits results in a single write.
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

    /// How long to wait for further changes before persisting the vector index.
    private let saveDebounceMs: Int

    /// Currently active file watcher.
    private var watcher: FileWatcher?

    /// Statistics tracking.
    private var stats: IndexingStats

    /// Set when the in-memory vector index has unsaved changes.
    private var needsSave = false

    /// Pending debounce timer for a scheduled save.
    private var saveTimer: Task<Void, Never>?

    /// Tail of the serial save chain. Each queued save awaits its predecessor, so
    /// writes to the vector index never overlap and awaiting the tail waits for all
    /// queued work.
    private var saveChain: Task<Void, Never>?

    /// Set once `stop()` has been called, so no further timers are armed.
    private var isShuttingDown = false

    /// Consecutive save failures, used to bound automatic retries.
    private var consecutiveSaveFailures = 0

    /// How many times a failing save is retried automatically before it is left
    /// to the next file event or `stop()`. Prevents a hot retry loop on a
    /// persistently unwritable index.
    private static let maxSaveRetries = 3

    // MARK: - Types

    /// Statistics about incremental indexing.
    public struct IndexingStats: Sendable {
        public var filesCreated: Int = 0
        public var filesModified: Int = 0
        public var filesDeleted: Int = 0
        public var chunksAdded: Int = 0
        public var chunksReused: Int = 0
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
    ///   - saveDebounceMs: Delay before persisting the vector index after a change.
    public init(
        indexManager: IndexManager,
        parser: HybridParser = HybridParser(),
        embeddingProvider: EmbeddingProviderChain = .default,
        config: Config,
        logger: Logger = Logger(label: "IncrementalIndexer"),
        saveDebounceMs: Int = 1000
    ) {
        self.indexManager = indexManager
        self.parser = parser
        self.embeddingProvider = embeddingProvider
        self.config = config
        self.logger = logger
        self.saveDebounceMs = saveDebounceMs
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
            extensions: FileCollector.indexableExtensions(config: config, parser: parser),
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

        // Drain any pending save before returning.
        await flushPendingSave()

        logger.info("Incremental indexing stopped")
    }

    /// Stops the incremental indexer.
    ///
    /// Persists any unsaved vector index changes before returning.
    public func stop() async {
        // Set before draining so a failed save cannot re-arm a timer that would
        // outlive the indexer and fire after shutdown.
        isShuttingDown = true
        await watcher?.stop()
        watcher = nil
        await flushPendingSave()
    }

    /// Returns current indexing statistics.
    public func getStats() -> IndexingStats {
        stats
    }

    /// Resets indexing statistics.
    public func resetStats() {
        stats = IndexingStats()
    }

    /// Persists the vector index if there are unsaved changes.
    ///
    /// Cancels any in-flight coalesced save and performs it immediately.
    public func flushPendingSave() async {
        // Cancel wakes a sleeping timer so it queues its save immediately.
        if let timer = saveTimer {
            timer.cancel()
            await timer.value
        }
        // Queue one more save for anything still dirty, then wait for the entire
        // chain — including saves queued by other callers — to finish writing.
        enqueueSave()
        await saveChain?.value
    }

    // MARK: - Private Methods

    private func handleEvent(_ event: FileWatcher.Event) async throws {
        switch event {
        case let .created(path):
            try await indexFile(at: path, isNew: true)
            stats.filesCreated += 1

        case let .modified(path):
            try await indexFile(at: path, isNew: false)
            stats.filesModified += 1

        case let .deleted(path):
            try await removeFile(at: path)
            stats.filesDeleted += 1
        }

        stats.lastUpdateTime = Date()
    }

    /// Indexes (or re-indexes) a single file, independent of the watcher.
    ///
    /// Routes through `IndexManager.indexFile`, which performs per-chunk content-hash
    /// change detection (so an edit to one function does not re-embed the whole file)
    /// and records the file hash (so subsequent reconciliation sees the file as clean).
    ///
    /// This is the primitive used by watch events, by `watch --once`, and by
    /// working-tree reconciliation.
    ///
    /// - Parameters:
    ///   - path: The file to index.
    ///   - isNew: Whether the file is newly created (affects logging only).
    public func indexFile(at path: String, isNew: Bool = false) async throws {
        logger.debug(isNew ? "File created" : "File modified", metadata: ["path": "\(path)"])

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            logger.warning("Could not read file", metadata: ["path": "\(path)"])
            return
        }

        let fileHash = FileHasher.hash(content)
        let parseResult = parser.parse(content: content, path: path, fileHash: fileHash)

        if case let .failure(error) = parseResult {
            guard error == .emptyContent else {
                // A syntax error usually means the file is mid-edit. Keep the previous
                // chunks rather than blanking the file out of search results.
                logger.warning("Parse failed", metadata: [
                    "path": "\(path)",
                    "error": "\(error)",
                ])
                return
            }

            // The file still exists but is now empty: drop what we indexed for it,
            // otherwise deleted code stays searchable until a full rebuild.
            let removed = try await clearChunks(for: path)
            try await indexManager.chunkStore.deleteSnippetsByPath(path)
            try await indexManager.recordIndexed(fileHash: fileHash, path: path)
            stats.chunksRemoved += removed
            scheduleSave()

            logger.info("Cleared emptied file from index", metadata: [
                "path": "\(path)",
                "chunks": "\(removed)",
            ])
            return
        }

        // `IndexManager.indexFile` only reindexes a category when the new set is
        // non-empty — it records the file hash and returns otherwise. So a file that
        // lost all of its chunks (or all of its snippets) would keep serving the stale
        // ones while being marked clean. Clear those categories explicitly.
        if parseResult.chunks.isEmpty {
            stats.chunksRemoved += try await clearChunks(for: path)
        }
        if parseResult.snippets.isEmpty {
            try await indexManager.chunkStore.deleteSnippetsByPath(path)
        }

        let result = try await indexManager.indexFile(
            path: path,
            fileHash: fileHash,
            parseResult: parseResult,
            embedder: { [embeddingProvider] chunks in
                try await embeddingProvider.embed(chunks.map(\.content))
            }
        )

        // Count only chunks that were actually (re-)embedded; `chunksReused` tracks
        // the rest, so the two counters partition `result.chunksIndexed`.
        stats.chunksAdded += result.chunksIndexed - result.chunksReused
        stats.chunksReused += result.chunksReused
        scheduleSave()

        logger.info(isNew ? "Indexed new file" : "Re-indexed modified file", metadata: [
            "path": "\(path)",
            "chunks": "\(result.chunksIndexed)",
            "reused": "\(result.chunksReused)",
            "snippets": "\(result.snippetsIndexed)",
        ])
    }

    /// Removes a single file from the index, independent of the watcher.
    ///
    /// - Parameter path: The file to remove.
    public func removeFile(at path: String) async throws {
        logger.debug("File deleted", metadata: ["path": "\(path)"])

        let removed = try await clearChunks(for: path)
        try await indexManager.chunkStore.deleteSnippetsByPath(path)
        try await indexManager.chunkStore.deleteFileHash(path: path)

        stats.chunksRemoved += removed
        scheduleSave()

        logger.info("Removed deleted file from index", metadata: [
            "path": "\(path)",
            "chunks": "\(removed)",
        ])
    }

    /// Deletes every chunk indexed for `path`, along with its vectors.
    ///
    /// Vectors are dropped first so the vector store never retains orphans pointing
    /// at rows that no longer exist.
    ///
    /// - Returns: The number of chunks removed.
    @discardableResult
    private func clearChunks(for path: String) async throws -> Int {
        let existing = try await indexManager.chunkStore.getByPath(path)
        for chunk in existing {
            try await indexManager.vectorStore.delete(id: chunk.id)
        }
        try await indexManager.chunkStore.deleteByPath(path)
        return existing.count
    }

    // MARK: - Save Coalescing

    /// Marks the vector index dirty and schedules a coalesced save.
    ///
    /// The timer task captures `self` strongly on purpose: a pending save must not be
    /// dropped if the last external reference goes away. The retain is temporary — it
    /// ends when the task completes.
    private func scheduleSave() {
        needsSave = true
        guard !isShuttingDown, saveTimer == nil else { return }

        let delay = UInt64(max(0, saveDebounceMs)) * 1_000_000
        saveTimer = Task {
            // Cancellation means "save now" (see `flushPendingSave`), not "skip the
            // save" — `try?` swallows the sleep's cancellation error and falls through.
            try? await Task.sleep(nanoseconds: delay)
            self.saveTimer = nil
            self.enqueueSave()
        }
    }

    /// Appends a save to the serial chain.
    ///
    /// Chaining rather than guarding on an "in flight" flag is what makes
    /// `flushPendingSave` correct under concurrent callers: `WatchCommand` issues two
    /// overlapping `stop()` calls, and both must return only after every queued write
    /// has completed.
    private func enqueueSave() {
        let previous = saveChain
        saveChain = Task {
            await previous?.value
            await self.writeVectorIndexIfDirty()
        }
    }

    /// Performs the actual write if the index is dirty. Never throws.
    private func writeVectorIndexIfDirty() async {
        guard needsSave else { return }
        needsSave = false

        do {
            try await indexManager.save()
            consecutiveSaveFailures = 0
            logger.debug("Persisted vector index")
        } catch VectorStoreError.noPersistencePath {
            // An in-memory vector store has nothing to persist. This is a valid
            // configuration (tests, ephemeral indexes), not a failure.
            consecutiveSaveFailures = 0
            logger.debug("Vector store has no persistence path; skipping save")
        } catch {
            // Leave the index dirty and retry on a timer, bounded so a persistently
            // unwritable index does not spin.
            needsSave = true
            consecutiveSaveFailures += 1
            stats.errors += 1
            logger.error("Failed to persist vector index", metadata: [
                "error": "\(error.localizedDescription)",
                "attempt": "\(consecutiveSaveFailures)",
            ])

            if consecutiveSaveFailures < Self.maxSaveRetries {
                scheduleSave()
            }
        }
    }
}
