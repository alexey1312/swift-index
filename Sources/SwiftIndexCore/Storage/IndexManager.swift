// MARK: - IndexManager

import Foundation
import Logging

/// Coordinates chunk and vector stores for unified index management.
///
/// IndexManager provides a high-level interface for:
/// - Coordinated chunk and vector storage
/// - Incremental indexing with file hash tracking
/// - Hybrid search combining FTS and semantic similarity
/// - Index persistence and lifecycle management
public actor IndexManager {
    // MARK: - Properties

    /// The chunk store for metadata and FTS.
    public let chunkStore: GRDBChunkStore

    /// The vector store for embeddings.
    public let vectorStore: USearchVectorStore

    /// Logger for diagnostics.
    private let logger: Logger

    /// Configuration for the index.
    private let config: IndexManagerConfig

    // MARK: - Initialization

    /// Create an index manager with the specified storage directory.
    ///
    /// - Parameters:
    ///   - directory: Directory for storing index files.
    ///   - dimension: Vector embedding dimension.
    ///   - config: Optional configuration.
    /// - Throws: If store creation fails.
    public init(
        directory: String,
        dimension: Int,
        config: IndexManagerConfig = .default
    ) throws {
        // Ensure directory exists
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        let dbPath = (directory as NSString).appendingPathComponent("chunks.db")
        let vectorPath = (directory as NSString).appendingPathComponent("vectors.usearch")

        chunkStore = try GRDBChunkStore(path: dbPath)
        vectorStore = try USearchVectorStore(dimension: dimension, path: vectorPath)
        self.config = config
        logger = Logger(label: "IndexManager")
    }

    /// Create an index manager with custom stores (for testing).
    ///
    /// - Parameters:
    ///   - chunkStore: The chunk store to use.
    ///   - vectorStore: The vector store to use.
    ///   - config: Optional configuration.
    public init(
        chunkStore: GRDBChunkStore,
        vectorStore: USearchVectorStore,
        config: IndexManagerConfig = .default
    ) {
        self.chunkStore = chunkStore
        self.vectorStore = vectorStore
        self.config = config
        logger = Logger(label: "IndexManager")
    }

    // MARK: - Indexing

    /// Index a chunk with its embedding vector.
    ///
    /// - Parameters:
    ///   - chunk: The code chunk to index.
    ///   - vector: The embedding vector for the chunk.
    /// - Throws: If indexing fails.
    public func index(chunk: CodeChunk, vector: [Float]) async throws {
        try ensureWritable()
        try await chunkStore.insert(chunk)
        try await vectorStore.add(id: chunk.id, vector: vector)

        logger.debug("Indexed chunk", metadata: [
            "id": "\(chunk.id)",
            "path": "\(chunk.path)",
            "kind": "\(chunk.kind.rawValue)",
        ])
    }

    /// Index multiple chunks with their embedding vectors in batch.
    ///
    /// - Parameter items: Array of (chunk, vector) pairs.
    /// - Throws: If indexing fails.
    public func indexBatch(_ items: [(chunk: CodeChunk, vector: [Float])]) async throws {
        try ensureWritable()
        guard !items.isEmpty else { return }

        let chunks = items.map(\.chunk)
        let vectors = items.map { (id: $0.chunk.id, vector: $0.vector) }

        try await chunkStore.insertBatch(chunks)
        try await vectorStore.addBatch(vectors)

        logger.info("Indexed batch", metadata: [
            "count": "\(items.count)",
        ])
    }

    // MARK: - Snippet Indexing

    /// Reindex info snippets for a file.
    ///
    /// This removes all existing snippets for the path and inserts new ones.
    /// Snippets are BM25-only (no embeddings required).
    ///
    /// - Parameters:
    ///   - path: The file path.
    ///   - snippets: New snippets to index.
    /// - Returns: Number of snippets indexed.
    @discardableResult
    public func reindexSnippets(path: String, snippets: [InfoSnippet]) async throws -> Int {
        try ensureWritable()
        // Delete old snippets for this path
        try await chunkStore.deleteSnippetsByPath(path)

        // Insert new snippets
        guard !snippets.isEmpty else { return 0 }
        try await chunkStore.insertSnippetBatch(snippets)

        logger.debug("Indexed snippets", metadata: [
            "path": "\(path)",
            "count": "\(snippets.count)",
        ])

        return snippets.count
    }

    /// Index a file's chunks and snippets in one unified operation.
    ///
    /// This is the primary entry point for indexing a single file. It handles:
    /// - Chunks with content-based change detection (reuses embeddings for unchanged content)
    /// - Snippets (BM25-only, no embeddings required)
    ///
    /// - Parameters:
    ///   - path: The file path.
    ///   - fileHash: The content hash of the file.
    ///   - parseResult: The parsed result containing chunks and snippets.
    ///   - embedder: Closure to generate embeddings for chunks that need them.
    /// - Returns: Statistics about the indexing operation.
    /// - Throws: If indexing fails.
    public func indexFile(
        path: String,
        fileHash: String,
        parseResult: ParseResult,
        embedder: ([CodeChunk]) async throws -> [[Float]]
    ) async throws -> FileIndexResult {
        try ensureWritable()
        let chunks = parseResult.chunks
        let snippets = parseResult.snippets

        // 1. Index chunks with change detection
        var chunksResult = ReindexResult(totalChunks: 0, reusedChunks: 0, embeddedChunks: 0)
        if !chunks.isEmpty {
            chunksResult = try await reindexWithChangeDetection(
                path: path,
                newChunks: chunks,
                embedder: embedder
            )
        } else {
            // Record file as indexed even if no chunks (to avoid re-processing)
            try await recordIndexed(fileHash: fileHash, path: path)
        }

        // 2. Index snippets (BM25-only)
        var snippetsIndexed = 0
        if !snippets.isEmpty {
            snippetsIndexed = try await reindexSnippets(path: path, snippets: snippets)
        }

        logger.debug("Indexed file", metadata: [
            "path": "\(path)",
            "chunks": "\(chunksResult.totalChunks)",
            "reused": "\(chunksResult.reusedChunks)",
            "snippets": "\(snippetsIndexed)",
        ])

        return FileIndexResult(
            chunksIndexed: chunksResult.totalChunks,
            chunksReused: chunksResult.reusedChunks,
            snippetsIndexed: snippetsIndexed
        )
    }

    /// Check if a file needs reindexing based on its path and content hash.
    ///
    /// - Parameters:
    ///   - path: The file path.
    ///   - hash: The file content hash.
    /// - Returns: True if the file has not been indexed or has changed.
    public func needsIndexing(path: String, fileHash hash: String) async throws -> Bool {
        guard let storedHash = try await chunkStore.getFileHash(forPath: path) else {
            return true // File not previously indexed
        }
        return storedHash != hash // File changed if hash differs
    }

    /// Record that a file has been indexed.
    ///
    /// - Parameters:
    ///   - hash: The file content hash.
    ///   - path: The file path.
    public func recordIndexed(fileHash hash: String, path: String) async throws {
        try ensureWritable()
        try await chunkStore.setFileHash(hash, forPath: path)
    }

    /// Reindex a file with content-based change detection.
    ///
    /// This optimized method compares content hashes of new chunks against existing
    /// chunks to avoid re-embedding unchanged content. Only chunks with new or
    /// modified content will have their embeddings generated.
    ///
    /// - Parameters:
    ///   - path: The file path.
    ///   - newChunks: New chunks parsed from the file.
    ///   - embedder: Closure to generate embeddings for chunks that need them.
    /// - Returns: Statistics about the reindex operation.
    /// - Throws: If reindexing fails.
    @discardableResult
    public func reindexWithChangeDetection(
        path: String,
        newChunks: [CodeChunk],
        embedder: ([CodeChunk]) async throws -> [[Float]]
    ) async throws -> ReindexResult {
        try ensureWritable()
        // Get existing chunks and their vectors for this file
        let oldChunks = try await chunkStore.getByPath(path)

        // Batch fetch all vectors in a single actor hop
        let oldChunkIDs = oldChunks.map(\.id)
        let vectorsById = try await vectorStore.getBatch(ids: oldChunkIDs)

        // Build lookup: contentHash → (chunk, vector)
        var existingByHash: [String: (chunk: CodeChunk, vector: [Float]?)] = [:]
        for chunk in oldChunks {
            let vector = vectorsById[chunk.id]
            existingByHash[chunk.contentHash] = (chunk: chunk, vector: vector)
        }

        // Categorize new chunks
        var chunksToEmbed: [CodeChunk] = []
        var reusableChunks: [(chunk: CodeChunk, vector: [Float])] = []

        for newChunk in newChunks {
            if let existing = existingByHash[newChunk.contentHash],
               let vector = existing.vector
            {
                // Content unchanged - reuse existing vector
                reusableChunks.append((chunk: newChunk, vector: vector))
            } else {
                // New or changed content - needs embedding
                chunksToEmbed.append(newChunk)
            }
        }

        // Generate embeddings only for changed chunks
        var newlyEmbedded: [(chunk: CodeChunk, vector: [Float])] = []
        if !chunksToEmbed.isEmpty {
            let embeddings = try await embedder(chunksToEmbed)
            for (chunk, embedding) in zip(chunksToEmbed, embeddings) {
                newlyEmbedded.append((chunk: chunk, vector: embedding))
            }
        }

        // Combine all chunks
        let allChunks = reusableChunks + newlyEmbedded

        // Delete old chunks from stores
        for chunk in oldChunks {
            try await vectorStore.delete(id: chunk.id)
        }
        try await chunkStore.deleteByPath(path)
        try await chunkStore.deleteFileHash(path: path)

        // Index all chunks (reused + newly embedded)
        try await indexBatch(allChunks)

        // Record file hash
        if let firstChunk = newChunks.first {
            try await recordIndexed(fileHash: firstChunk.fileHash, path: path)
        }

        let result = ReindexResult(
            totalChunks: newChunks.count,
            reusedChunks: reusableChunks.count,
            embeddedChunks: chunksToEmbed.count
        )

        logger.info("Reindexed file with change detection", metadata: [
            "path": "\(path)",
            "total": "\(result.totalChunks)",
            "reused": "\(result.reusedChunks)",
            "embedded": "\(result.embeddedChunks)",
        ])

        return result
    }

    // MARK: - Search

    /// Perform semantic similarity search.
    ///
    /// - Parameters:
    ///   - vector: The query embedding vector.
    ///   - limit: Maximum results to return.
    /// - Returns: Chunks with similarity scores.
    public func searchSemantic(
        vector: [Float],
        limit: Int
    ) async throws -> [(chunk: CodeChunk, score: Float)] {
        let vectorResults = try await vectorStore.search(vector: vector, limit: limit)

        var results: [(chunk: CodeChunk, score: Float)] = []
        for (id, similarity) in vectorResults {
            if let chunk = try await chunkStore.get(id: id) {
                results.append((chunk: chunk, score: similarity))
            }
        }

        return results
    }

    /// Perform BM25 full-text search.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - limit: Maximum results to return.
    /// - Returns: Chunks with BM25 scores.
    public func searchFTS(
        query: String,
        limit: Int
    ) async throws -> [(chunk: CodeChunk, score: Double)] {
        try await chunkStore.searchFTS(query: query, limit: limit)
    }

    /// Perform hybrid search combining semantic and FTS with RRF fusion.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - vector: The query embedding vector.
    ///   - options: Search options.
    /// - Returns: Fused results with combined scores.
    public func searchHybrid(
        query: String,
        vector: [Float],
        options: HybridSearchOptions = .default
    ) async throws -> [(chunk: CodeChunk, score: Double)] {
        // Fetch more results than needed for fusion
        let fetchLimit = options.limit * 3

        // Parallel search
        async let semanticTask = searchSemantic(vector: vector, limit: fetchLimit)
        async let ftsTask = searchFTS(query: query, limit: fetchLimit)

        let (semanticResults, ftsResults) = try await (semanticTask, ftsTask)

        // Build rank maps (1-indexed)
        var semanticRanks: [String: Int] = [:]
        for (index, result) in semanticResults.enumerated() {
            semanticRanks[result.chunk.id] = index + 1
        }

        var ftsRanks: [String: Int] = [:]
        for (index, result) in ftsResults.enumerated() {
            ftsRanks[result.chunk.id] = index + 1
        }

        // Collect all unique chunk IDs
        var allChunkIDs = Set(semanticRanks.keys)
        allChunkIDs.formUnion(ftsRanks.keys)

        // Build chunk lookup
        var chunkLookup: [String: CodeChunk] = [:]
        for result in semanticResults {
            chunkLookup[result.chunk.id] = result.chunk
        }
        for result in ftsResults {
            chunkLookup[result.chunk.id] = result.chunk
        }

        // Calculate RRF scores
        let k = Double(options.rrfK)
        var fusedResults: [(chunk: CodeChunk, score: Double)] = []

        for chunkID in allChunkIDs {
            guard let chunk = chunkLookup[chunkID] else { continue }

            var rrfScore = 0.0

            // Semantic contribution
            if let semanticRank = semanticRanks[chunkID] {
                rrfScore += options.semanticWeight / (k + Double(semanticRank))
            }

            // FTS contribution
            if let ftsRank = ftsRanks[chunkID] {
                rrfScore += (1.0 - options.semanticWeight) / (k + Double(ftsRank))
            }

            fusedResults.append((chunk: chunk, score: rrfScore))
        }

        // Sort by RRF score (descending) and limit
        fusedResults.sort { $0.score > $1.score }
        return Array(fusedResults.prefix(options.limit))
    }

    // MARK: - Retrieval

    /// Get a chunk by ID.
    ///
    /// - Parameter id: The chunk ID.
    /// - Returns: The chunk if found.
    public func getChunk(id: String) async throws -> CodeChunk? {
        try await chunkStore.get(id: id)
    }

    /// Get all chunks for a file.
    ///
    /// - Parameter path: The file path.
    /// - Returns: All chunks from the file.
    public func getChunks(path: String) async throws -> [CodeChunk] {
        try await chunkStore.getByPath(path)
    }

    /// Get chunks by their IDs.
    ///
    /// - Parameter ids: The chunk IDs.
    /// - Returns: Found chunks.
    public func getChunks(ids: [String]) async throws -> [CodeChunk] {
        try await chunkStore.getByIDs(ids)
    }

    // MARK: - Statistics

    /// Get the total number of indexed chunks.
    ///
    /// - Returns: Chunk count.
    public func chunkCount() async throws -> Int {
        try await chunkStore.count()
    }

    /// Get the total number of indexed vectors.
    ///
    /// - Returns: Vector count.
    public func vectorCount() async throws -> Int {
        try await vectorStore.count()
    }

    /// Get all indexed file paths.
    ///
    /// - Returns: Array of file paths.
    public func indexedPaths() async throws -> [String] {
        try await chunkStore.allPaths()
    }

    /// Get the total number of indexed info snippets.
    ///
    /// - Returns: Snippet count.
    public func snippetCount() async throws -> Int {
        try await chunkStore.snippetCount()
    }

    /// Get index statistics.
    ///
    /// - Returns: Statistics about the index.
    public func statistics() async throws -> IndexStatistics {
        async let chunks = chunkCount()
        async let vectors = vectorCount()
        async let paths = indexedPaths()
        async let snippets = snippetCount()

        return try await IndexStatistics(
            chunkCount: chunks,
            vectorCount: vectors,
            fileCount: paths.count,
            dimension: vectorStore.dimension,
            snippetCount: snippets
        )
    }

    // MARK: - Persistence

    /// Save both stores to disk.
    ///
    /// - Throws: If saving fails.
    public func save() async throws {
        try ensureWritable()
        try await vectorStore.save()
        // Chunk store auto-persists via SQLite
        logger.info("Index saved")
    }

    /// Load the vector store from disk.
    ///
    /// - Throws: If loading fails.
    public func load() async throws {
        if vectorStore.indexFileExists() {
            try await vectorStore.load()
            logger.info("Vector index loaded")
        }
        // Chunk store auto-loads via SQLite
    }

    /// Clear all indexed data.
    ///
    /// - Throws: If clearing fails.
    public func clear() async throws {
        try ensureWritable()
        try await chunkStore.clear()
        try await chunkStore.clearSnippets()
        try await vectorStore.clear()
        logger.info("Index cleared")
    }

    // MARK: - Maintenance

    /// Remove chunks for files that no longer exist.
    ///
    /// - Returns: Number of chunks removed.
    @discardableResult
    public func pruneDeletedFiles() async throws -> Int {
        try ensureWritable()
        let paths = try await indexedPaths()
        var removedCount = 0

        for path in paths {
            if !FileManager.default.fileExists(atPath: path) {
                let chunks = try await chunkStore.getByPath(path)
                for chunk in chunks {
                    try await vectorStore.delete(id: chunk.id)
                }
                try await chunkStore.deleteByPath(path)
                try await chunkStore.deleteFileHash(path: path)
                removedCount += chunks.count

                logger.debug("Pruned deleted file", metadata: [
                    "path": "\(path)",
                    "chunks": "\(chunks.count)",
                ])
            }
        }

        if removedCount > 0 {
            logger.info("Pruned deleted files", metadata: [
                "removedChunks": "\(removedCount)",
            ])
        }

        return removedCount
    }

    /// Verify index consistency between chunk and vector stores.
    ///
    /// - Returns: Consistency report.
    public func verifyConsistency() async throws -> ConsistencyReport {
        let chunkIDs = try await Set(chunkStore.allIDs())
        let vectorIDs = try await Set(vectorStore.allIDs())

        let missingVectors = chunkIDs.subtracting(vectorIDs)
        let orphanedVectors = vectorIDs.subtracting(chunkIDs)

        return ConsistencyReport(
            chunkCount: chunkIDs.count,
            vectorCount: vectorIDs.count,
            missingVectors: Array(missingVectors),
            orphanedVectors: Array(orphanedVectors),
            isConsistent: missingVectors.isEmpty && orphanedVectors.isEmpty
        )
    }

    /// Repair index by removing orphaned entries.
    ///
    /// - Returns: Number of entries repaired.
    @discardableResult
    public func repair() async throws -> Int {
        try ensureWritable()
        let report = try await verifyConsistency()
        var repairedCount = 0

        // Remove orphaned vectors
        for vectorID in report.orphanedVectors {
            try await vectorStore.delete(id: vectorID)
            repairedCount += 1
        }

        // Note: Missing vectors require re-embedding, not handled here

        if repairedCount > 0 {
            logger.info("Repaired index", metadata: [
                "orphanedVectorsRemoved": "\(report.orphanedVectors.count)",
            ])
        }

        return repairedCount
    }
}

// MARK: - IndexManagerConfig

/// Configuration for IndexManager.
public struct IndexManagerConfig: Sendable {
    /// Default configuration.
    public static let `default` = IndexManagerConfig()

    /// Whether the index is read-only.
    public let readOnly: Bool

    /// Whether to auto-save after batch operations.
    public let autoSave: Bool

    /// Batch size for chunked operations.
    public let batchSize: Int

    public init(
        readOnly: Bool = false,
        autoSave: Bool = true,
        batchSize: Int = 100
    ) {
        self.readOnly = readOnly
        self.autoSave = autoSave
        self.batchSize = batchSize
    }
}

// MARK: - IndexManagerError

public enum IndexManagerError: Error, Sendable {
    case readOnly
}

extension IndexManager {
    private func ensureWritable() throws {
        if config.readOnly {
            throw IndexManagerError.readOnly
        }
    }
}

// MARK: - HybridSearchOptions

/// Options for hybrid search.
public struct HybridSearchOptions: Sendable {
    /// Default search options.
    public static let `default` = HybridSearchOptions()

    /// Maximum results to return.
    public let limit: Int

    /// Weight for semantic search (0-1). FTS weight = 1 - semanticWeight.
    public let semanticWeight: Double

    /// RRF constant K (typically 60).
    public let rrfK: Int

    public init(
        limit: Int = 20,
        semanticWeight: Double = 0.7,
        rrfK: Int = 60
    ) {
        self.limit = limit
        self.semanticWeight = semanticWeight
        self.rrfK = rrfK
    }
}

// MARK: - IndexStatistics

/// Statistics about the index.
public struct IndexStatistics: Sendable {
    /// Number of indexed chunks.
    public let chunkCount: Int

    /// Number of indexed vectors.
    public let vectorCount: Int

    /// Number of indexed files.
    public let fileCount: Int

    /// Vector embedding dimension.
    public let dimension: Int

    /// Number of indexed info snippets (documentation).
    public let snippetCount: Int

    /// Whether chunk and vector counts match.
    public var isConsistent: Bool {
        chunkCount == vectorCount
    }

    public init(
        chunkCount: Int,
        vectorCount: Int,
        fileCount: Int,
        dimension: Int,
        snippetCount: Int = 0
    ) {
        self.chunkCount = chunkCount
        self.vectorCount = vectorCount
        self.fileCount = fileCount
        self.dimension = dimension
        self.snippetCount = snippetCount
    }
}

// MARK: - ConsistencyReport

/// Report from index consistency verification.
public struct ConsistencyReport: Sendable {
    /// Number of chunks in chunk store.
    public let chunkCount: Int

    /// Number of vectors in vector store.
    public let vectorCount: Int

    /// Chunk IDs without corresponding vectors.
    public let missingVectors: [String]

    /// Vector IDs without corresponding chunks.
    public let orphanedVectors: [String]

    /// Whether the index is fully consistent.
    public let isConsistent: Bool
}

// MARK: - ReindexResult

/// Result of a reindex operation with change detection.
public struct ReindexResult: Sendable {
    /// Total number of chunks processed.
    public let totalChunks: Int

    /// Number of chunks that reused existing embeddings.
    public let reusedChunks: Int

    /// Number of chunks that required new embeddings.
    public let embeddedChunks: Int

    /// Percentage of embeddings saved through reuse.
    public var reusePercentage: Double {
        guard totalChunks > 0 else { return 0 }
        return Double(reusedChunks) / Double(totalChunks) * 100
    }
}

// MARK: - FileIndexResult

/// Result of indexing a single file (chunks + snippets).
public struct FileIndexResult: Sendable {
    /// Number of chunks indexed.
    public let chunksIndexed: Int

    /// Number of chunks that reused existing embeddings.
    public let chunksReused: Int

    /// Number of documentation snippets indexed (BM25-only).
    public let snippetsIndexed: Int

    public init(chunksIndexed: Int, chunksReused: Int, snippetsIndexed: Int) {
        self.chunksIndexed = chunksIndexed
        self.chunksReused = chunksReused
        self.snippetsIndexed = snippetsIndexed
    }
}
