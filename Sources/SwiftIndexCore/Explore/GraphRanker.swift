// MARK: - GraphRanker

import Foundation

/// Ranks symbols by how strongly the graph connects them to the search seeds.
///
/// Text search alone ranks a file that mentions every query word above the code
/// that actually runs. A random walk that restarts at the seeds moves score along
/// call and type edges, so code that the seeds use or that uses the seeds rises,
/// and an isolated text match falls.
public enum GraphRanker {
    /// An undirected, weighted connection between two symbols.
    public struct Link: Sendable, Equatable {
        public let source: String
        public let target: String
        public let weight: Double
        /// Line of the reference in the source file, when known.
        public let line: Int?

        public init(source: String, target: String, weight: Double, line: Int? = nil) {
            self.source = source
            self.target = target
            self.weight = weight
            self.line = line
        }
    }

    /// Personalized PageRank (random walk with restart) from weighted seeds.
    ///
    /// - Parameters:
    ///   - seeds: Restart weights per symbol id. Values need not sum to one.
    ///   - links: Graph connections, used in both directions.
    ///   - restart: Probability of a jump back to the seeds at each step.
    ///   - iterations: Number of power iterations.
    /// - Returns: Scores that sum to one, keyed by symbol id.
    public static func personalizedPageRank(
        seeds: [String: Double],
        links: [Link],
        restart: Double = 0.25,
        iterations: Int = 25
    ) -> [String: Double] {
        let seedTotal = seeds.values.filter { $0 > 0 }.reduce(0, +)
        guard seedTotal > 0 else { return [:] }
        let restartVector = seeds.filter { $0.value > 0 }.mapValues { $0 / seedTotal }

        var adjacency: [String: [(String, Double)]] = [:]
        for link in links where link.source != link.target && link.weight > 0 {
            adjacency[link.source, default: []].append((link.target, link.weight))
            adjacency[link.target, default: []].append((link.source, link.weight))
        }
        let outWeight = adjacency.mapValues { $0.reduce(0) { $0 + $1.1 } }

        var rank = restartVector
        for _ in 0 ..< iterations {
            var next = restartVector.mapValues { restart * $0 }
            var dangling = 0.0
            for (node, value) in rank where value > 0 {
                guard let neighbours = adjacency[node], let total = outWeight[node], total > 0 else {
                    dangling += value
                    continue
                }
                for (neighbour, weight) in neighbours {
                    next[neighbour, default: 0] += (1 - restart) * value * weight / total
                }
            }
            // A node without links returns its mass to the seeds, so scores keep summing to one.
            for (seed, share) in restartVector {
                next[seed, default: 0] += (1 - restart) * dangling * share
            }
            rank = next
        }
        return rank
    }

    /// Relative value of showing a symbol of this kind to an agent.
    public static func kindWeight(_ kind: SymbolKind) -> Double {
        switch kind {
        case .function, .method, .initializer, .type, .protocolDecl, .subscriptDecl, .operatorDecl:
            1.0
        case .property:
            0.5
        case .enumCase, .typealiasDecl:
            0.3
        }
    }

    /// Down-weights tests and generated code, which rarely answer "how does X work".
    public static func pathPenalty(_ path: String) -> Double {
        let generated = path.contains("/Generated/") || path.hasSuffix(".pb.swift") || path.contains(".generated.")
        return generated || AffectedAnalyzer.isTestPath(path) ? 0.5 : 1.0
    }

    /// Keeps files that score at least `ratio` of the best file, best first.
    public static func cutoff(_ scores: [String: Double], ratio: Double = 0.35, limit: Int) -> [(String, Double)] {
        let sorted = scores.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        guard let best = sorted.first?.value, best > 0 else { return [] }
        return Array(sorted.prefix { $0.value >= best * ratio }.prefix(limit))
    }
}
