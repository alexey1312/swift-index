import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("Explore Tests")
struct ExploreTests {
    // MARK: - GraphRanker

    @Test("A node linked to the seed outranks an unlinked node and scores sum to one")
    func pageRankFavoursLinkedNodes() {
        let links = [
            GraphRanker.Link(source: "seed", target: "hub", weight: 1),
            GraphRanker.Link(source: "hub", target: "far", weight: 1),
            GraphRanker.Link(source: "other", target: "far", weight: 1),
        ]

        let ranks = GraphRanker.personalizedPageRank(seeds: ["seed": 1], links: links)

        #expect((ranks["hub"] ?? 0) > (ranks["far"] ?? 0))
        #expect((ranks["far"] ?? 0) > (ranks["other"] ?? 0))
        #expect(abs(ranks.values.reduce(0, +) - 1) < 1e-9)
    }

    @Test("Cutoff keeps files near the best score, in order")
    func cutoffIsRelative() {
        let kept = GraphRanker.cutoff(["a": 1.0, "b": 0.5, "c": 0.2], limit: 5)
        #expect(kept.map(\.0) == ["a", "b"])
        #expect(GraphRanker.cutoff(["a": 1.0, "b": 0.9], limit: 1).map(\.0) == ["a"])
    }

    @Test("Identifier tokens skip plain prose words")
    func identifierTokens() {
        let tokens = ExploreEngine.identifierTokens(in: "how does IndexManager.save call chunk_store and flush")
        #expect(tokens.contains("IndexManager.save"))
        #expect(tokens.contains("chunk_store"))
        #expect(!tokens.contains("flush"))
        #expect(!tokens.contains("how"))
    }

    // MARK: - Renderer

    private static let source = (1 ... 200).map { "let line\($0) = \($0)" }.joined(separator: "\n")

    private func symbol(
        _ name: String,
        path: String,
        lines: ClosedRange<Int>,
        kind: SymbolKind = .function
    ) -> SymbolNode {
        SymbolNode(
            id: name, name: name, qualifiedName: name, container: nil, module: nil, kind: kind,
            argumentLabels: nil, arity: 0, isStatic: false, isRequirement: false, isOverride: false,
            access: nil, path: path, startLine: lines.lowerBound, endLine: lines.upperBound,
            chunkID: nil, fileHash: FileHasher.hash(Self.source)
        )
    }

    private func plan(files: [ExploreFile], characters: Int) -> ExplorePlan {
        ExplorePlan(
            query: "q",
            files: files,
            spine: ["a", "b"],
            impact: ExploreImpact(symbolName: "a", symbols: 3, files: 2, tests: 1),
            callSites: [:],
            budget: ExploreBudget(characters: characters, files: 8)
        )
    }

    private func file(_ path: String, symbol: SymbolNode, onSpine: Bool) -> ExploreFile {
        ExploreFile(
            path: path, score: 1, onSpine: onSpine, symbols: [(symbol, 1)], chunkRanges: [], declarations: [symbol]
        )
    }

    @Test("Output uses Read-style numbered lines, a call path and a blast radius")
    func renderShape() {
        let renderer = ExploreRenderer { _ in Self.source }
        let target = symbol("a", path: "/p/A.swift", lines: 10 ... 12)

        let text = renderer.render(
            plan(files: [file("/p/A.swift", symbol: target, onSpine: true)], characters: 5000),
            options: ExploreOptions(projectRoot: "/p")
        )

        #expect(text.contains("## A.swift"))
        #expect(text.contains("10\tlet line10 = 10"))
        #expect(text.contains("12\tlet line12 = 12"))
        #expect(!text.contains("13\tlet line13"))
        #expect(text.contains("call path: a → b"))
        #expect(text.contains("blast radius of a: 3 symbols in 2 files, 1 test files"))
    }

    @Test("Output stays within the character budget and gives spine files more room")
    func budgetAndSpine() {
        let renderer = ExploreRenderer { _ in Self.source }
        let spine = file("/p/Spine.swift", symbol: symbol("s", path: "/p/Spine.swift", lines: 1 ... 55), onSpine: true)
        let other = file("/p/Other.swift", symbol: symbol("o", path: "/p/Other.swift", lines: 1 ... 55), onSpine: false)

        let text = renderer.render(plan(files: [spine, other], characters: 1500), options: ExploreOptions())

        #expect(text.count <= 1500)
        let parts = text.components(separatedBy: "## /p/Other.swift")
        let spineLines = parts[0].components(separatedBy: "\n").filter { $0.contains("\tlet ") }.count
        let otherLines = parts[1].components(separatedBy: "\n").filter { $0.contains("\tlet ") }.count
        #expect(spineLines > otherLines)
        #expect(otherLines > 0)
    }

    @Test("A file changed since indexing gets a warning banner")
    func staleBanner() {
        let renderer = ExploreRenderer { _ in Self.source + "\nlet added = 1" }
        let target = symbol("a", path: "/p/A.swift", lines: 1 ... 2)

        let text = renderer.render(
            plan(files: [file("/p/A.swift", symbol: target, onSpine: false)], characters: 4000),
            options: ExploreOptions()
        )

        #expect(text.contains("changed since indexing"))
    }

    @Test("Budget tiers grow with the project and never pass the hard cap")
    func budgetTiers() {
        #expect(ExploreBudget.forIndex(fileCount: 50).files == 4)
        #expect(ExploreBudget.forIndex(fileCount: 500).files == 6)
        #expect(ExploreBudget.forIndex(fileCount: 5000).characters <= ExploreBudget.hardCap)
        #expect(ExploreBudget(characters: 99999, files: 1).characters == ExploreBudget.hardCap)
    }

    // MARK: - Engine

    private struct StubSearch: SearchEngine {
        let results: [SearchResult]
        func search(query _: String, options _: SearchOptions) async throws -> [SearchResult] {
            results
        }
    }

    @Test("Explore follows graph edges from the seed to the code it calls")
    func engineFollowsGraph() async throws {
        let caller = "struct Engine {\n    func run() {\n        Store().save()\n    }\n}"
        let callee = "struct Store {\n    func save() {}\n}"
        let unrelated = "struct Noise {\n    func other() {}\n}"
        let files = [
            "/p/Sources/App/Engine.swift": caller,
            "/p/Sources/App/Store.swift": callee,
            "/p/Sources/App/Noise.swift": unrelated,
        ]

        let store = try GRDBChunkStore()
        let builder = GraphBuilder(chunkStore: store)
        for (path, content) in files {
            try await builder.recordFile(
                path: path, content: content, fileHash: FileHasher.hash(content), chunks: [], projectRoot: "/p"
            )
        }
        try await builder.resolve()

        let seed = CodeChunk(
            path: "/p/Sources/App/Engine.swift", content: caller, startLine: 2, endLine: 4, kind: .method,
            fileHash: FileHasher.hash(caller)
        )
        let engine = ExploreEngine(
            store: store,
            seedSearch: StubSearch(results: [SearchResult(chunk: seed, score: 1)]),
            renderer: ExploreRenderer { files[$0] }
        )

        let result = try await engine.explore(query: "run", options: ExploreOptions(projectRoot: "/p"))

        let paths = result.plan.files.map(\.path)
        #expect(paths.contains("/p/Sources/App/Engine.swift"))
        #expect(paths.contains("/p/Sources/App/Store.swift"))
        #expect(!paths.contains("/p/Sources/App/Noise.swift"))
        #expect(result.text.contains("2\tfunc save() {}") || result.text.contains("2\t    func save() {}"))
    }
}
