import Foundation
@testable import SwiftIndexCore
import Testing

// MARK: - SearchResult Tests

@Suite("SearchResult Tests")
struct SearchResultTests {
    @Test("SearchResult creation")
    func searchResultCreation() {
        let chunk = CodeChunk(
            path: "/test.swift",
            content: "func test() {}",
            startLine: 1,
            endLine: 1,
            kind: .function,
            fileHash: "hash"
        )

        let result = SearchResult(
            chunk: chunk,
            score: 0.95,
            bm25Score: 0.8,
            semanticScore: 0.9,
            bm25Rank: 2,
            semanticRank: 1
        )

        #expect(result.score == 0.95)
        #expect(result.bm25Score == 0.8)
        #expect(result.semanticScore == 0.9)
        #expect(result.bm25Rank == 2)
        #expect(result.semanticRank == 1)
        #expect(!result.isMultiHop)
    }

    @Test("SearchResult comparison")
    func searchResultComparison() {
        let chunk1 = CodeChunk(
            id: "1",
            path: "/test1.swift",
            content: "func test1() {}",
            startLine: 1,
            endLine: 1,
            kind: .function,
            fileHash: "hash1"
        )

        let chunk2 = CodeChunk(
            id: "2",
            path: "/test2.swift",
            content: "func test2() {}",
            startLine: 1,
            endLine: 1,
            kind: .function,
            fileHash: "hash2"
        )

        let result1 = SearchResult(chunk: chunk1, score: 0.9)
        let result2 = SearchResult(chunk: chunk2, score: 0.8)

        // Higher score should be "less than" for sorting (comes first)
        #expect(result1 < result2)

        let sorted = [result2, result1].sorted()
        #expect(sorted.first?.chunk.id == "1")
    }

    @Test("SearchResult identifiable")
    func searchResultIdentifiable() {
        let chunk = CodeChunk(
            id: "unique-id",
            path: "/test.swift",
            content: "func test() {}",
            startLine: 1,
            endLine: 1,
            kind: .function,
            fileHash: "hash"
        )

        let result = SearchResult(chunk: chunk, score: 0.9)
        #expect(result.id == "unique-id")
    }
}
