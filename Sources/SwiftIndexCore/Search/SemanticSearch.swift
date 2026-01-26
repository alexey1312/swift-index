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

        // Batch fetch chunks to avoid N+1 query pattern
        // Deduplicate IDs to prevent crashes in Dictionary creation and redundant fetches
        let chunkIds = Array(Set(vectorResults.map(\.id)))
        let chunks = try await chunkStore.getByIDs(chunkIds)
        let chunkMap = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) })

        for (rank, (chunkId, similarity)) in vectorResults.enumerated() {
            guard let chunk = chunkMap[chunkId] else {
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
    /// Applies metadata-aware re-ranking based on query intent.
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
        // Fetch extra results for re-ranking
        let fetchLimit = limit * 2
        let vectorResults = try await vectorStore.search(vector: queryVector, limit: fetchLimit)

        // Analyze query for protocol/implementation intent
        let queryAnalysis = analyzeQueryIntent(query)

        // Re-rank based on metadata if applicable
        if queryAnalysis.needsReranking {
            var rankedResults: [(id: String, score: Float)] = []

            // Batch fetch chunks for re-ranking
            // Deduplicate IDs to prevent crashes in Dictionary creation and redundant fetches
            let chunkIds = Array(Set(vectorResults.map(\.id)))
            let chunks = try await chunkStore.getByIDs(chunkIds)
            let chunkMap = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) })

            for result in vectorResults {
                guard let chunk = chunkMap[result.id] else {
                    rankedResults.append((id: result.id, score: result.similarity))
                    continue
                }

                // Calculate re-ranking boost
                let boost = calculateMetadataBoost(chunk: chunk, queryAnalysis: queryAnalysis)
                let adjustedScore = result.similarity * boost

                rankedResults.append((id: result.id, score: adjustedScore))
            }

            // Sort by adjusted score and limit
            return rankedResults
                .sorted { $0.score > $1.score }
                .prefix(limit)
                .map(\.self)
        }

        return vectorResults.prefix(limit).map { (id: $0.id, score: $0.similarity) }
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

    // MARK: - Query Analysis

    /// Result of query intent analysis for re-ranking.
    private struct QueryAnalysis {
        /// Whether re-ranking is needed based on query patterns.
        var needsReranking: Bool = false

        /// Whether query asks about protocol implementations.
        var asksAboutImplementation: Bool = false

        /// Whether query mentions specific protocols.
        var mentionsProtocol: Bool = false

        /// Protocol/type names extracted from query.
        var targetTypes: [String] = []

        /// Whether query asks about specific code kinds.
        var preferredKinds: [ChunkKind] = []
    }

    /// Analyzes query to detect intent patterns for re-ranking.
    ///
    /// Detects patterns like:
    /// - "what implements ChunkStore" → boost conformances matching ChunkStore
    /// - "protocol for search" → boost protocol kinds
    /// - "class that handles auth" → boost class kinds
    private nonisolated func analyzeQueryIntent(_ query: String) -> QueryAnalysis {
        var analysis = QueryAnalysis()
        let lowercased = query.lowercased()

        // Pattern: "implements X", "conforms to X", "inherits from X"
        let implementationPatterns = [
            "implement", "implements", "implementing",
            "conforms to", "conforming to",
            "inherits", "inheriting", "extends",
            "subclass of", "child of",
        ]

        for pattern in implementationPatterns {
            if lowercased.contains(pattern) {
                analysis.asksAboutImplementation = true
                analysis.needsReranking = true
                break
            }
        }

        // Pattern: "what X", "which X", "find X" - extract type name after pattern
        let queryPatterns = [
            "what implements",
            "which implements",
            "find implementations of",
            "classes that implement",
            "structs that implement",
            "types that implement",
            "conforms to",
            "inherits from",
        ]

        for pattern in queryPatterns {
            if let range = lowercased.range(of: pattern) {
                let afterPattern = String(query[range.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: .whitespaces)
                    .first ?? ""

                if !afterPattern.isEmpty {
                    // Capitalize first letter (likely a type name)
                    let typeName = afterPattern.prefix(1).uppercased() + afterPattern.dropFirst()
                    analysis.targetTypes.append(typeName)
                }
            }
        }

        // Extract PascalCase words as potential type names
        let pascalCasePattern = try? NSRegularExpression(pattern: "\\b[A-Z][a-zA-Z0-9]+\\b")
        if let regex = pascalCasePattern {
            let matches = regex.matches(in: query, range: NSRange(query.startIndex..., in: query))
            for match in matches {
                if let range = Range(match.range, in: query) {
                    let typeName = String(query[range])
                    if !analysis.targetTypes.contains(typeName) {
                        analysis.targetTypes.append(typeName)
                    }
                }
            }
        }

        // Pattern: mentions protocol
        if lowercased.contains("protocol") {
            analysis.mentionsProtocol = true
            analysis.needsReranking = true
            analysis.preferredKinds.append(.protocol)
        }

        // Pattern: mentions class/struct/actor
        if lowercased.contains("class") || lowercased.contains("classes") {
            analysis.preferredKinds.append(.class)
            analysis.needsReranking = true
        }
        if lowercased.contains("struct") || lowercased.contains("structs") {
            analysis.preferredKinds.append(.struct)
            analysis.needsReranking = true
        }
        if lowercased.contains("actor") || lowercased.contains("actors") {
            analysis.preferredKinds.append(.actor)
            analysis.needsReranking = true
        }

        return analysis
    }

    /// Calculates metadata-based boost multiplier for a chunk.
    ///
    /// - Parameters:
    ///   - chunk: The code chunk to evaluate.
    ///   - queryAnalysis: The analyzed query intent.
    /// - Returns: Boost multiplier (1.0 = no boost, >1.0 = boosted).
    private nonisolated func calculateMetadataBoost(
        chunk: CodeChunk,
        queryAnalysis: QueryAnalysis
    ) -> Float {
        var boost: Float = 1.0

        // Boost for matching conformances
        if queryAnalysis.asksAboutImplementation, !queryAnalysis.targetTypes.isEmpty {
            for targetType in queryAnalysis.targetTypes {
                // Check if chunk conforms to or mentions target type
                let conformanceMatch = chunk.conformances.contains { conformance in
                    conformance.lowercased().contains(targetType.lowercased())
                }
                if conformanceMatch {
                    boost *= 1.5 // Strong boost for direct conformance match
                }

                // Also check symbols (for extensions adding conformance)
                let symbolMatch = chunk.symbols.contains { symbol in
                    symbol.lowercased().contains(targetType.lowercased())
                }
                if symbolMatch, !conformanceMatch {
                    boost *= 1.2 // Moderate boost for symbol match
                }
            }
        }

        // Boost for preferred chunk kinds
        if !queryAnalysis.preferredKinds.isEmpty {
            if queryAnalysis.preferredKinds.contains(chunk.kind) {
                boost *= 1.3
            }
        }

        // Boost protocols when looking for protocols
        if queryAnalysis.mentionsProtocol, chunk.kind == .protocol {
            boost *= 1.3
        }

        // Boost implementations (not protocols) when looking for implementations
        if queryAnalysis.asksAboutImplementation, chunk.kind != .protocol {
            if !chunk.conformances.isEmpty {
                boost *= 1.2 // Has conformances, likely an implementation
            }
        }

        return boost
    }
}
