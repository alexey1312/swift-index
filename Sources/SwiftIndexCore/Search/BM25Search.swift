// MARK: - BM25 Search Engine

import Foundation

/// A keyword-based search engine using BM25 via FTS5.
///
/// BM25Search leverages the ChunkStore's FTS5 full-text search capabilities
/// to perform keyword-based relevance ranking. It serves as one half of the
/// hybrid search strategy.
///
/// ## Features
///
/// - Full-text keyword search using SQLite FTS5
/// - BM25 ranking algorithm for relevance scoring
/// - Optional path and extension filtering
/// - Score normalization for fusion compatibility
///
/// ## Usage
///
/// ```swift
/// let search = BM25Search(chunkStore: store)
/// let results = try await search.search(
///     query: "authentication",
///     options: .default
/// )
/// ```
public actor BM25Search: SearchEngine {
    /// The chunk store providing FTS5 search capabilities.
    private let chunkStore: any ChunkStore

    /// Shared glob pattern matcher with LRU cache.
    private let globMatcher: GlobMatcher

    /// Creates a new BM25 search engine.
    ///
    /// - Parameters:
    ///   - chunkStore: The chunk store with FTS5 support.
    ///   - globMatcher: Shared glob pattern matcher for path filtering.
    public init(chunkStore: any ChunkStore, globMatcher: GlobMatcher = GlobMatcher()) {
        self.chunkStore = chunkStore
        self.globMatcher = globMatcher
    }

    /// Performs a BM25 keyword search.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - options: Search configuration options.
    /// - Returns: Array of search results with BM25 scores.
    public func search(query: String, options: SearchOptions) async throws -> [SearchResult] {
        // Perform FTS5 search
        let ftsResults = try await chunkStore.searchFTS(
            query: prepareQuery(query),
            limit: options.limit * 2 // Fetch extra for filtering
        )

        // Filter and transform results
        var results: [SearchResult] = []

        for (rank, (chunk, score)) in ftsResults.enumerated() {
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
                score: Float(score),
                bm25Score: Float(score),
                semanticScore: nil,
                bm25Rank: rank + 1,
                semanticRank: nil,
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

    /// Performs a raw BM25 search returning chunk IDs and scores.
    ///
    /// This method is used internally by HybridSearchEngine for fusion.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - limit: Maximum number of results.
    /// - Returns: Array of (chunk ID, BM25 score) pairs.
    public func searchRaw(
        query: String,
        limit: Int
    ) async throws -> [(id: String, score: Float)] {
        let ftsResults = try await chunkStore.searchFTS(
            query: prepareQuery(query),
            limit: limit
        )

        return ftsResults.map { (id: $0.chunk.id, score: Float($0.score)) }
    }

    // MARK: - Private Helpers

    /// Prepares a query for FTS5 search.
    ///
    /// - Parameter query: The raw query string.
    /// - Returns: FTS5-compatible query string.
    private func prepareQuery(_ query: String) -> String {
        // Split into terms and join with AND for FTS5
        let terms = query
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .compactMap { term -> String? in
                // Remove FTS5 special characters that cause syntax errors
                // These include: ? * + - ^ ( ) { } [ ] | \ : ~
                let sanitized = term.filter { char in
                    !["?", "*", "+", "^", "(", ")", "{", "}", "[", "]", "|", "\\", ":", "~"].contains(String(char))
                }

                // Skip empty terms after sanitization
                guard !sanitized.isEmpty else { return nil }

                // Escape double quotes for FTS5
                let escaped = sanitized.replacingOccurrences(of: "\"", with: "\"\"")

                // CamelCase identifiers should use exact matching (no wildcard)
                // to prevent "USearchError" from matching just "Search"
                if isCamelCaseIdentifier(escaped) {
                    return "\"\(escaped)\""
                }

                // Use prefix matching for partial words (3+ chars)
                if escaped.count >= 3 {
                    return "\"\(escaped)\"*"
                }
                return "\"\(escaped)\""
            }

        return terms.joined(separator: " ")
    }

    /// Detects if a term is a CamelCase identifier (e.g., USearchError, CodeChunk).
    ///
    /// - Parameter term: The term to check.
    /// - Returns: True if the term is a CamelCase identifier.
    private nonisolated func isCamelCaseIdentifier(_ term: String) -> Bool {
        // Minimum 3 characters, starts with letter, no spaces
        guard term.count >= 3,
              term.first?.isLetter == true,
              !term.contains(" ")
        else {
            return false
        }
        // Must contain both uppercase and lowercase letters
        return term.contains(where: \.isUppercase) &&
            term.contains(where: \.isLowercase)
    }
}
