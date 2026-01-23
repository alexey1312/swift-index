import Foundation
@testable import SwiftIndexCore
import Testing

// MARK: - IndexManager Tests

@Suite("IndexManager Tests")
struct IndexManagerTests {
    let dimension = 4

    // MARK: - Indexing

    @Test("Index chunk with vector")
    func testIndex() async throws {
        let manager = try await makeIndexManager()
        let chunk = makeChunk(id: "idx-1")
        let vector: [Float] = [0.1, 0.2, 0.3, 0.4]

        try await manager.index(chunk: chunk, vector: vector)

        let retrieved = try await manager.getChunk(id: "idx-1")
        let vectorExists = try await manager.vectorStore.contains(id: "idx-1")

        #expect(retrieved != nil)
        #expect(vectorExists == true)
    }

    @Test("Index batch")
    func testIndexBatch() async throws {
        let manager = try await makeIndexManager()
        let items: [(chunk: CodeChunk, vector: [Float])] = [
            (makeChunk(id: "batch-1"), [0.1, 0.2, 0.3, 0.4]),
            (makeChunk(id: "batch-2"), [0.5, 0.6, 0.7, 0.8]),
            (makeChunk(id: "batch-3"), [0.9, 1.0, 1.1, 1.2]),
        ]

        try await manager.indexBatch(items)
        let stats = try await manager.statistics()

        #expect(stats.chunkCount == 3)
        #expect(stats.vectorCount == 3)
    }

    // MARK: - Incremental Indexing

    @Test("Check needs indexing for new file")
    func needsIndexingNew() async throws {
        let manager = try await makeIndexManager()

        let needsIndexing = try await manager.needsIndexing(fileHash: "new-hash")

        #expect(needsIndexing == true)
    }

    @Test("Check needs indexing for indexed file")
    func needsIndexingExisting() async throws {
        let manager = try await makeIndexManager()
        try await manager.recordIndexed(fileHash: "existing-hash", path: "/test/file.swift")

        let needsIndexing = try await manager.needsIndexing(fileHash: "existing-hash")

        #expect(needsIndexing == false)
    }

    @Test("Reindex file")
    func testReindex() async throws {
        let manager = try await makeIndexManager()

        // Index original chunks
        try await manager.indexBatch([
            (makeChunk(id: "old-1", path: "/test/file.swift", fileHash: "old-hash"), [0.1, 0.2, 0.3, 0.4]),
            (makeChunk(id: "old-2", path: "/test/file.swift", fileHash: "old-hash"), [0.5, 0.6, 0.7, 0.8]),
        ])
        try await manager.recordIndexed(fileHash: "old-hash", path: "/test/file.swift")

        // Reindex with new chunks
        let newChunks: [(chunk: CodeChunk, vector: [Float])] = [
            (makeChunk(id: "new-1", path: "/test/file.swift", fileHash: "new-hash"), [0.1, 0.2, 0.3, 0.4]),
        ]
        try await manager.reindex(path: "/test/file.swift", newChunks: newChunks)

        // Verify old chunks removed, new chunks present
        let oldChunk1 = try await manager.getChunk(id: "old-1")
        let oldChunk2 = try await manager.getChunk(id: "old-2")
        let newChunk1 = try await manager.getChunk(id: "new-1")

        #expect(oldChunk1 == nil)
        #expect(oldChunk2 == nil)
        #expect(newChunk1 != nil)
    }

    // MARK: - Search

    @Test("Semantic search")
    func semanticSearch() async throws {
        let manager = try await makeIndexManager()
        try await manager.indexBatch([
            (makeChunk(id: "sem-1", content: "authentication"), [1.0, 0.0, 0.0, 0.0]),
            (makeChunk(id: "sem-2", content: "payment"), [0.0, 1.0, 0.0, 0.0]),
            (makeChunk(id: "sem-3", content: "logging"), [0.0, 0.0, 1.0, 0.0]),
        ])

        let results = try await manager.searchSemantic(
            vector: [0.9, 0.1, 0.0, 0.0],
            limit: 3
        )

        #expect(results.count == 3)
        #expect(results[0].chunk.id == "sem-1")
    }

    @Test("FTS search through manager")
    func fTSSearch() async throws {
        let manager = try await makeIndexManager()
        try await manager.indexBatch([
            (
                makeChunk(id: "fts-1", content: "func authenticate(user: User) // handle authentication"),
                [0.1, 0.2, 0.3, 0.4]
            ),
            (makeChunk(id: "fts-2", content: "func processPayment()"), [0.5, 0.6, 0.7, 0.8]),
        ])

        let results = try await manager.searchFTS(query: "authentication", limit: 10)

        #expect(results.count >= 1)
        #expect(results[0].chunk.id == "fts-1")
    }

    @Test("Hybrid search combines semantic and FTS")
    func hybridSearch() async throws {
        let manager = try await makeIndexManager()
        try await manager.indexBatch([
            (makeChunk(id: "hyb-1", content: "func authenticateUser(credentials: Credentials)"), [1.0, 0.0, 0.0, 0.0]),
            (makeChunk(id: "hyb-2", content: "func validateToken(token: String)"), [0.8, 0.2, 0.0, 0.0]),
            (makeChunk(id: "hyb-3", content: "func processPayment(amount: Double)"), [0.0, 1.0, 0.0, 0.0]),
        ])

        let results = try await manager.searchHybrid(
            query: "authenticate",
            vector: [0.9, 0.1, 0.0, 0.0],
            options: HybridSearchOptions(limit: 3, semanticWeight: 0.5)
        )

        #expect(results.count >= 1)
        // hyb-1 should rank high due to both semantic similarity and FTS match
        #expect(results[0].chunk.id == "hyb-1")
    }

    // MARK: - Statistics and Maintenance

    @Test("Statistics reports correct counts")
    func testStatistics() async throws {
        let manager = try await makeIndexManager()
        try await manager.indexBatch([
            (makeChunk(id: "stat-1", path: "/test/a.swift"), [0.1, 0.2, 0.3, 0.4]),
            (makeChunk(id: "stat-2", path: "/test/a.swift"), [0.5, 0.6, 0.7, 0.8]),
            (makeChunk(id: "stat-3", path: "/test/b.swift"), [0.9, 1.0, 1.1, 1.2]),
        ])

        let stats = try await manager.statistics()

        #expect(stats.chunkCount == 3)
        #expect(stats.vectorCount == 3)
        #expect(stats.fileCount == 2)
        #expect(stats.dimension == dimension)
        #expect(stats.isConsistent == true)
    }

    @Test("Verify consistency")
    func testVerifyConsistency() async throws {
        let manager = try await makeIndexManager()
        try await manager.indexBatch([
            (makeChunk(id: "cons-1"), [0.1, 0.2, 0.3, 0.4]),
            (makeChunk(id: "cons-2"), [0.5, 0.6, 0.7, 0.8]),
        ])

        let report = try await manager.verifyConsistency()

        #expect(report.isConsistent == true)
        #expect(report.missingVectors.isEmpty)
        #expect(report.orphanedVectors.isEmpty)
    }

    @Test("Clear index")
    func testClear() async throws {
        let manager = try await makeIndexManager()
        try await manager.indexBatch([
            (makeChunk(id: "clr-1"), [0.1, 0.2, 0.3, 0.4]),
            (makeChunk(id: "clr-2"), [0.5, 0.6, 0.7, 0.8]),
        ])

        try await manager.clear()
        let stats = try await manager.statistics()

        #expect(stats.chunkCount == 0)
        #expect(stats.vectorCount == 0)
    }

    // MARK: - Content-Based Change Detection

    @Test("ReindexWithChangeDetection reuses vectors for unchanged chunks")
    func reindexWithChangeDetectionReusesVectors() async throws {
        let manager = try await makeIndexManager()

        // Create initial chunks with content hashes
        let content1 = "func authenticate() { }"
        let content2 = "func logout() { }"
        // Content hashes are computed automatically by CodeChunk

        let chunk1 = CodeChunk(
            id: "change-1",
            path: "/test/file.swift",
            content: content1,
            startLine: 1,
            endLine: 3,
            kind: .function,
            symbols: ["authenticate"],
            references: [],
            fileHash: "file-hash-1"
        )
        let chunk2 = CodeChunk(
            id: "change-2",
            path: "/test/file.swift",
            content: content2,
            startLine: 5,
            endLine: 7,
            kind: .function,
            symbols: ["logout"],
            references: [],
            fileHash: "file-hash-1"
        )

        // Index initial chunks
        try await manager.indexBatch([
            (chunk: chunk1, vector: [1.0, 0.0, 0.0, 0.0]),
            (chunk: chunk2, vector: [0.0, 1.0, 0.0, 0.0]),
        ])
        try await manager.recordIndexed(fileHash: "file-hash-1", path: "/test/file.swift")

        // Track embedding calls
        var embeddingCallCount = 0

        // Create new chunks - chunk1 unchanged (same content), chunk2 modified
        let newContent2 = "func logoutUser() { }"
        let newChunk1 = CodeChunk(
            id: "new-change-1",
            path: "/test/file.swift",
            content: content1, // Same content as chunk1
            startLine: 1,
            endLine: 3,
            kind: .function,
            symbols: ["authenticate"],
            references: [],
            fileHash: "file-hash-2"
        )
        let newChunk2 = CodeChunk(
            id: "new-change-2",
            path: "/test/file.swift",
            content: newContent2, // Different content
            startLine: 5,
            endLine: 7,
            kind: .function,
            symbols: ["logoutUser"],
            references: [],
            fileHash: "file-hash-2"
        )

        // Reindex with change detection
        let result = try await manager.reindexWithChangeDetection(
            path: "/test/file.swift",
            newChunks: [newChunk1, newChunk2]
        ) { chunksToEmbed in
            embeddingCallCount = chunksToEmbed.count
            // Only newChunk2 should need embedding (content changed)
            return chunksToEmbed.map { _ in [0.0, 0.0, 1.0, 0.0] as [Float] }
        }

        // Verify results
        #expect(result.totalChunks == 2)
        #expect(result.reusedChunks == 1) // chunk1's content unchanged
        #expect(result.embeddedChunks == 1) // chunk2's content changed
        #expect(embeddingCallCount == 1) // Only one chunk needed embedding

        // Verify both chunks are in the index
        let stats = try await manager.statistics()
        #expect(stats.chunkCount == 2)
    }

    @Test("ReindexWithChangeDetection embeds all chunks when content all changed")
    func reindexWithChangeDetectionEmbedsAllWhenAllChanged() async throws {
        let manager = try await makeIndexManager()

        // Create initial chunk
        let chunk1 = CodeChunk(
            id: "old-1",
            path: "/test/file.swift",
            content: "func old() { }",
            startLine: 1,
            endLine: 3,
            kind: .function,
            symbols: ["old"],
            references: [],
            fileHash: "hash-1"
        )

        try await manager.indexBatch([
            (chunk: chunk1, vector: [1.0, 0.0, 0.0, 0.0]),
        ])

        // Create completely new chunks (different content)
        let newChunks = [
            CodeChunk(
                id: "new-1",
                path: "/test/file.swift",
                content: "func newFunc1() { }",
                startLine: 1,
                endLine: 3,
                kind: .function,
                symbols: ["newFunc1"],
                references: [],
                fileHash: "hash-2"
            ),
            CodeChunk(
                id: "new-2",
                path: "/test/file.swift",
                content: "func newFunc2() { }",
                startLine: 5,
                endLine: 7,
                kind: .function,
                symbols: ["newFunc2"],
                references: [],
                fileHash: "hash-2"
            ),
        ]

        var embeddingCallCount = 0
        let result = try await manager.reindexWithChangeDetection(
            path: "/test/file.swift",
            newChunks: newChunks
        ) { chunksToEmbed in
            embeddingCallCount = chunksToEmbed.count
            return chunksToEmbed.map { _ in [0.5, 0.5, 0.0, 0.0] as [Float] }
        }

        #expect(result.totalChunks == 2)
        #expect(result.reusedChunks == 0) // No content matched
        #expect(result.embeddedChunks == 2) // All chunks needed embedding
        #expect(embeddingCallCount == 2)
    }

    @Test("ReindexWithChangeDetection reuses all vectors when content unchanged")
    func reindexWithChangeDetectionReusesAllWhenUnchanged() async throws {
        let manager = try await makeIndexManager()

        let content1 = "func first() { }"
        let content2 = "func second() { }"

        let chunk1 = CodeChunk(
            id: "same-1",
            path: "/test/file.swift",
            content: content1,
            startLine: 1,
            endLine: 3,
            kind: .function,
            symbols: ["first"],
            references: [],
            fileHash: "hash-1"
        )
        let chunk2 = CodeChunk(
            id: "same-2",
            path: "/test/file.swift",
            content: content2,
            startLine: 5,
            endLine: 7,
            kind: .function,
            symbols: ["second"],
            references: [],
            fileHash: "hash-1"
        )

        try await manager.indexBatch([
            (chunk: chunk1, vector: [1.0, 0.0, 0.0, 0.0]),
            (chunk: chunk2, vector: [0.0, 1.0, 0.0, 0.0]),
        ])

        // Reindex with exact same content (but new IDs)
        let newChunks = [
            CodeChunk(
                id: "new-same-1",
                path: "/test/file.swift",
                content: content1, // Same content
                startLine: 1,
                endLine: 3,
                kind: .function,
                symbols: ["first"],
                references: [],
                fileHash: "hash-2"
            ),
            CodeChunk(
                id: "new-same-2",
                path: "/test/file.swift",
                content: content2, // Same content
                startLine: 5,
                endLine: 7,
                kind: .function,
                symbols: ["second"],
                references: [],
                fileHash: "hash-2"
            ),
        ]

        var embeddingCallCount = 0
        let result = try await manager.reindexWithChangeDetection(
            path: "/test/file.swift",
            newChunks: newChunks
        ) { chunksToEmbed in
            embeddingCallCount = chunksToEmbed.count
            return chunksToEmbed.map { _ in [0.0, 0.0, 0.0, 1.0] as [Float] }
        }

        #expect(result.totalChunks == 2)
        #expect(result.reusedChunks == 2) // All content unchanged
        #expect(result.embeddedChunks == 0) // No new embeddings needed
        #expect(embeddingCallCount == 0) // Embedder should not be called
    }

    @Test("ReindexResult calculates reuse percentage correctly")
    func reindexResultReusePercentage() {
        let result1 = ReindexResult(totalChunks: 10, reusedChunks: 7, embeddedChunks: 3)
        #expect(result1.reusePercentage == 70.0)

        let result2 = ReindexResult(totalChunks: 0, reusedChunks: 0, embeddedChunks: 0)
        #expect(result2.reusePercentage == 0.0)

        let result3 = ReindexResult(totalChunks: 5, reusedChunks: 5, embeddedChunks: 0)
        #expect(result3.reusePercentage == 100.0)
    }

    // MARK: - Helpers

    private func makeIndexManager() async throws -> IndexManager {
        let chunkStore = try GRDBChunkStore()
        let vectorStore = try USearchVectorStore(dimension: dimension)
        return IndexManager(chunkStore: chunkStore, vectorStore: vectorStore)
    }
}
