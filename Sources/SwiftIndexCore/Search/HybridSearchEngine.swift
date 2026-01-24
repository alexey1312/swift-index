// MARK: - Hybrid Search Engine

import Foundation

/// A hybrid search engine combining BM25 keyword search with semantic similarity.
///
/// HybridSearchEngine runs both BM25 and semantic searches in parallel, then
/// combines the results using Reciprocal Rank Fusion (RRF). This approach
/// leverages the strengths of both methods:
/// - BM25 excels at exact keyword matching
/// - Semantic search finds conceptually similar code
///
/// ## Features
///
/// - Parallel execution of BM25 and semantic search
/// - Configurable semantic weight for RRF fusion
/// - Optional multi-hop reference following
/// - Path and extension filtering
///
/// ## Usage
///
/// ```swift
/// let engine = HybridSearchEngine(
///     chunkStore: store,
///     vectorStore: vectorStore,
///     embeddingProvider: provider
/// )
///
/// let results = try await engine.search(
///     query: "user authentication",
///     options: SearchOptions(semanticWeight: 0.7)
/// )
/// ```
///
/// ## Scoring
///
/// The final score is computed using weighted RRF:
/// ```
/// score = (1 - semanticWeight) * RRF(bm25_rank) + semanticWeight * RRF(semantic_rank)
/// ```
public actor HybridSearchEngine: SearchEngine {
    /// The BM25 search engine for keyword matching.
    private let bm25Search: BM25Search

    /// The semantic search engine for similarity matching.
    private let semanticSearch: SemanticSearch

    /// The chunk store for retrieving chunk data.
    private let chunkStore: any ChunkStore

    /// The RRF fusion algorithm instance.
    private let fusion: RRFFusion

    /// Shared glob pattern matcher with LRU cache.
    private let globMatcher: GlobMatcher

    /// Creates a new hybrid search engine.
    ///
    /// - Parameters:
    ///   - chunkStore: The chunk store with FTS5 support.
    ///   - vectorStore: The vector store with HNSW index.
    ///   - embeddingProvider: The provider for query embedding.
    ///   - rrfK: The k parameter for RRF fusion (default: 60).
    public init(
        chunkStore: any ChunkStore,
        vectorStore: any VectorStore,
        embeddingProvider: any EmbeddingProvider,
        rrfK: Int = 60,
        globMatcher: GlobMatcher = GlobMatcher()
    ) {
        self.chunkStore = chunkStore
        self.globMatcher = globMatcher
        bm25Search = BM25Search(chunkStore: chunkStore, globMatcher: globMatcher)
        semanticSearch = SemanticSearch(
            vectorStore: vectorStore,
            chunkStore: chunkStore,
            embeddingProvider: embeddingProvider,
            globMatcher: globMatcher
        )
        fusion = RRFFusion(k: rrfK)
    }

    /// Performs a hybrid search combining BM25 and semantic results.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - options: Search configuration options.
    /// - Returns: Array of search results ranked by combined relevance.
    public func search(query: String, options: SearchOptions) async throws -> [SearchResult] {
        // Calculate search limits for each method
        // Fetch more than needed to ensure we have enough after fusion
        let fetchLimit = options.limit * 3

        // Run BM25 and semantic search in parallel
        async let bm25Task = bm25Search.searchRaw(query: query, limit: fetchLimit)
        async let semanticTask = semanticSearch.searchRaw(query: query, limit: fetchLimit)

        let (bm25Results, semanticResults) = try await (bm25Task, semanticTask)

        // Apply weighted RRF fusion
        let bm25Weight = 1.0 - options.semanticWeight
        let semanticWeight = options.semanticWeight

        let fusedResults = fusion.fuse(
            bm25Results,
            firstWeight: bm25Weight,
            semanticResults,
            secondWeight: semanticWeight
        )

        // Build lookup dictionaries for original scores
        let bm25Scores = Dictionary(
            uniqueKeysWithValues: bm25Results.enumerated().map { ($1.id, (score: $1.score, rank: $0 + 1)) }
        )
        let semanticScores = Dictionary(
            uniqueKeysWithValues: semanticResults.enumerated().map { ($1.id, (score: $1.score, rank: $0 + 1)) }
        )

        // Convert fused results to SearchResults
        var results: [SearchResult] = []

        for fusedItem in fusedResults {
            guard let chunk = try await chunkStore.get(id: fusedItem.id) else {
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

            let bm25Info = bm25Scores[fusedItem.id]
            let semanticInfo = semanticScores[fusedItem.id]

            let result = SearchResult(
                chunk: chunk,
                score: fusedItem.score,
                bm25Score: bm25Info?.score,
                semanticScore: semanticInfo?.score,
                bm25Rank: bm25Info?.rank,
                semanticRank: semanticInfo?.rank,
                isMultiHop: false,
                hopDepth: 0
            )
            results.append(result)

            if results.count >= options.limit {
                break
            }
        }

        // Optionally perform multi-hop search
        if options.multiHop, options.multiHopDepth > 0 {
            let multiHopResults = try await performMultiHop(
                initialResults: results,
                options: options,
                currentDepth: 1
            )
            results.append(contentsOf: multiHopResults)
        }

        // Final sort and limit
        return Array(results.sorted().prefix(options.limit))
    }

    // MARK: - Multi-Hop Search

    /// Performs multi-hop reference following to find related chunks.
    ///
    /// - Parameters:
    ///   - initialResults: The initial search results.
    ///   - options: Search configuration options.
    ///   - currentDepth: Current hop depth.
    /// - Returns: Additional results from multi-hop traversal.
    private func performMultiHop(
        initialResults: [SearchResult],
        options: SearchOptions,
        currentDepth: Int
    ) async throws -> [SearchResult] {
        guard currentDepth <= options.multiHopDepth else {
            return []
        }

        var hopResults: [SearchResult] = []
        let seenIds = Set(initialResults.map(\.chunk.id))

        for result in initialResults.prefix(5) { // Limit hop sources
            // Follow references from this chunk
            for reference in result.chunk.references {
                // Search for chunks containing this symbol
                let refResults = try await bm25Search.searchRaw(
                    query: reference,
                    limit: 3
                )

                for (rank, refResult) in refResults.enumerated() {
                    guard !seenIds.contains(refResult.id) else {
                        continue
                    }

                    guard let chunk = try await chunkStore.get(id: refResult.id) else {
                        continue
                    }

                    // Apply filters
                    if let pathFilter = options.pathFilter {
                        guard await globMatcher.matches(chunk.path, pattern: pathFilter) else {
                            continue
                        }
                    }

                    // Decay score based on hop depth
                    let decayFactor = pow(0.7, Float(currentDepth))
                    let hopScore = refResult.score * decayFactor

                    let hopResult = SearchResult(
                        chunk: chunk,
                        score: hopScore,
                        bm25Score: refResult.score,
                        semanticScore: nil,
                        bm25Rank: rank + 1,
                        semanticRank: nil,
                        isMultiHop: true,
                        hopDepth: currentDepth
                    )
                    hopResults.append(hopResult)
                }
            }
        }

        // Recursively follow more hops if configured
        if currentDepth < options.multiHopDepth, !hopResults.isEmpty {
            let nextHopResults = try await performMultiHop(
                initialResults: hopResults,
                options: options,
                currentDepth: currentDepth + 1
            )
            hopResults.append(contentsOf: nextHopResults)
        }

        return hopResults
    }

    // MARK: - Info Snippet Search

    /// Searches for info snippets (documentation) using BM25 full-text search.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - limit: Maximum number of results to return.
    ///   - pathFilter: Optional glob pattern to filter results by path.
    /// - Returns: Array of info snippet search results ranked by relevance.
    public func searchInfoSnippets(
        query: String,
        limit: Int = 10,
        pathFilter: String? = nil
    ) async throws -> [InfoSnippetSearchResult] {
        // Check if chunk store supports info snippets
        guard let snippetStore = chunkStore as? InfoSnippetStore else {
            return []
        }

        // Perform FTS search
        let rawResults = try await snippetStore.searchSnippetsFTS(query: query, limit: limit * 2)

        // Filter and convert results
        var results: [InfoSnippetSearchResult] = []

        for (snippet, score) in rawResults {
            // Apply path filter if specified
            if let pathFilter {
                guard await globMatcher.matches(snippet.path, pattern: pathFilter) else {
                    continue
                }
            }

            results.append(InfoSnippetSearchResult(snippet: snippet, score: score))

            if results.count >= limit {
                break
            }
        }

        return results.sorted()
    }
}

// MARK: - Search Strategy

public extension HybridSearchEngine {
    /// Available search strategies.
    enum Strategy: Sendable {
        /// Use only BM25 keyword search.
        case bm25Only

        /// Use only semantic similarity search.
        case semanticOnly

        /// Use hybrid search with specified semantic weight.
        case hybrid(semanticWeight: Float)

        /// Default hybrid strategy.
        public static let `default` = Strategy.hybrid(semanticWeight: 0.7)
    }

    /// Creates search options for a specific strategy.
    ///
    /// - Parameters:
    ///   - strategy: The search strategy to use.
    ///   - limit: Maximum results to return.
    /// - Returns: Configured search options.
    static func options(
        for strategy: Strategy,
        limit: Int = 20
    ) -> SearchOptions {
        switch strategy {
        case .bm25Only:
            SearchOptions(limit: limit, semanticWeight: 0.0)
        case .semanticOnly:
            SearchOptions(limit: limit, semanticWeight: 1.0)
        case let .hybrid(weight):
            SearchOptions(limit: limit, semanticWeight: weight)
        }
    }
}

// MARK: - Enhanced Search with Query Expansion

public extension HybridSearchEngine {
    /// Result of an enhanced search operation.
    struct EnhancedSearchResult: Sendable {
        /// The search results.
        public let results: [SearchResult]

        /// The expanded query (if expansion was performed).
        public let expandedQuery: ExpandedQuery?

        /// Whether query expansion was performed.
        public var wasExpanded: Bool { expandedQuery != nil }
    }

    /// Performs a search with optional LLM-powered query expansion.
    ///
    /// Query expansion generates semantically related terms to improve recall.
    /// The expanded terms are searched alongside the original query.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - options: Search configuration options.
    ///   - expander: The query expander (nil to skip expansion).
    ///   - timeout: Timeout for query expansion.
    /// - Returns: Enhanced search result with expanded query info.
    func searchWithExpansion(
        query: String,
        options: SearchOptions,
        expander: QueryExpander?,
        timeout: TimeInterval = 30
    ) async throws -> EnhancedSearchResult {
        // If no expander, perform standard search
        guard let expander else {
            let results = try await search(query: query, options: options)
            return EnhancedSearchResult(results: results, expandedQuery: nil)
        }

        // Try to expand the query
        let expandedQuery: ExpandedQuery
        do {
            expandedQuery = try await expander.expand(query, timeout: timeout)
        } catch {
            // Expansion failed, fall back to standard search
            let results = try await search(query: query, options: options)
            return EnhancedSearchResult(results: results, expandedQuery: nil)
        }

        // Search with all expanded terms
        // Use the original query for semantic search (best representation)
        // Use combined terms for BM25 (keyword coverage)
        let expandedBM25Query = expandedQuery.allTerms.joined(separator: " ")

        // Fetch more results to account for overlap
        let fetchLimit = options.limit * 4

        // Run searches with original and expanded queries
        async let originalSemanticTask = semanticSearch.searchRaw(
            query: query,
            limit: fetchLimit
        )
        async let expandedBM25Task = bm25Search.searchRaw(
            query: expandedBM25Query,
            limit: fetchLimit
        )

        let (semanticResults, bm25Results) = try await (
            originalSemanticTask,
            expandedBM25Task
        )

        // Fuse results
        let bm25Weight = 1.0 - options.semanticWeight
        let semanticWeight = options.semanticWeight

        let fusedResults = fusion.fuse(
            bm25Results,
            firstWeight: bm25Weight,
            semanticResults,
            secondWeight: semanticWeight
        )

        // Build results
        var results: [SearchResult] = []
        let bm25Scores: [String: (score: Float, rank: Int)] = Dictionary(
            uniqueKeysWithValues: bm25Results.enumerated().map { index, result in
                (result.id, (score: result.score, rank: index + 1))
            }
        )
        let semanticScores: [String: (score: Float, rank: Int)] = Dictionary(
            uniqueKeysWithValues: semanticResults.enumerated().map { index, result in
                (result.id, (score: result.score, rank: index + 1))
            }
        )

        for fusedItem in fusedResults {
            guard let chunk = try await chunkStore.get(id: fusedItem.id) else {
                continue
            }

            // Apply filters
            if let pathFilter = options.pathFilter {
                guard await globMatcher.matches(chunk.path, pattern: pathFilter) else {
                    continue
                }
            }

            if let extensionFilter = options.extensionFilter, !extensionFilter.isEmpty {
                let ext = (chunk.path as NSString).pathExtension.lowercased()
                guard extensionFilter.contains(ext) else {
                    continue
                }
            }

            let bm25Info = bm25Scores[fusedItem.id]
            let semanticInfo = semanticScores[fusedItem.id]

            let result = SearchResult(
                chunk: chunk,
                score: fusedItem.score,
                bm25Score: bm25Info?.score,
                semanticScore: semanticInfo?.score,
                bm25Rank: bm25Info?.rank,
                semanticRank: semanticInfo?.rank,
                isMultiHop: false,
                hopDepth: 0
            )
            results.append(result)

            if results.count >= options.limit {
                break
            }
        }

        return EnhancedSearchResult(
            results: Array(results.sorted().prefix(options.limit)),
            expandedQuery: expandedQuery
        )
    }
}
