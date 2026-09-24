import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("BM25 OR Fallback Tests")
struct BM25FallbackTests {
    private func store(_ contents: [String: String]) async throws -> GRDBChunkStore {
        let store = try GRDBChunkStore()
        for (id, content) in contents.sorted(by: { $0.key < $1.key }) {
            try await store.insert(CodeChunk(
                id: id, path: "/p/\(id).swift", content: content, startLine: 1, endLine: 3,
                kind: .function, fileHash: id
            ))
        }
        return store
    }

    @Test("A query that no chunk matches with AND still returns partial matches")
    func orFallback() async throws {
        let search = try await BM25Search(chunkStore: store([
            "save": "func persistIndex() { writer.flush() }",
            "load": "func restoreVectors() { reader.open() }",
            "noise": "func unrelated() {}",
        ]))

        let results = try await search.search(query: "how does writer flush reader", options: SearchOptions(limit: 10))

        #expect(Set(results.map(\.chunk.id)) == ["save", "load"])
    }

    @Test("AND matches rank first and every chunk appears once")
    func andFirstNoDuplicates() async throws {
        let search = try await BM25Search(chunkStore: store([
            "both": "func persist() { writer.flush() }",
            "writer": "let writer = Writer()",
            "flush": "func flush() {}",
        ]))

        let results = try await search.search(query: "writer flush", options: SearchOptions(limit: 10))
        let ids = results.map(\.chunk.id)

        #expect(ids.first == "both")
        #expect(Set(ids) == ["both", "writer", "flush"])
        #expect(ids.count == Set(ids).count)
    }

    @Test("A query of only stop words returns nothing and does not throw")
    func stopWordsOnly() async throws {
        let search = try await BM25Search(chunkStore: store(["save": "func persistIndex() {}"]))

        let results = try await search.search(query: "how does the", options: SearchOptions(limit: 10))

        #expect(results.isEmpty)
    }
}
