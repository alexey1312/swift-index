// MARK: - GraphQueryEngine

import Foundation
import Logging

/// Which relationship to explore.
public enum GraphRelation: String, Sendable, CaseIterable {
    case callers
    case callees
    case impact
    case paths
    case neighborhood
}

/// A symbol plus how far it sits from the query root.
public struct GraphNode: Sendable, Equatable {
    public let symbol: SymbolNode
    public let depth: Int
}

/// A chain of symbols connected by edges.
public struct CallPath: Sendable, Equatable {
    public let symbolIDs: [String]
    /// Product of the edge confidences along the path.
    public let confidence: Double
}

/// The result of a graph query.
public struct GraphNeighborhood: Sendable {
    public let root: SymbolNode
    public let relation: GraphRelation
    public let depth: Int
    public let nodes: [GraphNode]
    public let edges: [GraphEdge]
    public let paths: [CallPath]
    /// Edges whose target could not be resolved, so callers know the traversal is
    /// incomplete rather than assuming it ended.
    public let unresolvedCount: Int
    /// Whether the node budget stopped the traversal early.
    public let truncated: Bool

    public var fileCount: Int {
        Set(nodes.map(\.symbol.path)).count
    }

    public var moduleCount: Int {
        Set(nodes.compactMap(\.symbol.module)).count
    }

    public var publicAPICount: Int {
        nodes.filter { $0.symbol.access == "public" }.count
    }
}

/// Answers structural questions about the symbol graph.
public actor GraphQueryEngine {
    private let chunkStore: GRDBChunkStore
    private let config: GraphConfig
    private let logger: Logger

    /// Hard cap on nodes visited, so a high-fan-in symbol cannot explode a query.
    private let maxNodes: Int

    public init(
        chunkStore: GRDBChunkStore,
        config: GraphConfig = GraphConfig(),
        maxNodes: Int = 500,
        logger: Logger = Logger(label: "GraphQueryEngine")
    ) {
        self.chunkStore = chunkStore
        self.config = config
        self.maxNodes = maxNodes
        self.logger = logger
    }

    /// Finds symbols matching a name, qualified name, or `path:line`.
    public func resolveSymbols(query: String, limit: Int = 10) async throws -> [SymbolNode] {
        try await chunkStore.findSymbols(matching: query, limit: limit)
    }

    /// Runs a relation query rooted at a symbol.
    public func query(
        symbol: SymbolNode,
        relation: GraphRelation,
        depth: Int,
        minConfidence: Double? = nil,
        target: SymbolNode? = nil,
        limit: Int = 40
    ) async throws -> GraphNeighborhood {
        let threshold = minConfidence ?? config.minConfidence

        switch relation {
        case .callers:
            return try await traverse(TraversalSpec(
                root: symbol,
                relation: relation,
                incoming: true,
                kinds: [.calls, .initializes, .overrides],
                depth: depth,
                minConfidence: threshold,
                limit: limit
            ))

        case .callees:
            return try await traverse(TraversalSpec(
                root: symbol,
                relation: relation,
                incoming: false,
                kinds: [.calls, .initializes],
                depth: depth,
                minConfidence: threshold,
                limit: limit
            ))

        case .impact:
            // Blast radius: everything that could break, so overrides and conformances
            // count as dependents too.
            return try await traverse(TraversalSpec(
                root: symbol,
                relation: relation,
                incoming: true,
                kinds: [.calls, .initializes, .overrides, .conforms, .references],
                depth: depth,
                minConfidence: threshold,
                limit: limit
            ))

        case .neighborhood:
            let outgoing = try await traverse(TraversalSpec(
                root: symbol,
                relation: relation,
                incoming: false,
                kinds: [.calls, .initializes, .references],
                depth: depth,
                minConfidence: threshold,
                limit: limit
            ))
            let incoming = try await traverse(TraversalSpec(
                root: symbol,
                relation: relation,
                incoming: true,
                kinds: [.calls, .initializes],
                depth: depth,
                minConfidence: threshold,
                limit: limit
            ))
            return merge(outgoing, incoming, root: symbol, relation: relation, depth: depth)

        case .paths:
            guard let target else {
                return GraphNeighborhood(
                    root: symbol, relation: relation, depth: depth,
                    nodes: [], edges: [], paths: [],
                    unresolvedCount: 0, truncated: false
                )
            }
            return try await findPaths(
                from: symbol,
                to: target,
                maxDepth: depth,
                minConfidence: threshold
            )
        }
    }

    // MARK: - Traversal

    /// Breadth-first traversal with a node budget.
    ///
    /// Done level by level in Swift rather than as a recursive CTE so the budget can
    /// be enforced *before* a high-fan-in symbol expands, and so confidence decays
    /// with distance.
    private struct TraversalSpec {
        let root: SymbolNode
        let relation: GraphRelation
        let incoming: Bool
        let kinds: [EdgeKind]
        let depth: Int
        let minConfidence: Double
        let limit: Int
    }

    private func traverse(_ spec: TraversalSpec) async throws -> GraphNeighborhood {
        let root = spec.root
        let incoming = spec.incoming
        let kinds = spec.kinds
        let depth = spec.depth
        let minConfidence = spec.minConfidence
        let limit = spec.limit
        let relation = spec.relation
        var visited: Set<String> = [root.id]
        var nodes: [GraphNode] = []
        var collectedEdges: [GraphEdge] = []
        var frontier = [root.id]
        var truncated = false
        var unresolved = 0

        for level in 1 ... max(1, depth) {
            guard !frontier.isEmpty else { break }

            let edges = try await chunkStore.neighbours(
                of: frontier,
                incoming: incoming,
                kinds: kinds,
                minConfidence: minConfidence
            )
            collectedEdges.append(contentsOf: edges)

            // Count the edges that lead nowhere, so callers can tell a genuine
            // boundary from a traversal that simply could not follow further.
            if !incoming {
                unresolved += try await chunkStore.unresolvedNeighbourCount(
                    of: frontier,
                    kinds: kinds
                )
            }

            var nextFrontier: [String] = []
            for edge in edges {
                guard let neighbourID = incoming ? edge.sourceID as String? : edge.targetID else {
                    continue
                }
                guard !visited.contains(neighbourID) else { continue }

                if visited.count >= maxNodes {
                    truncated = true
                    break
                }

                visited.insert(neighbourID)
                nextFrontier.append(neighbourID)

                if let symbol = try await chunkStore.symbol(id: neighbourID) {
                    nodes.append(GraphNode(symbol: symbol, depth: level))
                }
            }

            if truncated {
                break
            }
            frontier = nextFrontier
        }

        // Rank by proximity first, then by how heavily referenced a symbol is —
        // a free, ML-free importance signal.
        let ranked = nodes
            .sorted { ($0.depth, -$0.symbol.inDegree) < ($1.depth, -$1.symbol.inDegree) }
            .prefix(limit)

        return GraphNeighborhood(
            root: root,
            relation: relation,
            depth: depth,
            nodes: Array(ranked),
            edges: collectedEdges,
            paths: [],
            unresolvedCount: unresolved,
            truncated: truncated
        )
    }

    /// Finds up to `k` paths between two symbols.
    private func findPaths(
        from source: SymbolNode,
        to target: SymbolNode,
        maxDepth: Int,
        minConfidence: Double,
        k: Int = 3
    ) async throws -> GraphNeighborhood {
        var paths: [CallPath] = []
        var queue: [(chain: [String], confidence: Double)] = [([source.id], 1.0)]
        var seen: Set<String> = [source.id]

        for _ in 0 ..< max(1, maxDepth) {
            guard paths.count < k, !queue.isEmpty else { break }
            var next: [(chain: [String], confidence: Double)] = []

            for entry in queue {
                guard let tail = entry.chain.last else { continue }
                let edges = try await chunkStore.neighbours(
                    of: [tail],
                    incoming: false,
                    kinds: [.calls, .initializes, .overrides],
                    minConfidence: minConfidence
                )

                for edge in edges {
                    guard let neighbourID = edge.targetID else { continue }
                    let confidence = entry.confidence * edge.confidence

                    if neighbourID == target.id {
                        paths.append(CallPath(
                            symbolIDs: entry.chain + [neighbourID],
                            confidence: confidence
                        ))
                        continue
                    }

                    guard !seen.contains(neighbourID) else { continue }
                    seen.insert(neighbourID)
                    next.append((entry.chain + [neighbourID], confidence))
                }
            }

            if paths.count >= k {
                break
            }
            queue = next
        }

        // Exact paths surface above heuristic ones.
        let ranked = paths.sorted { $0.confidence > $1.confidence }.prefix(k)
        let nodeIDs = Set(ranked.flatMap(\.symbolIDs))
        var nodes: [GraphNode] = []
        for id in nodeIDs {
            if let symbol = try await chunkStore.symbol(id: id) {
                nodes.append(GraphNode(symbol: symbol, depth: 0))
            }
        }

        return GraphNeighborhood(
            root: source,
            relation: .paths,
            depth: maxDepth,
            nodes: nodes,
            edges: [],
            paths: Array(ranked),
            unresolvedCount: 0,
            truncated: false
        )
    }

    private func merge(
        _ first: GraphNeighborhood,
        _ second: GraphNeighborhood,
        root: SymbolNode,
        relation: GraphRelation,
        depth: Int
    ) -> GraphNeighborhood {
        var seen: Set<String> = []
        var nodes: [GraphNode] = []
        for node in first.nodes + second.nodes where seen.insert(node.symbol.id).inserted {
            nodes.append(node)
        }

        return GraphNeighborhood(
            root: root,
            relation: relation,
            depth: depth,
            nodes: nodes,
            edges: first.edges + second.edges,
            paths: [],
            unresolvedCount: first.unresolvedCount + second.unresolvedCount,
            truncated: first.truncated || second.truncated
        )
    }
}
