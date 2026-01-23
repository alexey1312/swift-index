// MARK: - SearchResult Model

import Foundation

/// A search result from the hybrid search engine.
public struct SearchResult: Sendable, Equatable, Identifiable {
    /// The matched code chunk.
    public let chunk: CodeChunk

    /// Combined relevance score (0.0 to 1.0, higher is better).
    public let score: Float

    /// BM25 keyword search score component.
    public let bm25Score: Float?

    /// Semantic similarity score component.
    public let semanticScore: Float?

    /// Rank from BM25 results (if applicable).
    public let bm25Rank: Int?

    /// Rank from semantic results (if applicable).
    public let semanticRank: Int?

    /// Whether this result came from multi-hop reference following.
    public let isMultiHop: Bool

    /// The hop depth if this is a multi-hop result.
    public let hopDepth: Int

    public init(
        chunk: CodeChunk,
        score: Float,
        bm25Score: Float? = nil,
        semanticScore: Float? = nil,
        bm25Rank: Int? = nil,
        semanticRank: Int? = nil,
        isMultiHop: Bool = false,
        hopDepth: Int = 0
    ) {
        self.chunk = chunk
        self.score = score
        self.bm25Score = bm25Score
        self.semanticScore = semanticScore
        self.bm25Rank = bm25Rank
        self.semanticRank = semanticRank
        self.isMultiHop = isMultiHop
        self.hopDepth = hopDepth
    }

    // MARK: - Identifiable

    public var id: String { chunk.id }

    // MARK: - Relevance Percentage

    /// Relevance percentage (0-100) based on semantic similarity.
    ///
    /// Uses the semantic score if available, otherwise converts the RRF
    /// fusion score to an approximate percentage.
    public var relevancePercent: Int {
        if let semantic = semanticScore {
            return Int(semantic * 100)
        }
        // RRF max score is ~0.0164 (when k=60), normalize to percentage
        return Int(min(score / 0.0164, 1.0) * 100)
    }
}

// MARK: - Comparable

extension SearchResult: Comparable {
    public static func < (lhs: SearchResult, rhs: SearchResult) -> Bool {
        // Sort by displayed relevance percentage for consistency with UI
        // (relevancePercent prefers semanticScore when available)
        lhs.relevancePercent > rhs.relevancePercent
    }
}

// MARK: - CustomStringConvertible

extension SearchResult: CustomStringConvertible {
    public var description: String {
        let scoreStr = String(format: "%.3f", score)
        let hopStr = isMultiHop ? " (hop \(hopDepth))" : ""
        return "SearchResult(\(chunk.path):\(chunk.startLine), score: \(scoreStr)\(hopStr))"
    }
}
