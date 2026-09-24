import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("Graph Completeness Tests")
struct GraphCompletenessTests {
    private func build(_ files: [(String, String)]) async throws -> GRDBChunkStore {
        let store = try GRDBChunkStore()
        let builder = GraphBuilder(chunkStore: store)
        for (path, source) in files {
            let facts = SwiftGraphFactsExtractor.extract(
                content: source,
                path: path,
                fileHash: FileHasher.hash(source),
                module: GraphBuilder.inferModule(path: path, projectRoot: "/p")
            )
            try await builder.record(facts: facts, chunks: [])
        }
        try await builder.resolve()
        return store
    }

    private func edgeCount(_ store: GRDBChunkStore, kind: EdgeKind) async throws -> Int {
        try await store.resolvedEdgePairs(kind: kind).count
    }

    private static let hierarchy = """
    protocol Drawable {
        func draw()
    }

    class Shape: Drawable {
        func draw() {}
        func area() -> Double { 0 }
    }

    class Circle: Shape {
        override func draw() {}
        override func area() -> Double { 1 }
    }
    """

    @Test("A class target becomes inherits and a protocol target stays conforms")
    func inheritanceKinds() async throws {
        let store = try await build([("/p/Sources/App/Shapes.swift", Self.hierarchy)])

        #expect(try await edgeCount(store, kind: .inherits) == 1)
        #expect(try await edgeCount(store, kind: .conforms) == 1)
    }

    @Test("Override members link to the member they override")
    func overrideEdges() async throws {
        let store = try await build([("/p/Sources/App/Shapes.swift", Self.hierarchy)])

        let pairs = try await store.resolvedEdgePairs(kind: .overrides)
        #expect(pairs.count == 2)
        for pair in pairs {
            let source = try #require(try await store.symbol(id: pair.source))
            let target = try #require(try await store.symbol(id: pair.target))
            #expect(source.container == "Circle")
            #expect(target.container == "Shape")
            #expect(source.name == target.name)
        }
    }

    @Test("Another resolver pass does not duplicate or inflate override edges")
    func overridePassIsIdempotent() async throws {
        let store = try await build([("/p/Sources/App/Shapes.swift", Self.hierarchy)])
        let before = try await store.graphStatistics()

        try await GraphBuilder(chunkStore: store).resolve()

        let after = try await store.graphStatistics()
        #expect(before.edges == after.edges)
        #expect(try await edgeCount(store, kind: .overrides) == 2)
    }

    @Test("Imports are stored per file and replaced on re-record")
    func importsPersist() async throws {
        let path = "/p/Tests/AppTests/StoreTests.swift"
        let store = try await build([(path, "import App\nimport Testing\nfunc check() {}")])
        #expect(try await store.paths(importingAnyOf: ["App"]) == [path])

        try await GraphBuilder(chunkStore: store).removeFile(path: path)
        #expect(try await store.paths(importingAnyOf: ["App"]).isEmpty)
    }

    @Test("Dead code lists unreferenced internal symbols and skips exempt ones")
    func deadCodeExemptions() async throws {
        let source = """
        struct Service {
            func used() {}
            func unused() {}
            public func api() {}
            @objc func bridged() {}
            func caller() { used() }
        }

        class Base {
            func hook() {}
        }

        class Derived: Base {
            override func hook() {}
        }

        protocol Handler {
            func handle()
        }

        struct Concrete: Handler {
            func handle() {}
        }
        """
        let store = try await build([("/p/Sources/App/Service.swift", source)])

        let names = try await Set(DeadCodeFinder.find(in: store).map(\.qualifiedName))

        #expect(names.contains("Service.unused"))
        #expect(!names.contains("Service.used"))
        #expect(!names.contains("Service.api"))
        #expect(!names.contains("Service.bridged"))
        #expect(!names.contains("Derived.hook"))
        #expect(!names.contains("Concrete.handle"))
        #expect(!names.contains("Handler.handle"))
    }

    @Test("Affected tests come from graph edges and module imports")
    func affectedTests() async throws {
        let store = try await build([
            ("/p/Sources/App/Store.swift", "struct Store {\n    func save() {}\n}"),
            ("/p/Sources/App/Other.swift", "struct Other {}"),
            ("/p/Tests/AppTests/StoreTests.swift", "func testSave() { Store().save() }"),
            ("/p/Tests/AppTests/ImportOnlyTests.swift", "import App\nfunc testNothing() {}"),
            ("/p/Tests/OtherTests/UnrelatedTests.swift", "import Other\nfunc testUnrelated() {}"),
        ])

        let tests = try await AffectedAnalyzer.affectedTests(
            changedPaths: ["Sources/App/Store.swift"],
            store: store,
            projectRoot: "/p"
        )

        let byPath = Dictionary(uniqueKeysWithValues: tests.map { ($0.path, $0.reason) })
        #expect(byPath["/p/Tests/AppTests/StoreTests.swift"] == .graph)
        #expect(byPath["/p/Tests/AppTests/ImportOnlyTests.swift"] == .importsModule)
        #expect(byPath["/p/Tests/OtherTests/UnrelatedTests.swift"] == nil)
    }

    @Test("Dead code exempts init, body, test files and witnesses from extension conformances")
    func deadCodeExtensionAndNameExemptions() async throws {
        let protocols = """
        protocol Handler {
            func handle()
        }
        """
        let concrete = """
        struct Concrete {
            init() {}
            var body: Int { 0 }
            func stray() {}
        }

        extension Concrete: Handler {
            func handle() {}
        }
        """
        let other = """
        struct Other {}

        extension Other: Handler {}

        extension Other {
            func handle() {}
        }
        """
        let store = try await build([
            ("/p/Sources/App/Handler.swift", protocols),
            ("/p/Sources/App/Concrete.swift", concrete),
            ("/p/Sources/App/Other.swift", other),
            ("/p/Tests/AppTests/HelperTests.swift", "func unusedHelper() {}"),
        ])

        let names = try await Set(DeadCodeFinder.find(in: store).map(\.qualifiedName))

        #expect(names.contains("Concrete.stray"))
        #expect(!names.contains("Concrete.init"))
        #expect(!names.contains("Concrete.body"))
        #expect(!names.contains("Concrete.handle"))
        #expect(!names.contains("Other.handle"))
        #expect(!names.contains("unusedHelper"))
    }

    @Test("Resolution ends when unresolved duplicate edges collide", .timeLimit(.minutes(1)))
    func duplicateUnresolvedEdgesTerminate() async throws {
        let path = "/p/Sources/App/S.swift"
        let store = try await build([(path, "struct S {\n    func a() {}\n    func b() { a() }\n}")])
        let callerID = try #require(try await store.symbols(inPath: path).first { $0.name == "b" }?.id)

        let duplicate = GraphEdge(sourceID: callerID, targetName: "a", kind: .calls, sourcePath: path)
        try await store.insertEdges([duplicate])
        try await store.insertEdges([duplicate])
        try await store.insertEdges([GraphEdge(sourceID: callerID, targetName: "zz", kind: .calls, sourcePath: path)])
        try await store.insertEdges([GraphEdge(sourceID: callerID, targetName: "zz", kind: .calls, sourcePath: path)])

        try await SymbolResolver().resolveAll(chunkStore: store)

        #expect(try await store.unattemptedEdges(limit: 10).isEmpty)
        let toA = try await store.outgoingEdges(from: callerID, minConfidence: 0).filter { $0.targetName == "a" }
        #expect(toA.count == 1)
        #expect(toA.first?.targetID != nil)
    }

    @Test("EdgeResolution changes kind only between inherits and conforms")
    func edgeResolutionKindInvariant() {
        #expect(EdgeResolution.isValid(kind: .calls, resolvedKind: nil))
        #expect(EdgeResolution.isValid(kind: .conforms, resolvedKind: .inherits))
        #expect(EdgeResolution.isValid(kind: .inherits, resolvedKind: .conforms))
        #expect(!EdgeResolution.isValid(kind: .calls, resolvedKind: .inherits))
        #expect(!EdgeResolution.isValid(kind: .conforms, resolvedKind: .calls))
    }
}
