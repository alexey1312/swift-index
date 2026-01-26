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

    /// Type alias for score lookup dictionary.
    private typealias ScoreLookup = [String: (score: Float, rank: Int)]

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
        // Fetch more than needed to ensure we have enough after fusion and filtering
        // Higher multiplier improves recall at the cost of processing more candidates
        let fetchLimit = options.limit * 5

        // Extract query terms for boost calculations
        let queryTerms = extractQueryTerms(from: query)

        // Detect "implements X" pattern and get conforming types
        let conformanceResults = try await getConformanceResults(query: query, limit: fetchLimit)

        // Run BM25 and semantic search in parallel
        async let bm25Task = bm25Search.searchRaw(query: query, limit: fetchLimit)
        async let semanticTask = semanticSearch.searchRaw(query: query, limit: fetchLimit)

        let (bm25Results, semanticResults) = try await (bm25Task, semanticTask)

        // Apply weighted RRF fusion (with conformance results as third source)
        let bm25Weight = 1.0 - options.semanticWeight
        let semanticWeight = options.semanticWeight

        let fusedResults: [(id: String, score: Float, ranks: [Int?])] = if conformanceResults.isEmpty {
            fusion.fuse(
                bm25Results,
                firstWeight: bm25Weight,
                semanticResults,
                secondWeight: semanticWeight
            )
        } else {
            // Include conformance results with high weight (3.0x boost)
            fusion.fuse(
                [bm25Results, semanticResults, conformanceResults],
                weights: [bm25Weight, semanticWeight, 3.0]
            )
        }

        // Build lookup dictionaries for original scores
        let bm25Scores = buildScoreLookup(from: bm25Results)
        let semanticScores = buildScoreLookup(from: semanticResults)
        let conformanceIds = Set(conformanceResults.map(\.id))

        // Convert fused results to SearchResults
        var results: [SearchResult] = []

        for fusedItem in fusedResults {
            guard let chunk = try await chunkStore.get(id: fusedItem.id),
                  await passesFilters(chunk, options: options)
            else {
                continue
            }

            let bm25Info = bm25Scores[fusedItem.id]
            let semanticInfo = semanticScores[fusedItem.id]

            // Apply all ranking boosts
            let (boostedScore, hasExactMatch) = try await applyRankingBoosts(
                baseScore: fusedItem.score,
                chunk: chunk,
                query: query,
                queryTerms: queryTerms
            )

            let result = SearchResult(
                chunk: chunk,
                score: boostedScore,
                bm25Score: bm25Info?.score,
                semanticScore: semanticInfo?.score,
                bm25Rank: bm25Info?.rank,
                semanticRank: semanticInfo?.rank,
                isMultiHop: false,
                hopDepth: 0,
                exactSymbolMatch: hasExactMatch || conformanceIds.contains(fusedItem.id)
            )
            results.append(result)

            if results.count >= options.limit * 2 {
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
        return Array(results.sorted { $0.score > $1.score }.prefix(options.limit))
    }

    // MARK: - Helper Methods

    /// Builds a score lookup dictionary from raw search results.
    private nonisolated func buildScoreLookup(
        from results: [(id: String, score: Float)]
    ) -> ScoreLookup {
        Dictionary(uniqueKeysWithValues: results.enumerated().map { index, result in
            (result.id, (score: result.score, rank: index + 1))
        })
    }

    /// Checks if a chunk passes the configured filters.
    private func passesFilters(_ chunk: CodeChunk, options: SearchOptions) async -> Bool {
        if let pathFilter = options.pathFilter {
            guard await globMatcher.matches(chunk.path, pattern: pathFilter) else {
                return false
            }
        }

        if let extensionFilter = options.extensionFilter, !extensionFilter.isEmpty {
            let ext = (chunk.path as NSString).pathExtension.lowercased()
            guard extensionFilter.contains(ext) else {
                return false
            }
        }

        return true
    }

    // MARK: - Ranking Boost Constants

    /// Threshold for rare term detection (terms appearing fewer times receive boost).
    private static let rareTermThreshold = 10

    /// Boost multiplier for exact symbol match on rare terms.
    private static let exactSymbolBoost: Float = 2.5

    /// Boost multiplier for exact content match on rare CamelCase terms.
    /// Lower than symbol boost since content matches are less precise.
    private static let exactContentBoost: Float = 2.0

    /// Boost multiplier for paths containing "/Sources/" vs "/Tests/".
    private static let sourcePathBoost: Float = 1.1

    /// Boost multiplier for public declarations.
    private static let publicModifierBoost: Float = 1.1

    /// Demotion multiplier for standard protocol extensions in conceptual queries.
    private static let standardProtocolDemotion: Float = 0.5

    /// Demotion for BM25 results matching only part of CamelCase term.
    private static let partialMatchDemotion: Float = 0.3

    /// Standard Swift protocols that often add noise to conceptual queries.
    private static let standardProtocols: Set<String> = [
        "Comparable", "Equatable", "Hashable", "Codable",
        "Sendable", "CustomStringConvertible", "CustomDebugStringConvertible",
        "Encodable", "Decodable", "Identifiable", "CaseIterable",
    ]

    /// Applies all ranking boosts to a search result.
    ///
    /// Combines multiple boost factors:
    /// - Exact symbol match boost (2.5x for rare terms)
    /// - Content-based CamelCase match boost (2.0x for rare CamelCase identifiers)
    /// - Source path boost (1.1x for /Sources/ vs /Tests/)
    /// - Public modifier boost (1.1x for public declarations)
    /// - Standard protocol extension demotion (0.5x in conceptual queries)
    ///
    /// - Parameters:
    ///   - baseScore: The original fusion score.
    ///   - chunk: The code chunk to evaluate.
    ///   - query: The original query string.
    ///   - queryTerms: Extracted query terms.
    /// - Returns: Tuple of (boosted score, whether exact match was found).
    private func applyRankingBoosts(
        baseScore: Float,
        chunk: CodeChunk,
        query: String,
        queryTerms: [String]
    ) async throws -> (score: Float, hasExactMatch: Bool) {
        var score = baseScore
        var hasExactMatch = false

        // 1. Exact symbol match boost for rare terms
        for term in queryTerms {
            if chunk.symbols.contains(term) {
                let frequency = try await chunkStore.getTermFrequency(term: term)
                if frequency < Self.rareTermThreshold {
                    hasExactMatch = true
                    score *= Self.exactSymbolBoost
                    break // Only apply once
                }
            }
        }

        // 2. Content-based exact match boost for rare CamelCase terms
        // Only applies if no symbol match was found (prevents double-boosting)
        if !hasExactMatch {
            for term in queryTerms where isCamelCaseIdentifier(term) {
                if chunk.content.contains(term) {
                    let frequency = try await chunkStore.getTermFrequency(term: term)
                    if frequency < Self.rareTermThreshold {
                        hasExactMatch = true
                        score *= Self.exactContentBoost
                        break // Only apply once
                    }
                }
            }
        }

        // 3. Source path boost (prioritize production code over tests)
        if chunk.path.contains("/Sources/") {
            score *= Self.sourcePathBoost
        }

        // 4. Public modifier boost (prioritize public API)
        if let signature = chunk.signature, signature.hasPrefix("public ") {
            score *= Self.publicModifierBoost
        }

        // 5. Standard protocol extension demotion (for conceptual queries)
        if isConceptualQuery(query), isStandardProtocolExtension(chunk) {
            score *= Self.standardProtocolDemotion
        }

        // 6. Partial match demotion for CamelCase queries
        if !hasExactCamelCaseMatch(chunk: chunk, queryTerms: queryTerms) {
            score *= Self.partialMatchDemotion
        }

        return (score, hasExactMatch)
    }

    /// Detects if a query is conceptual (asking "how", "what", "where", or semantic search).
    ///
    /// Conceptual queries focus on understanding rather than finding specific code,
    /// so standard protocol extensions (Comparable, Equatable, etc.) are demoted.
    ///
    /// - Parameter query: The search query.
    /// - Returns: True if the query is conceptual.
    private nonisolated func isConceptualQuery(_ query: String) -> Bool {
        let lowercased = query.lowercased()

        // Question patterns
        let questionPatterns = ["how ", "what ", "where ", "why ", "which "]
        if questionPatterns.contains(where: { lowercased.contains($0) }) {
            return true
        }

        // Semantic search patterns
        let semanticPatterns = [
            "nearest neighbor", "vector search", "similarity search",
            "semantic search", "k-nearest", "knn", "embedding search",
        ]
        return semanticPatterns.contains(where: { lowercased.contains($0) })
    }

    /// Checks if a chunk is an extension conforming to a standard protocol.
    ///
    /// Standard protocols like Comparable, Equatable, Hashable often add noise
    /// to conceptual searches because they appear in many types but don't represent
    /// the core functionality being searched for.
    ///
    /// - Parameter chunk: The code chunk to check.
    /// - Returns: True if the chunk is a standard protocol extension.
    private nonisolated func isStandardProtocolExtension(_ chunk: CodeChunk) -> Bool {
        guard chunk.kind == .extension else { return false }

        // Check if any conformance is a standard protocol
        return chunk.conformances.contains { conformance in
            Self.standardProtocols.contains(conformance)
        }
    }

    /// Checks if a chunk contains an exact match for any CamelCase query term.
    ///
    /// Used to demote BM25 results that only partially match CamelCase identifiers
    /// (e.g., "BM25Search" matching query "USearchError" via "Search" substring).
    ///
    /// - Parameters:
    ///   - chunk: The code chunk to check.
    ///   - queryTerms: Extracted query terms.
    /// - Returns: True if exact CamelCase match exists or no CamelCase terms in query.
    private nonisolated func hasExactCamelCaseMatch(
        chunk: CodeChunk,
        queryTerms: [String]
    ) -> Bool {
        let camelCaseTerms = queryTerms.filter { isCamelCaseIdentifier($0) }
        guard !camelCaseTerms.isEmpty else { return true }

        for term in camelCaseTerms {
            if chunk.symbols.contains(term) ||
                chunk.content.contains(term) ||
                chunk.references.contains(term)
            {
                return true
            }
        }
        return false
    }

    /// Detects if a term is a CamelCase identifier (e.g., USearchError, CodeChunk).
    ///
    /// CamelCase identifiers are common in Swift code and warrant exact matching
    /// to avoid false positives from partial matches.
    ///
    /// - Parameter term: The term to check.
    /// - Returns: True if the term is a CamelCase identifier.
    private nonisolated func isCamelCaseIdentifier(_ term: String) -> Bool {
        // Minimum 3 characters, starts with letter, no spaces, mixed case
        term.count >= 3 &&
            term.first?.isLetter == true &&
            !term.contains(" ") &&
            term.contains(where: \.isUppercase) &&
            term.contains(where: \.isLowercase)
    }

    // MARK: - Conformance Detection

    /// Detects "implements X" patterns and returns conforming type chunks.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - limit: Maximum results to return.
    /// - Returns: Array of (id, score) pairs for conforming types.
    private func getConformanceResults(
        query: String,
        limit: Int
    ) async throws -> [(id: String, score: Float)] {
        // Detect "implements X" or "conforms to X" patterns
        let patterns = [
            #/implements\s+(\w+)/#,
            #/conforms\s+to\s+(\w+)/#,
            #/what\s+implements\s+(\w+)/#,
            #/types?\s+implementing\s+(\w+)/#,
            #/classes?\s+implementing\s+(\w+)/#,
            #/structs?\s+implementing\s+(\w+)/#,
            #/actors?\s+implementing\s+(\w+)/#,
        ]

        for pattern in patterns {
            if let match = try? pattern.firstMatch(in: query.lowercased()) {
                let protocolName = String(match.1)
                // Capitalize first letter for proper Swift naming
                let capitalizedName = protocolName.prefix(1).uppercased() + protocolName.dropFirst()

                guard let grdbStore = chunkStore as? GRDBChunkStore else {
                    continue
                }

                let conformingTypes = try await grdbStore.findConformingTypes(protocol: capitalizedName)

                // Return as ranked list with high scores
                return conformingTypes.prefix(limit).enumerated().map { index, chunk in
                    // Score decreases slightly by rank to maintain ordering
                    (id: chunk.id, score: Float(limit - index))
                }
            }
        }

        return []
    }

    /// Extracts meaningful terms from a query for boost calculations.
    private func extractQueryTerms(from query: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "what", "how", "where",
            "when", "why", "which", "who", "that", "this", "to", "for", "of", "in",
            "on", "at", "by", "with", "from", "implements", "conforms", "types",
            "type", "class", "struct", "actor", "enum", "protocol", "extension",
        ]

        return query
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count >= 2 }
            .filter { !stopWords.contains($0.lowercased()) }
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
        let bm25Scores = buildScoreLookup(from: bm25Results)
        let semanticScores = buildScoreLookup(from: semanticResults)

        for fusedItem in fusedResults {
            guard let chunk = try await chunkStore.get(id: fusedItem.id),
                  await passesFilters(chunk, options: options)
            else {
                continue
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
