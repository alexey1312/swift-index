// MARK: - RRF Fusion

import Foundation

/// Reciprocal Rank Fusion algorithm for combining multiple ranked lists.
///
/// RRF is a rank aggregation method that combines results from multiple search
/// systems. The enhanced formula incorporates both rank and original scores:
/// ```
/// score = weight * (alpha * RRF(rank) + (1 - alpha) * normalized_score)
/// ```
/// where:
/// - `k` is a constant (typically 60) that reduces the impact of high-ranking results
/// - `alpha` controls the balance between rank-based and score-based fusion
///
/// ## Usage
///
/// ```swift
/// let fusion = RRFFusion(k: 60, alpha: 0.7)
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

    /// The alpha parameter controlling the balance between rank-based and score-based fusion.
    ///
    /// - `alpha = 1.0`: Pure RRF (only ranks matter)
    /// - `alpha = 0.0`: Pure score-based fusion (only original scores matter)
    /// - `alpha = 0.7`: Default, 70% RRF + 30% normalized score
    ///
    /// Lower alpha values make high-confidence results from either search method
    /// more influential, which helps differentiate exact matches from approximate ones.
    public let alpha: Float

    /// Creates a new RRF fusion instance.
    ///
    /// - Parameters:
    ///   - k: The k parameter (default: 60).
    ///   - alpha: Balance between RRF and score-based fusion (default: 0.7).
    public init(k: Int = 60, alpha: Float = 0.7) {
        precondition(k > 0, "k must be positive")
        precondition(alpha >= 0 && alpha <= 1, "alpha must be between 0 and 1")
        self.k = k
        self.alpha = alpha
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
    /// Uses a hybrid scoring approach that combines rank-based RRF with
    /// normalized original scores, controlled by the `alpha` parameter.
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

            // Find max score in this list for normalization
            // Use 1.0 as fallback to avoid division by zero
            let maxScore = list.map(\.score).max() ?? 1.0
            let normalizer = maxScore > 0 ? maxScore : 1.0

            for (rankIndex, item) in list.enumerated() {
                let rank = rankIndex + 1

                // RRF component: rank-based score
                let rrfScore = 1.0 / Float(k + rank)

                // Score component: normalized original score (0 to 1)
                let normalizedScore = item.score / normalizer

                // Hybrid: combine RRF and normalized score using alpha
                // alpha=1.0 → pure RRF, alpha=0.0 → pure score-based
                let hybridScore = alpha * rrfScore + (1 - alpha) * normalizedScore

                // Apply list weight
                let contribution = weight * hybridScore
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
