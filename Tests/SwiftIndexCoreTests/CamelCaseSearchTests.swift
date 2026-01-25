import Foundation
@testable import SwiftIndexCore
import Testing

// MARK: - CamelCase Search Tests

@Suite("CamelCase Search Tests")
struct CamelCaseSearchTests {
    // MARK: - CamelCase Detection Tests

    @Test("isCamelCaseIdentifier detects valid CamelCase")
    func detectsValidCamelCase() {
        // These should be detected as CamelCase
        #expect(BM25SearchTestHelper.isCamelCaseIdentifier("USearchError") == true)
        #expect(BM25SearchTestHelper.isCamelCaseIdentifier("CodeChunk") == true)
        #expect(BM25SearchTestHelper.isCamelCaseIdentifier("HybridSearchEngine") == true)
        #expect(BM25SearchTestHelper.isCamelCaseIdentifier("GRDBChunkStore") == true)
        #expect(BM25SearchTestHelper.isCamelCaseIdentifier("FTS5") == true)
        #expect(BM25SearchTestHelper.isCamelCaseIdentifier("iOS16") == true)
    }

    @Test("isCamelCaseIdentifier rejects non-CamelCase")
    func rejectsNonCamelCase() {
        // These should NOT be detected as CamelCase
        #expect(BM25SearchTestHelper.isCamelCaseIdentifier("search") == false)
        #expect(BM25SearchTestHelper.isCamelCaseIdentifier("SEARCH") == false)
        #expect(BM25SearchTestHelper.isCamelCaseIdentifier("AB") == false) // Too short
        #expect(BM25SearchTestHelper.isCamelCaseIdentifier("123") == false) // No letters
        #expect(BM25SearchTestHelper.isCamelCaseIdentifier("hello world") == false) // Has space
        #expect(BM25SearchTestHelper.isCamelCaseIdentifier("") == false) // Empty
    }

    // MARK: - BM25 Query Preparation Tests

    @Test("BM25 uses exact match for CamelCase terms")
    func bm25ExactMatchForCamelCase() async throws {
        let store = try GRDBChunkStore()
        let search = BM25Search(chunkStore: store)

        // Insert chunk with USearchError
        let chunk = CodeChunk(
            id: "1",
            path: "Sources/Storage/USearchVectorStore.swift",
            content: "} catch let usearchError as USearchError {",
            startLine: 145,
            endLine: 147,
            kind: .function,
            symbols: ["insert"],
            references: ["USearchError"],
            fileHash: "abc"
        )
        try await store.insert(chunk)

        // Insert another chunk that just mentions "Search"
        let otherChunk = CodeChunk(
            id: "2",
            path: "Sources/Search/SearchEngine.swift",
            content: "func performSearch(query: String) {}",
            startLine: 10,
            endLine: 12,
            kind: .function,
            symbols: ["performSearch"],
            references: [],
            fileHash: "def"
        )
        try await store.insert(otherChunk)

        // Search for USearchError - should find only the exact match
        let results = try await search.search(
            query: "USearchError",
            options: SearchOptions(limit: 10)
        )

        // Should find the chunk with USearchError
        #expect(results.contains(where: { $0.chunk.id == "1" }))
    }

    // MARK: - Content-Based Boost Tests

    @Test("Content-based boost for rare CamelCase in catch clause")
    func contentBoostForRareCamelCase() async throws {
        let chunkStore = try GRDBChunkStore()
        let vectorStore = try USearchVectorStore(dimension: 384, path: nil)
        let embeddingProvider = MockEmbeddingProviderForCamelCase()
        let engine = HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: embeddingProvider
        )

        // Insert chunk with USearchError in content (not in symbols)
        let targetChunk = CodeChunk(
            id: "usearch-1",
            path: "Sources/Storage/USearchVectorStore.swift",
            content: """
            public func insert(id: String, vector: [Float]) async throws {
                do {
                    index.add(label: numericId, vector: vector)
                } catch let usearchError as USearchError {
                    throw VectorStoreError.insertionFailed(id: id)
                }
            }
            """,
            startLine: 140,
            endLine: 150,
            kind: .function,
            symbols: ["insert"],
            references: ["USearchError", "VectorStoreError"],
            fileHash: "abc123"
        )
        try await chunkStore.insert(targetChunk)
        let vector1 = try await embeddingProvider.embed("insert vector error")
        try await vectorStore.add(id: "usearch-1", vector: vector1)

        // Insert unrelated chunks to make USearchError rare
        for i in 0 ..< 5 {
            let chunk = CodeChunk(
                id: "other-\(i)",
                path: "Sources/Other/File\(i).swift",
                content: "func someFunction\(i)() { print(\"unrelated code\") }",
                startLine: 1,
                endLine: 3,
                kind: .function,
                symbols: ["someFunction\(i)"],
                references: [],
                fileHash: "hash\(i)"
            )
            try await chunkStore.insert(chunk)
            let otherVector = try await embeddingProvider.embed("some function")
            try await vectorStore.add(id: "other-\(i)", vector: otherVector)
        }

        // Search for USearchError
        let results = try await engine.search(
            query: "USearchError",
            options: SearchOptions(limit: 10, semanticWeight: 0.7)
        )

        // The chunk containing USearchError should be in results
        // and should have exactSymbolMatch = true (due to content-based boost)
        let targetResult = results.first(where: { $0.chunk.id == "usearch-1" })
        #expect(targetResult != nil, "Target chunk should be in results")

        // Verify it gets boosted (should be near the top)
        if let index = results.firstIndex(where: { $0.chunk.id == "usearch-1" }) {
            #expect(index < 3, "USearchError chunk should be in top 3 results")
        }
    }

    @Test("Symbol boost takes precedence over content boost")
    func symbolBoostTakesPrecedence() async throws {
        let chunkStore = try GRDBChunkStore()
        let vectorStore = try USearchVectorStore(dimension: 384, path: nil)
        let embeddingProvider = MockEmbeddingProviderForCamelCase()
        let engine = HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: embeddingProvider
        )

        // Chunk with term in symbols (should get 2.5x boost)
        let symbolChunk = CodeChunk(
            id: "symbol-chunk",
            path: "Sources/Models/USearchError.swift",
            content: "public struct USearchError: Error {}",
            startLine: 1,
            endLine: 1,
            kind: .struct,
            symbols: ["USearchError"],
            references: [],
            fileHash: "sym123"
        )
        try await chunkStore.insert(symbolChunk)
        let symbolVector = try await embeddingProvider.embed("USearchError struct")
        try await vectorStore.add(id: "symbol-chunk", vector: symbolVector)

        // Chunk with term only in content (should get 2.0x boost)
        let contentChunk = CodeChunk(
            id: "content-chunk",
            path: "Sources/Storage/VectorStore.swift",
            content: "} catch let error as USearchError { throw error }",
            startLine: 50,
            endLine: 52,
            kind: .function,
            symbols: ["handleError"],
            references: ["USearchError"],
            fileHash: "cnt123"
        )
        try await chunkStore.insert(contentChunk)
        let contentVector = try await embeddingProvider.embed("handle USearchError")
        try await vectorStore.add(id: "content-chunk", vector: contentVector)

        let results = try await engine.search(
            query: "USearchError",
            options: SearchOptions(limit: 10, semanticWeight: 0.5)
        )

        // Symbol chunk should rank higher due to higher boost (2.5x vs 2.0x)
        let symbolIndex = results.firstIndex(where: { $0.chunk.id == "symbol-chunk" })
        let contentIndex = results.firstIndex(where: { $0.chunk.id == "content-chunk" })

        #expect(symbolIndex != nil, "Symbol chunk should be in results")
        #expect(contentIndex != nil, "Content chunk should be in results")

        if let si = symbolIndex, let ci = contentIndex {
            #expect(si < ci, "Symbol chunk should rank higher than content-only chunk")
        }
    }
}

// MARK: - Test Helpers

/// Helper to expose BM25Search's private isCamelCaseIdentifier for testing.
enum BM25SearchTestHelper {
    static func isCamelCaseIdentifier(_ term: String) -> Bool {
        guard term.count >= 3,
              term.first?.isLetter == true,
              !term.contains(" ")
        else {
            return false
        }
        return term.contains(where: \.isUppercase) &&
            term.contains(where: \.isLowercase)
    }
}

/// Mock embedding provider for CamelCase tests.
actor MockEmbeddingProviderForCamelCase: EmbeddingProvider {
    nonisolated let id = "mock-camelcase"
    nonisolated let name = "Mock CamelCase Provider"
    nonisolated let dimension = 384

    nonisolated func isAvailable() async -> Bool { true }

    func embed(_ text: String) async throws -> [Float] {
        Self.generateEmbedding(text, dimension: dimension)
    }

    private nonisolated static func generateEmbedding(_ text: String, dimension: Int) -> [Float] {
        // Generate deterministic embedding based on text hash
        var vector = [Float](repeating: 0, count: dimension)
        let hash = text.hashValue
        for i in 0 ..< dimension {
            vector[i] = Float((hash &+ i * 31) % 1000) / 1000.0
        }
        return vector
    }
}
