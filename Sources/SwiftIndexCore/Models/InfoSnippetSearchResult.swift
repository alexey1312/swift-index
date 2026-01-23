// MARK: - InfoSnippetSearchResult Model

import Foundation

/// A search result for an InfoSnippet.
public struct InfoSnippetSearchResult: Sendable, Equatable, Identifiable {
    /// The matched info snippet.
    public let snippet: InfoSnippet

    /// BM25 search score.
    public let score: Double

    public init(snippet: InfoSnippet, score: Double) {
        self.snippet = snippet
        self.score = score
    }

    // MARK: - Identifiable

    public var id: String { snippet.id }

    // MARK: - Relevance Percentage

    /// Relevance percentage (0-100) based on BM25 score.
    ///
    /// BM25 scores are typically in the range 0-25, we normalize to percentage.
    public var relevancePercent: Int {
        Int(min(score / 25.0, 1.0) * 100)
    }
}

// MARK: - Comparable

extension InfoSnippetSearchResult: Comparable {
    public static func < (lhs: InfoSnippetSearchResult, rhs: InfoSnippetSearchResult) -> Bool {
        // Higher scores come first
        lhs.score > rhs.score
    }
}

// MARK: - CustomStringConvertible

extension InfoSnippetSearchResult: CustomStringConvertible {
    public var description: String {
        let scoreStr = String(format: "%.3f", score)
        return "InfoSnippetSearchResult(\(snippet.path):\(snippet.startLine), score: \(scoreStr))"
    }
}
