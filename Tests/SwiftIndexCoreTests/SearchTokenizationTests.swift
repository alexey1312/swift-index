import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("Search Tokenization Tests")
struct SearchTokenizationTests {
    @Test("Exact match for CamelCase identifier")
    func camelCaseMatch() async throws {
        let store = try GRDBChunkStore()

        let chunk = CodeChunk(
            id: "1",
            path: "test.swift",
            content: "public struct USearchError: Error {}",
            startLine: 1,
            endLine: 1,
            kind: .struct,
            symbols: ["USearchError"],
            references: [],
            fileHash: "abc",
            createdAt: Date(),
            docComment: nil,
            signature: nil,
            breadcrumb: nil,
            tokenCount: 0,
            language: "swift",
            contentHash: nil,
            generatedDescription: nil,
            conformances: [],
            isTypeDeclaration: true
        )

        try await store.insert(chunk)

        // Search for exact identifier
        let results = try await store.searchFTS(query: "USearchError", limit: 10)

        #expect(results.count == 1)
        #expect(results.first?.chunk.id == "1")
    }

    @Test("Exact match for mixed case")
    func mixedCase() async throws {
        let store = try GRDBChunkStore()
        let chunk = CodeChunk(
            id: "2",
            path: "test.swift",
            content: "func performSearch() {}",
            startLine: 1,
            endLine: 1,
            kind: .function,
            symbols: ["performSearch"],
            references: [],
            fileHash: "def",
            createdAt: Date(),
            docComment: nil,
            signature: nil,
            breadcrumb: nil,
            tokenCount: 0,
            language: "swift",
            contentHash: nil,
            generatedDescription: nil,
            conformances: [],
            isTypeDeclaration: false
        )
        try await store.insert(chunk)

        // Should match case-insensitive with unicode61 (default)
        let results = try await store.searchFTS(query: "performSearch", limit: 10)
        #expect(results.count == 1)

        let resultsLower = try await store.searchFTS(query: "performsearch", limit: 10)
        #expect(resultsLower.count == 1)
    }

    @Test("Verify stemming is disabled (no porter)")
    func stemmingDisabled() async throws {
        let store = try GRDBChunkStore()

        // "generic" and "generically" stem to "gener" in Porter.
        // If Porter is active, searching "generically" should find "generic".
        // If Porter is INACTIVE (unicode61), "generically" (-> generically*) should NOT find "generic".

        let chunk = CodeChunk(
            id: "5",
            path: "test.swift",
            content: "This is generic code",
            startLine: 1,
            endLine: 1,
            kind: .comment,
            symbols: [],
            references: [],
            fileHash: "mno",
            createdAt: Date(),
            docComment: nil,
            signature: nil,
            breadcrumb: nil,
            tokenCount: 0,
            language: "swift",
            contentHash: nil,
            generatedDescription: nil,
            conformances: [],
            isTypeDeclaration: false
        )
        try await store.insert(chunk)

        // Query: "generically"
        // unicode61: "generically*" matches "generically", "genericallyspeaking". NOT "generic".
        let results = try await store.searchFTS(query: "generically", limit: 10)

        // Should be empty with unicode61
        #expect(results.isEmpty)
    }
}
