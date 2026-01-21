// MARK: - RRF Fusion

import Foundation

/// Reciprocal Rank Fusion algorithm for combining multiple ranked lists.
///
/// RRF is a rank aggregation method that combines results from multiple search
/// systems without requiring score normalization. The formula is:
/// ```
/// score = sum(1 / (k + rank_i))
/// ```
/// where k is a constant (typically 60) that reduces the impact of high-ranking results.
///
/// ## Usage
///
/// ```swift
/// let fusion = RRFFusion(k: 60)
/// let combined = fusion.fuse([bm25Results, semanticResults])
/// ```
///
/// ## References
///
/// - Cormack, G. V., Clarke, C. L., & Buettcher, S. (2009).
///   "Reciprocal rank fusion outperforms condorcet and individual rank learning methods"
public struct RRFFusion: Sendable {
    /// The k parameter that controls the impact of high-ranking results.
    ///
    /// Higher values make the fusion more uniform across ranks.
    /// Lower values give more weight to top-ranked results.
    /// Default is 60, as recommended in the original paper.
    public let k: Int

    /// Creates a new RRF fusion instance.
    ///
    /// - Parameter k: The k parameter (default: 60).
    public init(k: Int = 60) {
        precondition(k > 0, "k must be positive")
        self.k = k
    }

    /// Fuses multiple ranked lists into a single ranked result.
    ///
    /// Each input list is a sequence of (identifier, original score) pairs,
    /// ordered by rank (first item = rank 1).
    ///
    /// - Parameter rankedLists: Array of ranked result lists.
    /// - Returns: Fused results sorted by combined RRF score (descending).
    public func fuse<ID: Hashable>(
        _ rankedLists: [[(id: ID, score: Float)]]
    ) -> [(id: ID, score: Float, ranks: [Int?])] {
        var scores: [ID: Float] = [:]
        var ranks: [ID: [Int?]] = [:]

        // Initialize ranks array for each ID
        for (listIndex, list) in rankedLists.enumerated() {
            for (rankIndex, item) in list.enumerated() {
                let rank = rankIndex + 1 // 1-indexed rank
                let contribution = 1.0 / Float(k + rank)
                scores[item.id, default: 0] += contribution

                // Track which rank this ID had in each list
                if ranks[item.id] == nil {
                    ranks[item.id] = Array(repeating: nil, count: rankedLists.count)
                }
                ranks[item.id]?[listIndex] = rank
            }
        }

        // Sort by fused score descending
        return scores
            .map { (id: $0.key, score: $0.value, ranks: ranks[$0.key] ?? []) }
            .sorted { $0.score > $1.score }
    }

    /// Fuses multiple ranked lists with custom weights for each list.
    ///
    /// - Parameters:
    ///   - rankedLists: Array of ranked result lists.
    ///   - weights: Weight for each list (must match rankedLists count).
    /// - Returns: Fused results sorted by weighted RRF score (descending).
    public func fuse<ID: Hashable>(
        _ rankedLists: [[(id: ID, score: Float)]],
        weights: [Float]
    ) -> [(id: ID, score: Float, ranks: [Int?])] {
        precondition(
            rankedLists.count == weights.count,
            "Number of weights must match number of ranked lists"
        )

        var scores: [ID: Float] = [:]
        var ranks: [ID: [Int?]] = [:]

        for (listIndex, list) in rankedLists.enumerated() {
            let weight = weights[listIndex]
            for (rankIndex, item) in list.enumerated() {
                let rank = rankIndex + 1
                let contribution = weight / Float(k + rank)
                scores[item.id, default: 0] += contribution

                if ranks[item.id] == nil {
                    ranks[item.id] = Array(repeating: nil, count: rankedLists.count)
                }
                ranks[item.id]?[listIndex] = rank
            }
        }

        return scores
            .map { (id: $0.key, score: $0.value, ranks: ranks[$0.key] ?? []) }
            .sorted { $0.score > $1.score }
    }

    /// Calculates the RRF score contribution for a given rank.
    ///
    /// - Parameter rank: The 1-indexed rank position.
    /// - Returns: The RRF score contribution.
    public func score(forRank rank: Int) -> Float {
        precondition(rank > 0, "Rank must be positive (1-indexed)")
        return 1.0 / Float(k + rank)
    }
}

// MARK: - Convenience Extensions

public extension RRFFusion {
    /// Fuses two ranked lists (common case for hybrid search).
    ///
    /// - Parameters:
    ///   - first: First ranked list.
    ///   - second: Second ranked list.
    /// - Returns: Fused results.
    func fuse<ID: Hashable>(
        _ first: [(id: ID, score: Float)],
        _ second: [(id: ID, score: Float)]
    ) -> [(id: ID, score: Float, ranks: [Int?])] {
        fuse([first, second])
    }

    /// Fuses two ranked lists with specified weights.
    ///
    /// - Parameters:
    ///   - first: First ranked list.
    ///   - firstWeight: Weight for first list.
    ///   - second: Second ranked list.
    ///   - secondWeight: Weight for second list.
    /// - Returns: Fused results.
    func fuse<ID: Hashable>(
        _ first: [(id: ID, score: Float)],
        firstWeight: Float,
        _ second: [(id: ID, score: Float)],
        secondWeight: Float
    ) -> [(id: ID, score: Float, ranks: [Int?])] {
        fuse([first, second], weights: [firstWeight, secondWeight])
    }
}
