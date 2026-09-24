// MARK: - ExploreEngine

import Foundation

/// Answers "how does X work" with the relevant source in one call.
///
/// Search finds seeds, the symbol graph ranks the code around them, and the
/// renderer returns line-numbered source for the best files together with the call
/// path between the top seeds and the blast radius of the top symbol. One answer
/// replaces the usual chain of search, read and grep calls.
public actor ExploreEngine {
    static let seedLimit = 30
    static let hops = 2
    static let maxNodes = 400
    static let minConfidence = 0.3
    /// Seeds that the graph does not connect to anything score lower: a text match
    /// with no structural support is often noise.
    static let isolatedSeedFactor = 0.6
    static let rankedKinds: [EdgeKind] = [.calls, .references, .inherits, .conforms, .overrides, .initializes]

    private let store: GRDBChunkStore
    private let seedSearch: any SearchEngine
    private let graphConfig: GraphConfig
    private let renderer: ExploreRenderer

    /// - Parameters:
    ///   - store: Index store with chunks and the symbol graph.
    ///   - seedSearch: Search that finds the seeds. Hybrid search in normal use,
    ///     BM25 alone where no embedding model can load.
    ///   - graphConfig: Graph settings.
    ///   - renderer: Output renderer.
    public init(
        store: GRDBChunkStore,
        seedSearch: any SearchEngine,
        graphConfig: GraphConfig = GraphConfig(),
        renderer: ExploreRenderer = ExploreRenderer()
    ) {
        self.store = store
        self.seedSearch = seedSearch
        self.graphConfig = graphConfig
        self.renderer = renderer
    }

    public func explore(query: String, options: ExploreOptions = ExploreOptions()) async throws -> ExploreResult {
        let plan = try await plan(query: query, options: options)
        return ExploreResult(text: renderer.render(plan, options: options), plan: plan)
    }

    /// Selects and ranks files without rendering them.
    public func plan(query: String, options: ExploreOptions) async throws -> ExplorePlan {
        var tier = options.budget
        if tier == nil {
            tier = try await ExploreBudget.forIndex(fileCount: store.indexedFileCount())
        }
        let limits = tier ?? ExploreBudget.forIndex(fileCount: 0)
        let budget = ExploreBudget(
            characters: limits.characters,
            files: min(options.maxFiles ?? limits.files, limits.files)
        )

        let seeds = try await collectSeeds(query: query)
        let subgraph = graphConfig.enabled ? try await expand(from: Array(seeds.symbols.keys)) : []
        let ranks = GraphRanker.personalizedPageRank(seeds: seeds.symbols, links: subgraph)
        let symbols = try await store.symbols(ids: Array(ranks.keys))

        let linked = Set(subgraph.flatMap { [$0.source, $0.target] })
        let symbolMass = seeds.symbols.values.reduce(0, +)
        let totalMass = symbolMass + seeds.files.values.reduce(0, +)
        let scale = totalMass > 0 ? symbolMass / totalMass : 0

        var symbolScores: [String: (SymbolNode, Double)] = [:]
        var fileScores: [String: Double] = [:]
        for symbol in symbols {
            var score = (ranks[symbol.id] ?? 0) * scale
            score *= GraphRanker.kindWeight(symbol.kind) * GraphRanker.pathPenalty(symbol.path)
            if !linked.contains(symbol.id) {
                score *= Self.isolatedSeedFactor
            }
            symbolScores[symbol.id] = (symbol, score)
            fileScores[symbol.path, default: 0] += score
        }
        for (path, mass) in seeds.files where totalMass > 0 {
            fileScores[path, default: 0] += mass / totalMass * GraphRanker.pathPenalty(path)
        }

        let topSeeds = seeds.symbols.keys
            .compactMap { symbolScores[$0] }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        let spine = try await spinePath(topSeeds)
        let spineFiles = Set(spine.map(\.path))

        var selected: [ExploreFile] = []
        for (path, score) in GraphRanker.cutoff(fileScores, limit: budget.files) {
            let ranked = symbolScores.values
                .filter { $0.0.path == path && $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .map { (symbol: $0.0, score: $0.1) }
            try await selected.append(ExploreFile(
                path: path,
                score: score,
                onSpine: spineFiles.contains(path),
                symbols: ranked,
                chunkRanges: seeds.chunkRanges[path] ?? [],
                declarations: store.symbols(inPath: path)
            ))
        }

        var impact: ExploreImpact?
        if graphConfig.enabled, let top = topSeeds.first {
            impact = try await self.impact(of: top)
        }
        return ExplorePlan(
            query: query,
            files: selected,
            spine: spine.map(\.qualifiedName),
            impact: impact,
            callSites: callSites(subgraph),
            budget: budget
        )
    }

    // MARK: - Seeds

    struct Seeds {
        var symbols: [String: Double] = [:]
        /// Weight of matched chunks that have no graph symbol, keyed by path.
        var files: [String: Double] = [:]
        var chunkRanges: [String: [ClosedRange<Int>]] = [:]
    }

    private func collectSeeds(query: String) async throws -> Seeds {
        var seeds = Seeds()
        let results = try await seedSearch.search(query: query, options: SearchOptions(limit: Self.seedLimit))

        for (rank, result) in results.enumerated() {
            let chunk = result.chunk
            let weight = 1.0 / Double(rank + 1)
            let matched = try await store.symbols(inPath: chunk.path)
                .filter { $0.startLine >= chunk.startLine && $0.startLine <= chunk.endLine }
            if matched.isEmpty {
                seeds.files[chunk.path, default: 0] += weight
                let range = chunk.startLine ... max(chunk.startLine, chunk.endLine)
                seeds.chunkRanges[chunk.path, default: []].append(range)
            } else {
                // The outermost symbol carries the weight: the chunk is its body.
                let outer = matched.min { lhs, rhs in
                    lhs.startLine == rhs.startLine ? lhs.endLine > rhs.endLine : lhs.startLine < rhs.startLine
                }
                if let outer {
                    seeds.symbols[outer.id, default: 0] += weight
                }
            }
        }

        // A symbol named in the query is the strongest possible seed.
        for token in Self.identifierTokens(in: query) {
            for symbol in try await store.findSymbols(matching: token, limit: 3) {
                seeds.symbols[symbol.id, default: 0] += 1
            }
        }
        return seeds
    }

    /// Words in a query that look like code identifiers rather than prose.
    public static func identifierTokens(in query: String) -> [String] {
        let separators = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.")).inverted
        return query.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { token in
                guard token.count >= 3 else { return false }
                return token.contains("_") || token.contains(".") || BM25Search.isCamelCaseIdentifier(token)
                    || token.first?.isUppercase == true
            }
    }

    // MARK: - Graph

    private func expand(from seedIDs: [String]) async throws -> [GraphRanker.Link] {
        var nodes = Set(seedIDs)
        var frontier = seedIDs
        var links: [GraphRanker.Link] = []
        var seen = Set<String>()

        for _ in 0 ..< Self.hops where !frontier.isEmpty {
            var edges = try await store.neighbours(
                of: frontier, incoming: false, kinds: Self.rankedKinds, minConfidence: Self.minConfidence
            )
            edges += try await store.neighbours(
                of: frontier, incoming: true, kinds: Self.rankedKinds, minConfidence: Self.minConfidence
            )
            frontier = []
            for edge in edges {
                guard let target = edge.targetID,
                      seen.insert("\(edge.sourceID)>\(target)>\(edge.kind.rawValue)").inserted
                else {
                    continue
                }
                links.append(GraphRanker.Link(
                    source: edge.sourceID, target: target, weight: edge.confidence, line: edge.firstLine
                ))
                for id in [edge.sourceID, target] where nodes.count < Self.maxNodes && nodes.insert(id).inserted {
                    frontier.append(id)
                }
            }
        }
        return links
    }

    private func callSites(_ links: [GraphRanker.Link]) -> [String: [Int]] {
        var sites: [String: [Int]] = [:]
        for link in links {
            if let line = link.line {
                sites[link.source, default: []].append(line)
            }
        }
        return sites
    }

    /// The call path between the two best seeds, in either direction.
    private func spinePath(_ topSeeds: [SymbolNode]) async throws -> [SymbolNode] {
        guard graphConfig.enabled, topSeeds.count >= 2 else { return [] }
        let engine = GraphQueryEngine(chunkStore: store, config: graphConfig, maxNodes: 200)
        let first = topSeeds[0]
        let second = topSeeds[1]
        for (from, to) in [(first, second), (second, first)] {
            let result = try await engine.query(symbol: from, relation: .paths, depth: 4, target: to, limit: 50)
            if let path = result.paths.first {
                let known = result.nodes.map(\.symbol) + [from, to]
                let byID = Dictionary(known.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                return path.symbolIDs.compactMap { byID[$0] }
            }
        }
        return []
    }

    private func impact(of symbol: SymbolNode) async throws -> ExploreImpact {
        let engine = GraphQueryEngine(chunkStore: store, config: graphConfig, maxNodes: 300)
        let result = try await engine.query(symbol: symbol, relation: .impact, depth: 2, limit: 300)
        let files = Set(result.nodes.map(\.symbol.path))
        return ExploreImpact(
            symbolName: symbol.qualifiedName,
            symbols: result.nodes.count,
            files: files.count,
            tests: files.filter(AffectedAnalyzer.isTestPath).count
        )
    }
}
