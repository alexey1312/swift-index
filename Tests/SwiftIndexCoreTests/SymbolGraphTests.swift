import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("Symbol Graph Tests")
struct SymbolGraphTests {
    // MARK: - Fixtures

    private static let storeSource = """
    protocol ChunkStore {
        func search(query: String) -> [String]
    }

    struct SQLiteStore: ChunkStore {
        func search(query: String) -> [String] { [query] }
    }

    struct MemoryStore: ChunkStore {
        func search(query: String) -> [String] { [] }
    }
    """

    private static let engineSource = """
    struct SearchEngine {
        private let store: any ChunkStore

        func run(_ text: String) -> [String] {
            return store.search(query: text)
        }

        func runTwice(_ text: String) -> [String] {
            return run(text) + run(text)
        }
    }
    """

    private func buildGraph() async throws -> GRDBChunkStore {
        let store = try GRDBChunkStore()
        let builder = GraphBuilder(chunkStore: store)

        for (path, source) in [
            ("/p/Sources/App/Store.swift", Self.storeSource),
            ("/p/Sources/App/Engine.swift", Self.engineSource),
        ] {
            let facts = SwiftGraphFactsExtractor.extract(
                content: source,
                path: path,
                fileHash: FileHasher.hash(source),
                module: "App"
            )
            try await builder.record(facts: facts, chunks: [])
        }

        try await builder.resolve()
        return store
    }

    // MARK: - Extraction

    @Test("Declarations become symbols with the right shape")
    func symbolExtraction() async throws {
        let store = try await buildGraph()
        let symbols = try await store.allSymbols()

        let names = Set(symbols.map(\.name))
        #expect(names.contains("ChunkStore"))
        #expect(names.contains("SearchEngine"))
        #expect(names.contains("run"))

        // A protocol member must be marked as a requirement, or witness fanout — the
        // whole reason for the graph — cannot trigger.
        let requirement = symbols.first { $0.name == "search" && $0.container == "ChunkStore" }
        #expect(requirement?.isRequirement == true)

        let implementation = symbols.first { $0.name == "search" && $0.container == "SQLiteStore" }
        #expect(implementation?.isRequirement == false)
    }

    @Test("Symbol identity ignores line numbers")
    func symbolIDIsPositionIndependent() {
        // Edges point at symbol ids. If ids moved with line numbers, inserting a blank
        // line at the top of a file would invalidate every edge into it.
        let first = SymbolNode.makeID(SymbolNode.Identity(
            path: "/p/A.swift", container: "Foo", name: "bar",
            kind: .method, argumentLabels: "x", isStatic: false
        ))
        let second = SymbolNode.makeID(SymbolNode.Identity(
            path: "/p/A.swift", container: "Foo", name: "bar",
            kind: .method, argumentLabels: "x", isStatic: false
        ))
        #expect(first == second)

        // Overloads must stay distinct.
        let overload = SymbolNode.makeID(SymbolNode.Identity(
            path: "/p/A.swift", container: "Foo", name: "bar",
            kind: .method, argumentLabels: "y", isStatic: false
        ))
        #expect(first != overload)
    }

    // MARK: - Resolution

    @Test("A self call resolves with high confidence")
    func selfCallResolution() async throws {
        let store = try await buildGraph()
        let symbols = try await store.allSymbols()
        let runTwice = try #require(symbols.first { $0.name == "runTwice" })

        let edges = try await store.outgoingEdges(from: runTwice.id, minConfidence: 0)
        let call = try #require(edges.first { $0.targetName == "run" && $0.kind == .calls })

        #expect(call.synthesizedBy == "self-container")
        #expect(call.confidence >= 0.9)
        // Two call sites collapse into one edge with a count.
        #expect(call.occurrences == 2)
    }

    @Test("A call through a typed property resolves to the declared type")
    func receiverVarTypeResolution() async throws {
        let store = try await buildGraph()
        let symbols = try await store.allSymbols()
        let run = try #require(symbols.first { $0.name == "run" })

        let edges = try await store.outgoingEdges(from: run.id, minConfidence: 0)
        let call = try #require(
            edges.first { $0.targetName == "search" && $0.synthesizedBy == "receiver-var-type" }
        )

        // `private let store: any ChunkStore` types the receiver from pure syntax —
        // no type checker required.
        #expect(call.confidence >= 0.8)
    }

    @Test("Calls to a protocol requirement fan out to conformers")
    func protocolWitnessFanout() async throws {
        let store = try await buildGraph()
        let symbols = try await store.allSymbols()
        let run = try #require(symbols.first { $0.name == "run" })

        let edges = try await store.outgoingEdges(from: run.id, minConfidence: 0)
        let witnesses = edges.filter { $0.synthesizedBy == "protocol-witness" }

        // This is the hop text search cannot follow: a call to the requirement should
        // surface the concrete implementations that will actually run.
        #expect(witnesses.count == 2)

        var targetContainers: Set<String> = []
        for witness in witnesses {
            if let id = witness.targetID, let symbol = try await store.symbol(id: id) {
                targetContainers.insert(symbol.container ?? "")
            }
        }
        #expect(targetContainers == ["SQLiteStore", "MemoryStore"])

        // Guesses must be labelled as such.
        #expect(witnesses.allSatisfy { $0.provenance == .heuristic })
        #expect(witnesses.allSatisfy { $0.confidence < 0.8 })
    }

    @Test("Conformance declared in an extension still fans out")
    func extensionConformanceFanout() async throws {
        // `extension Foo: Bar` is the most common conformance idiom in Swift. An
        // extension is always at file scope, so attributing it to the previously
        // parsed symbol credited an unrelated declaration and left witness fanout
        // with nothing to fan out to.
        let source = """
        protocol Handler {
            func handle() -> Int
        }

        struct FileHandler {}

        extension FileHandler: Handler {
            func handle() -> Int { 1 }
        }

        struct Caller {
            private let handler: any Handler
            func run() -> Int { handler.handle() }
        }
        """

        let store = try GRDBChunkStore()
        let builder = GraphBuilder(chunkStore: store)
        let facts = SwiftGraphFactsExtractor.extract(
            content: source,
            path: "/p/Sources/App/Handler.swift",
            fileHash: FileHasher.hash(source),
            module: "App"
        )
        try await builder.record(facts: facts, chunks: [])
        try await builder.resolve()

        let pairs = try await store.conformancePairs()
        #expect(
            pairs.contains { $0.type == "FileHandler" && $0.protocolName == "Handler" },
            "extension conformance must be attributed to the extended type, got \(pairs)"
        )

        let symbols = try await store.allSymbols()
        let run = try #require(symbols.first { $0.name == "run" })
        let edges = try await store.outgoingEdges(from: run.id, minConfidence: 0)
        let witnesses = edges.filter { $0.synthesizedBy == "protocol-witness" }
        #expect(!witnesses.isEmpty, "witness fanout should reach FileHandler.handle")
    }

    @Test("Standard protocols do not fan out")
    func standardProtocolsExcluded() {
        // A call to == must not produce an edge to every Equatable type in the project.
        #expect(SymbolResolver.standardProtocols.contains("Equatable"))
        #expect(SymbolResolver.standardProtocols.contains("Codable"))
        #expect(!SymbolResolver.standardProtocols.contains("ChunkStore"))
    }

    @Test("A typed receiver wins over a same-file symbol of the same name")
    func receiverBeatsSameFile() async throws {
        // Proximity is not evidence about which type a call lands on. Ordering
        // same-file first made `beta.handle()` resolve to a neighbouring Alpha.handle.
        let source = """
        struct Alpha {
            func handle() -> Int { 1 }
        }

        struct Beta {
            func handle() -> Int { 2 }
        }

        struct Caller {
            private let beta: Beta
            func run() -> Int { beta.handle() }
        }
        """

        let store = try GRDBChunkStore()
        let builder = GraphBuilder(chunkStore: store)
        let facts = SwiftGraphFactsExtractor.extract(
            content: source,
            path: "/p/Sources/App/Mixed.swift",
            fileHash: FileHasher.hash(source),
            module: "App"
        )
        try await builder.record(facts: facts, chunks: [])
        try await builder.resolve()

        let symbols = try await store.allSymbols()
        let run = try #require(symbols.first { $0.name == "run" })
        let edges = try await store.outgoingEdges(from: run.id, minConfidence: 0)
        let call = try #require(edges.first { $0.targetName == "handle" && $0.kind == .calls })
        let target = try #require(call.targetID.flatMap { id in symbols.first { $0.id == id } })

        #expect(target.container == "Beta", "resolved to \(target.container ?? "nil")")
    }

    @Test("Module inference does not report layout directories as modules")
    func moduleInference() {
        let root = "/p"
        #expect(GraphBuilder.inferModule(path: "/p/Sources/App/A.swift", projectRoot: root) == "App")
        // `Sources/A.swift` has no target directory, so there is no module to name.
        #expect(GraphBuilder.inferModule(path: "/p/Sources/A.swift", projectRoot: root) == nil)
        #expect(GraphBuilder.inferModule(path: "/p/Tests/AppTests/T.swift", projectRoot: root) == "AppTests")
    }

    @Test("An empty symbol query matches nothing")
    func emptyQueryMatchesNothing() async throws {
        let store = try await buildGraph()
        // Without a guard this became LIKE '%' and returned the whole table.
        let matches = try await store.findSymbols(matching: "  ", limit: 50)
        #expect(matches.isEmpty)
    }

    // MARK: - Queries

    @Test("Callers traversal finds transitive callers")
    func callersQuery() async throws {
        let store = try await buildGraph()
        let engine = GraphQueryEngine(chunkStore: store)

        let matches = try await engine.resolveSymbols(query: "ChunkStore.search", limit: 1)
        let root = try #require(matches.first)

        let result = try await engine.query(symbol: root, relation: .callers, depth: 2)
        let names = Set(result.nodes.map(\.symbol.qualifiedName))

        #expect(names.contains("SearchEngine.run"))
        // runTwice reaches search only through run, so depth 2 is required.
        #expect(names.contains("SearchEngine.runTwice"))
    }

    @Test("Callees traversal follows outgoing calls")
    func calleesQuery() async throws {
        let store = try await buildGraph()
        let engine = GraphQueryEngine(chunkStore: store)

        let root = try #require(
            try await engine.resolveSymbols(query: "runTwice", limit: 1).first
        )
        let result = try await engine.query(symbol: root, relation: .callees, depth: 2)
        let names = Set(result.nodes.map(\.symbol.qualifiedName))

        #expect(names.contains("SearchEngine.run"))
        #expect(names.contains("ChunkStore.search"))
    }

    @Test("Path finding connects two symbols")
    func pathQuery() async throws {
        let store = try await buildGraph()
        let engine = GraphQueryEngine(chunkStore: store)

        let source = try #require(try await engine.resolveSymbols(query: "runTwice", limit: 1).first)
        let target = try #require(
            try await engine.resolveSymbols(query: "ChunkStore.search", limit: 1).first
        )

        let result = try await engine.query(
            symbol: source, relation: .paths, depth: 4, target: target
        )

        #expect(!result.paths.isEmpty)
        let shortest = try #require(result.paths.min { $0.symbolIDs.count < $1.symbolIDs.count })
        #expect(shortest.symbolIDs.first == source.id)
        #expect(shortest.symbolIDs.last == target.id)
    }

    // MARK: - Output

    @Test("TOON output interns symbols and records provenance")
    func tOONFormatting() async throws {
        let store = try await buildGraph()
        let engine = GraphQueryEngine(chunkStore: store)
        let root = try #require(try await engine.resolveSymbols(query: "run", limit: 1).first)
        let result = try await engine.query(symbol: root, relation: .callees, depth: 2)

        let output = GraphTOONFormatter.format(result)

        #expect(output.contains("syms["))
        #expect(output.contains("edges["))
        // Heuristic edges must be visibly marked, never presented as fact.
        #expect(output.contains("heu"))
        #expect(output.contains("protocol-witness"))
    }

    // MARK: - Incremental behaviour

    @Test("Re-recording a file replaces its edges rather than duplicating them")
    func reRecordIsIdempotent() async throws {
        let store = try GRDBChunkStore()
        let builder = GraphBuilder(chunkStore: store)
        let path = "/p/Sources/App/Engine.swift"

        func record() async throws {
            let facts = SwiftGraphFactsExtractor.extract(
                content: Self.engineSource,
                path: path,
                fileHash: FileHasher.hash(Self.engineSource),
                module: "App"
            )
            try await builder.record(facts: facts, chunks: [])
        }

        try await record()
        let first = try await store.graphStatistics()
        try await record()
        let second = try await store.graphStatistics()

        #expect(first.symbols == second.symbols)
        #expect(first.edges == second.edges)
    }
}
