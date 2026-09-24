// MARK: - MCP Context

import Foundation
import Logging
import SwiftIndexCore

/// Shared context for MCP tools.
///
/// Manages lazy initialization and caching of shared resources like
/// IndexManager, EmbeddingProvider, and configuration.
public actor MCPContext {
    // MARK: - Singleton

    /// Shared instance for MCP tools.
    public static let shared = MCPContext()

    // MARK: - Properties

    private var indexManagers: [String: IndexManager] = [:]

    /// Cached resolution of the embedding provider, including its dimension.
    private var resolvedEmbedding: ResolvedEmbedding?

    /// Freshness already established for a path this session, so the scan runs once
    /// per path but its verdict keeps being reported.
    private var freshnessByPath: [String: StalenessInfo] = [:]
    /// Background embedding passes, keyed by resolved project path.
    private var backfillTasks: [String: Task<Void, Never>] = [:]
    /// Writer locks this process holds, keyed by index directory.
    private var writerLocks: [String: IndexWriterLock] = [:]
    /// Modification date of the vector file when this process last loaded it.
    private var vectorLoadDates: [String: Date] = [:]
    /// Live file watchers, keyed by resolved project path.
    private var watchers: [String: (indexer: IncrementalIndexer, task: Task<Void, Never>)] = [:]
    private var embeddingProvider: EmbeddingProviderChain?
    private var loadedConfigs: [String: Config] = [:]
    private var llmProviders: (utility: LLMProviderChain?, synthesis: LLMProviderChain?)?
    private var queryExpander: QueryExpander?
    private var resultSynthesizer: ResultSynthesizer?
    private var followUpGenerator: FollowUpGenerator?
    private let logger = Logger(label: "MCPContext")

    /// Shared task manager for async operations.
    public nonisolated let taskManager = TaskManager()

    // MARK: - Initialization

    private init() {}

    // MARK: - Testing Support

    /// Resets all cached state. For testing only.
    @_spi(Testing)
    public func resetForTesting() async {
        indexManagers.removeAll()
        embeddingProvider = nil
        loadedConfigs.removeAll()
        llmProviders = nil
        queryExpander = nil
        resultSynthesizer = nil
        followUpGenerator = nil
        await taskManager.resetForTesting()
    }

    // MARK: - Configuration

    /// Load or get cached configuration for a path.
    public func getConfig(for basePath: String) async throws -> Config {
        let resolvedPath = resolvePath(basePath)

        if let cached = loadedConfigs[resolvedPath] {
            return cached
        }

        // Load config using TOMLConfigLoader (handles layered config)
        let envConfig = (try? EnvironmentConfigLoader().load()) ?? .empty
        let config = try TOMLConfigLoader.loadLayered(
            env: envConfig,
            projectDirectory: resolvedPath,
            requireInitialization: false
        )
        logger.debug("Loaded config for: \(resolvedPath)")

        loadedConfigs[resolvedPath] = config
        return config
    }

    // MARK: - Embedding Provider

    /// Get or create the embedding provider chain.
    ///
    /// - Parameter indexDirectory: Index whose metadata pins an `auto` provider.
    public func getEmbeddingProvider(
        config: Config,
        indexDirectory: String? = nil
    ) async throws -> EmbeddingProviderChain {
        if let existing = embeddingProvider {
            return existing
        }

        let resolved = try await EmbeddingProviderFactory.resolve(
            config: config,
            indexDirectory: indexDirectory,
            logger: logger
        )
        resolvedEmbedding = resolved
        embeddingProvider = resolved.chain
        return resolved.chain
    }

    /// Get the fully resolved embedding selection (provider id, model, dimension).
    public func getResolvedEmbedding(config: Config) async throws -> ResolvedEmbedding {
        if let resolvedEmbedding {
            return resolvedEmbedding
        }
        _ = try await getEmbeddingProvider(config: config)
        // `getEmbeddingProvider` populates the cache.
        guard let resolvedEmbedding else {
            throw ProviderError.notAvailable(reason: "Embedding provider could not be resolved")
        }
        return resolvedEmbedding
    }

    // MARK: - Index Manager

    /// Get or create an IndexManager for a given path.
    public func getIndexManager(for basePath: String, config: Config) async throws -> IndexManager {
        let resolvedPath = resolvePath(basePath)
        let indexPath = (resolvedPath as NSString).appendingPathComponent(config.indexPath)

        if let cached = indexManagers[indexPath] {
            return cached
        }

        // Get embedding provider for dimension
        let provider = try await getEmbeddingProvider(config: config, indexDirectory: indexPath)

        // Create index manager
        let manager = try IndexManager(
            directory: indexPath,
            dimension: provider.dimension
        )

        // Try to load existing index
        if FileManager.default.fileExists(atPath: indexPath) {
            try await manager.load()
            vectorLoadDates[indexPath] = Self.vectorFileDate(indexPath: indexPath)
            logger.info("Loaded existing index from: \(indexPath)")
        }

        indexManagers[indexPath] = manager
        return manager
    }

    /// Check if an index exists for a path.
    public func indexExists(for basePath: String, config: Config) -> Bool {
        let resolvedPath = resolvePath(basePath)
        let indexPath = (resolvedPath as NSString).appendingPathComponent(config.indexPath)
        return FileManager.default.fileExists(atPath: indexPath)
    }

    /// Clear cached index manager for a path.
    public func clearIndexManager(for basePath: String, config: Config) {
        let resolvedPath = resolvePath(basePath)
        let indexPath = (resolvedPath as NSString).appendingPathComponent(config.indexPath)
        indexManagers.removeValue(forKey: indexPath)
    }

    /// Save all loaded indexes.
    public func saveAllIndexes() async throws {
        for (path, manager) in indexManagers {
            try await manager.save()
            logger.info("Saved index: \(path)")
        }
    }

    // MARK: - Search

    /// Create a search engine for a path.
    public func createSearchEngine(
        for basePath: String,
        config: Config
    ) async throws -> HybridSearchEngine {
        let manager = try await getIndexManager(for: basePath, config: config)
        let provider = try await getEmbeddingProvider(config: config)

        let chunkStore = await manager.chunkStore
        let vectorStore = await manager.vectorStore

        return HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: provider,
            rrfK: config.rrfK
        )
    }

    // MARK: - LLM Providers

    /// Get or create LLM provider chains for search enhancement.
    public func getLLMProviders(
        config: Config
    ) async throws -> (utility: LLMProviderChain?, synthesis: LLMProviderChain?) {
        // Check if LLM enhancement is enabled
        guard config.searchEnhancement.enabled else {
            return (nil, nil)
        }

        // Return cached providers if available
        if let existing = llmProviders {
            return existing
        }

        // Create utility tier provider
        let utilityProvider: LLMProviderChain?
        do {
            let provider = try LLMProviderFactory.createProvider(
                from: config.searchEnhancement.utility,
                openAIKey: config.openAIAPIKey,
                anthropicKey: config.anthropicAPIKey
            )
            utilityProvider = LLMProviderChain.single(provider)
            logger.debug("Created utility LLM provider: \(config.searchEnhancement.utility.provider)")
        } catch {
            logger.warning("Failed to create utility LLM provider: \(error)")
            utilityProvider = nil
        }

        // Create synthesis tier provider
        let synthesisProvider: LLMProviderChain?
        do {
            let provider = try LLMProviderFactory.createProvider(
                from: config.searchEnhancement.synthesis,
                openAIKey: config.openAIAPIKey,
                anthropicKey: config.anthropicAPIKey
            )
            synthesisProvider = LLMProviderChain.single(provider)
            logger.debug("Created synthesis LLM provider: \(config.searchEnhancement.synthesis.provider)")
        } catch {
            logger.warning("Failed to create synthesis LLM provider: \(error)")
            synthesisProvider = nil
        }

        let providers = (utilityProvider, synthesisProvider)
        llmProviders = providers
        return providers
    }

    /// Get or create query expander for search enhancement.
    public func getQueryExpander(config: Config) async throws -> QueryExpander? {
        guard config.searchEnhancement.enabled else {
            return nil
        }

        if let existing = queryExpander {
            return existing
        }

        let providers = try await getLLMProviders(config: config)
        guard let utility = providers.utility else {
            return nil
        }

        let expander = QueryExpander(provider: utility)
        queryExpander = expander
        return expander
    }

    /// Get or create result synthesizer for search enhancement.
    public func getResultSynthesizer(config: Config) async throws -> ResultSynthesizer? {
        guard config.searchEnhancement.enabled else {
            return nil
        }

        if let existing = resultSynthesizer {
            return existing
        }

        let providers = try await getLLMProviders(config: config)
        guard let synthesis = providers.synthesis else {
            return nil
        }

        let synthesizer = ResultSynthesizer(provider: synthesis)
        resultSynthesizer = synthesizer
        return synthesizer
    }

    /// Get or create follow-up generator for search enhancement.
    public func getFollowUpGenerator(config: Config) async throws -> FollowUpGenerator? {
        guard config.searchEnhancement.enabled else {
            return nil
        }

        if let existing = followUpGenerator {
            return existing
        }

        let providers = try await getLLMProviders(config: config)
        guard let utility = providers.utility else {
            return nil
        }

        let generator = FollowUpGenerator(provider: utility)
        followUpGenerator = generator
        return generator
    }

    // MARK: - Utilities

    public func resolvePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }

        if path == "." || path.isEmpty {
            return FileManager.default.currentDirectoryPath
        }

        return (FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent(path)
    }

    // MARK: - Freshness

    /// Brings the index for `basePath` in line with the working tree, once per session.
    ///
    /// stdio MCP servers are started and killed constantly, and nothing watches the
    /// tree in between. Without this, edits made while no server was running stay
    /// invisible until someone reindexes by hand. Running it lazily on the first tool
    /// call that touches a path keeps the cost off startup.
    ///
    /// - Returns: What remains stale after the cheap work has been applied.
    public func ensureFreshness(for basePath: String, config: Config) async -> StalenessInfo {
        guard indexExists(for: basePath, config: config) else { return .clean }
        guard acquireWriterRole(for: basePath, config: config) else {
            await reloadVectorsIfChanged(for: basePath, config: config)
            return await reconcileOnce(for: basePath, config: config, applying: false)
        }
        let info = await reconcileOnce(for: basePath, config: config, applying: true)
        await startWatcherIfNeeded(for: basePath, config: config)
        await startEmbeddingBackfillIfNeeded(for: basePath, config: config)
        return info
    }

    // MARK: - Writer Role

    /// Makes this process the writer of the index at `basePath`, if no other holds it.
    ///
    /// Several agents each start a server. Only the writer reconciles, watches and
    /// embeds; the others read and reload vectors when the writer saves them.
    /// A reader tries again on each call, so it takes over when the writer exits.
    ///
    /// - Returns: Whether this process is the writer.
    public func acquireWriterRole(for basePath: String, config: Config) -> Bool {
        let resolvedPath = resolvePath(basePath)
        let indexPath = (resolvedPath as NSString).appendingPathComponent(config.indexPath)
        if writerLocks[indexPath] != nil {
            return true
        }
        guard let lock = IndexWriterLock.acquire(indexDirectory: indexPath) else {
            return false
        }
        writerLocks[indexPath] = lock
        // A verdict recorded as a reader did not apply changes; reconcile again.
        freshnessByPath[resolvedPath] = nil
        logger.info("This server writes the index", metadata: ["path": "\(indexPath)"])
        return true
    }

    /// Message for a write attempt while another process holds the writer role.
    public func writerConflictMessage(for basePath: String, config: Config) -> String {
        let indexPath = (resolvePath(basePath) as NSString).appendingPathComponent(config.indexPath)
        let holder = IndexWriterLock.recordedHolder(indexDirectory: indexPath).map { " (pid \($0))" } ?? ""
        return """
        Another SwiftIndex process\(holder) writes this index and keeps it current. \
        Usually it is the MCP server of another agent session.
        """
    }

    /// Reloads vectors that the writer process saved after this process loaded them.
    private func reloadVectorsIfChanged(for basePath: String, config: Config) async {
        let indexPath = (resolvePath(basePath) as NSString).appendingPathComponent(config.indexPath)
        guard let manager = indexManagers[indexPath],
              let current = Self.vectorFileDate(indexPath: indexPath),
              current != vectorLoadDates[indexPath]
        else {
            return
        }
        do {
            try await manager.load()
            vectorLoadDates[indexPath] = current
            logger.debug("Reloaded vectors saved by the writer process")
        } catch {
            logger.debug("Vector reload failed", metadata: ["error": "\(error.localizedDescription)"])
        }
    }

    private static func vectorFileDate(indexPath: String) -> Date? {
        let path = (indexPath as NSString).appendingPathComponent("vectors.usearch")
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    // MARK: - Background Embedding

    /// Embeds chunks that have no vector yet, without blocking any tool call.
    ///
    /// Indexing stores chunks for text search first, so search and the graph work
    /// at once and semantic ranking improves as vectors arrive.
    public func startEmbeddingBackfillIfNeeded(for basePath: String, config: Config) async {
        let resolvedPath = resolvePath(basePath)
        guard config.embeddingEnabled, backfillTasks[resolvedPath] == nil,
              indexExists(for: basePath, config: config),
              acquireWriterRole(for: basePath, config: config),
              let indexManager = try? await getIndexManager(for: basePath, config: config),
              let resolved = try? await getResolvedEmbedding(config: config),
              let missing = try? await indexManager.missingVectorCount(), missing > 0
        else {
            return
        }

        let logger = logger
        let batchSize = max(config.embeddingBatchSize, 64)
        backfillTasks[resolvedPath] = Task(priority: .utility) {
            guard await resolved.chain.isAvailable() else {
                logger.warning("Embedding provider unavailable; semantic search stays off")
                return
            }
            do {
                // Repeat until nothing is missing: the watcher adds chunks while a pass runs.
                var total = 0
                while true {
                    let embedded = try await indexManager.embedMissingVectors(batchSize: batchSize) { chunks in
                        try await resolved.chain.embed(chunks.map(\.content))
                    }
                    guard embedded > 0 else { break }
                    total += embedded
                }
                logger.info("Background embedding finished", metadata: ["chunks": "\(total)"])
            } catch {
                logger.warning("Background embedding stopped", metadata: ["error": "\(error.localizedDescription)"])
            }
            self.finishBackfill(for: resolvedPath)
        }
        logger.info("Embedding in background", metadata: ["chunks": "\(missing)"])
    }

    private func finishBackfill(for resolvedPath: String) {
        backfillTasks[resolvedPath] = nil
    }

    // MARK: - Watching

    /// Starts watching `basePath` when `auto_index.watch` is on and an index exists.
    ///
    /// Started after the first reconcile, so the watcher only sees edits made later.
    public func startWatcherIfNeeded(for basePath: String, config: Config) async {
        let resolvedPath = resolvePath(basePath)
        guard config.autoIndex.enabled, config.autoIndex.watch, watchers[resolvedPath] == nil,
              indexExists(for: basePath, config: config),
              acquireWriterRole(for: basePath, config: config),
              let indexManager = try? await getIndexManager(for: basePath, config: config),
              let resolved = try? await getResolvedEmbedding(config: config)
        else {
            return
        }

        let indexer = IncrementalIndexer(
            indexManager: indexManager,
            embeddingProvider: resolved.chain,
            config: config,
            logger: logger
        )
        await indexer.deferEmbedding()
        await indexer.onChange { [self] in
            await startEmbeddingBackfillIfNeeded(for: resolvedPath, config: config)
        }
        let logger = logger
        let task = Task {
            do {
                try await indexer.watchAndIndex(path: resolvedPath)
            } catch {
                logger.warning("Watcher stopped", metadata: ["error": "\(error.localizedDescription)"])
            }
        }
        watchers[resolvedPath] = (indexer, task)
        logger.info("Watching for changes", metadata: ["path": "\(resolvedPath)"])
    }

    /// Stops the watcher for `basePath`, e.g. before a full reindex.
    public func stopWatcher(for basePath: String) async {
        let resolvedPath = resolvePath(basePath)
        guard let watcher = watchers.removeValue(forKey: resolvedPath) else { return }
        await watcher.indexer.stop()
        await watcher.task.value
    }

    /// Stops the watcher and the embedding pass for `basePath`, e.g. before a full reindex.
    public func stopBackgroundWork(for basePath: String) async {
        await stopWatcher(for: basePath)
        if let task = backfillTasks.removeValue(forKey: resolvePath(basePath)) {
            task.cancel()
            await task.value
        }
    }

    /// Stops every watcher and background embedding pass, and flushes pending saves.
    public func stopAllWatchers() async {
        for path in Array(watchers.keys) {
            await stopWatcher(for: path)
        }
        for task in backfillTasks.values {
            task.cancel()
            await task.value
        }
        backfillTasks = [:]
        for lock in writerLocks.values {
            lock.release()
        }
        writerLocks = [:]
    }

    // MARK: - Reconcile

    /// - Parameter applying: False for a reader, which only reports what is stale.
    private func reconcileOnce(for basePath: String, config: Config, applying: Bool) async -> StalenessInfo {
        guard config.autoIndex.enabled, config.autoIndex.reconcileOnConnect else {
            return .clean
        }

        let resolvedPath = resolvePath(basePath)
        // Return the cached verdict rather than `.clean`: a deferred branch-switch
        // catch-up must keep being reported for the rest of the session, not warned
        // about exactly once and then silently forgotten.
        if let cached = freshnessByPath[resolvedPath] {
            return cached
        }
        // Record before the work so a throw cannot cause an unbounded rescan loop.
        freshnessByPath[resolvedPath] = .clean

        do {
            let indexManager = try await getIndexManager(for: resolvedPath, config: config)
            let reconciler = IndexReconciler(logger: logger)
            let report = try await reconciler.reconcile(
                path: resolvedPath,
                config: config,
                chunkStore: indexManager.chunkStore
            )

            var info = StalenessInfo()
            guard applying else {
                info.dirtyPaths = Set(report.changed.map(\.path))
                freshnessByPath[resolvedPath] = info
                return info
            }

            // Deletions and stat refreshes are pure database work with no embedding
            // cost, so they are always applied in full. Stale results pointing at
            // files that no longer exist are the most misleading failure mode.
            var graphBuilder: GraphBuilder?
            if config.graph.enabled {
                graphBuilder = await GraphBuilder(
                    chunkStore: indexManager.chunkStore,
                    config: config.graph,
                    logger: logger
                )
            }
            let removedChunks = try await reconciler.applyDeletionsAndTouches(
                report,
                indexManager: indexManager,
                graphBuilder: graphBuilder
            )
            info.removedFiles = report.deleted.count
            if !report.deleted.isEmpty {
                try await graphBuilder?.resolve()
            }

            if report.changed.isEmpty {
                logger.debug("Index is up to date", metadata: [
                    "path": "\(resolvedPath)",
                    "scanned": "\(report.scanned)",
                    "removedChunks": "\(removedChunks)",
                ])
                freshnessByPath[resolvedPath] = info
                return info
            }

            // A large delta almost always means a branch switch. Re-embedding
            // hundreds of files inside the first tool call would blow the client's
            // timeout, so report staleness instead and let an explicit reindex catch
            // up.
            guard report.changed.count <= config.autoIndex.syncThreshold else {
                info.dirtyPaths = Set(report.changed.map(\.path))
                info.deferredCatchUp = true
                logger.info("Deferring catch-up for large change set", metadata: [
                    "path": "\(resolvedPath)",
                    "changed": "\(report.changed.count)",
                ])
                freshnessByPath[resolvedPath] = info
                return info
            }

            let resolved = try await getResolvedEmbedding(config: config)
            let indexer = IncrementalIndexer(
                indexManager: indexManager,
                embeddingProvider: resolved.chain,
                config: config,
                logger: logger
            )
            await indexer.enableGraph(projectRoot: resolvedPath)
            await indexer.deferEmbedding()

            for entry in report.changed {
                do {
                    try await indexer.indexFile(at: entry.path)

                    // indexFile returns without error when a file merely fails to
                    // parse (a mid-edit syntax error), leaving the old chunks in
                    // place. Confirm the file is genuinely current rather than
                    // reporting a clean session while serving stale content.
                    var stillStale = false
                    if let contents = try? String(contentsOfFile: entry.path, encoding: .utf8) {
                        stillStale = try await indexManager.needsIndexing(
                            path: entry.path,
                            fileHash: FileHasher.hash(contents)
                        )
                    }

                    if stillStale {
                        info.dirtyPaths.insert(entry.path)
                    } else {
                        info.refreshedFiles += 1
                    }
                } catch {
                    // Keep going: one unreadable file must not block the session.
                    info.dirtyPaths.insert(entry.path)
                    logger.warning("Catch-up failed for file", metadata: [
                        "path": "\(entry.path)",
                        "error": "\(error.localizedDescription)",
                    ])
                }
            }
            await indexer.resolveGraphIfNeeded()
            await indexer.flushPendingSave()

            freshnessByPath[resolvedPath] = info
            return info
        } catch {
            logger.debug("Freshness check skipped", metadata: [
                "path": "\(resolvedPath)",
                "error": "\(error.localizedDescription)",
            ])
            return .clean
        }
    }

    /// Forgets reconciliation state, so the next tool call rescans.
    public func resetFreshness() {
        freshnessByPath.removeAll()
    }
}
