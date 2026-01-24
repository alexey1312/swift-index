// MARK: - Semantic Search Engine

import Foundation

/// A vector similarity search engine using embeddings.
///
/// SemanticSearch uses the VectorStore's HNSW index to find code chunks
/// that are semantically similar to the query, even when they don't share
/// exact keywords.
///
/// ## Features
///
/// - Vector similarity search using embeddings
/// - Cosine similarity scoring
/// - Requires an embedding provider to encode queries
/// - Optional path and extension filtering
///
/// ## Usage
///
/// ```swift
/// let search = SemanticSearch(
///     vectorStore: store,
///     chunkStore: chunkStore,
///     embeddingProvider: provider
/// )
/// let results = try await search.search(
///     query: "handle user login",
///     options: .default
/// )
/// ```
public actor SemanticSearch: SearchEngine {
    /// The vector store providing similarity search.
    private let vectorStore: any VectorStore

    /// The chunk store for retrieving chunk metadata.
    private let chunkStore: any ChunkStore

    /// The embedding provider for encoding queries.
    private let embeddingProvider: any EmbeddingProvider

    /// Shared glob pattern matcher with LRU cache.
    private let globMatcher: GlobMatcher

    /// Creates a new semantic search engine.
    ///
    /// - Parameters:
    ///   - vectorStore: The vector store with HNSW index.
    ///   - chunkStore: The chunk store for metadata retrieval.
    ///   - embeddingProvider: The provider for query embedding.
    ///   - globMatcher: Shared glob pattern matcher for path filtering.
    public init(
        vectorStore: any VectorStore,
        chunkStore: any ChunkStore,
        embeddingProvider: any EmbeddingProvider,
        globMatcher: GlobMatcher = GlobMatcher()
    ) {
        self.vectorStore = vectorStore
        self.chunkStore = chunkStore
        self.embeddingProvider = embeddingProvider
        self.globMatcher = globMatcher
    }

    /// Performs a semantic similarity search.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - options: Search configuration options.
    /// - Returns: Array of search results with semantic scores.
    public func search(query: String, options: SearchOptions) async throws -> [SearchResult] {
        // Generate query embedding
        let queryVector = try await embeddingProvider.embed(query)

        // Search vector store
        let vectorResults = try await vectorStore.search(
            vector: queryVector,
            limit: options.limit * 2 // Fetch extra for filtering
        )

        // Fetch chunks and build results
        var results: [SearchResult] = []

        for (rank, (chunkId, similarity)) in vectorResults.enumerated() {
            guard let chunk = try await chunkStore.get(id: chunkId) else {
                continue
            }

            // Apply path filter
            if let pathFilter = options.pathFilter {
                guard await globMatcher.matches(chunk.path, pattern: pathFilter) else {
                    continue
                }
            }

            // Apply extension filter
            if let extensionFilter = options.extensionFilter, !extensionFilter.isEmpty {
                let ext = (chunk.path as NSString).pathExtension.lowercased()
                guard extensionFilter.contains(ext) else {
                    continue
                }
            }

            let result = SearchResult(
                chunk: chunk,
                score: similarity,
                bm25Score: nil,
                semanticScore: similarity,
                bm25Rank: nil,
                semanticRank: rank + 1,
                isMultiHop: false,
                hopDepth: 0
            )
            results.append(result)

            if results.count >= options.limit {
                break
            }
        }

        return results
    }

    /// Performs a raw semantic search returning chunk IDs and scores.
    ///
    /// This method is used internally by HybridSearchEngine for fusion.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - limit: Maximum number of results.
    /// - Returns: Array of (chunk ID, similarity score) pairs.
    public func searchRaw(
        query: String,
        limit: Int
    ) async throws -> [(id: String, score: Float)] {
        let queryVector = try await embeddingProvider.embed(query)
        let vectorResults = try await vectorStore.search(vector: queryVector, limit: limit)

        return vectorResults.map { (id: $0.id, score: $0.similarity) }
    }

    /// Performs a raw semantic search using a pre-computed query vector.
    ///
    /// - Parameters:
    ///   - vector: The pre-computed query embedding vector.
    ///   - limit: Maximum number of results.
    /// - Returns: Array of (chunk ID, similarity score) pairs.
    public func searchRaw(
        vector: [Float],
        limit: Int
    ) async throws -> [(id: String, score: Float)] {
        let vectorResults = try await vectorStore.search(vector: vector, limit: limit)
        return vectorResults.map { (id: $0.id, score: $0.similarity) }
    }
}
