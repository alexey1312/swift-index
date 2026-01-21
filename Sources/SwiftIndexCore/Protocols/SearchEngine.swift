// MARK: - SearchEngine Protocol

import Foundation

/// A search engine that performs code search operations.
///
/// Search engines combine various search strategies (BM25, semantic, etc.)
/// to find relevant code chunks based on user queries.
public protocol SearchEngine: Sendable {
    /// Perform a search with the given query and options.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - options: Search configuration options.
    /// - Returns: Array of search results ranked by relevance.
    func search(query: String, options: SearchOptions) async throws -> [SearchResult]
}

/// Options for configuring search behavior.
public struct SearchOptions: Sendable, Equatable {
    /// Maximum number of results to return.
    public var limit: Int

    /// Weight for semantic search (0.0 to 1.0).
    /// BM25 weight is (1 - semanticWeight).
    public var semanticWeight: Float

    /// Optional path filter (glob pattern).
    public var pathFilter: String?

    /// Optional file extension filter.
    public var extensionFilter: Set<String>?

    /// RRF k parameter for rank fusion.
    public var rrfK: Int

    /// Enable multi-hop reference following.
    public var multiHop: Bool

    /// Maximum depth for multi-hop search.
    public var multiHopDepth: Int

    public init(
        limit: Int = 20,
        semanticWeight: Float = 0.7,
        pathFilter: String? = nil,
        extensionFilter: Set<String>? = nil,
        rrfK: Int = 60,
        multiHop: Bool = false,
        multiHopDepth: Int = 2
    ) {
        self.limit = limit
        self.semanticWeight = semanticWeight
        self.pathFilter = pathFilter
        self.extensionFilter = extensionFilter
        self.rrfK = rrfK
        self.multiHop = multiHop
        self.multiHopDepth = multiHopDepth
    }

    /// Default search options.
    public static let `default` = SearchOptions()
}
