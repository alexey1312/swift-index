import Testing
import Foundation
@testable import SwiftIndexCore

// MARK: - GRDBChunkStore Tests

@Suite("GRDBChunkStore Tests")
struct GRDBChunkStoreTests {
    // MARK: - Basic CRUD

    @Test("Insert and retrieve chunk")
    func testInsertAndRetrieve() async throws {
        let store = try GRDBChunkStore()
        let chunk = makeChunk(id: "chunk-1", path: "/test/file.swift")

        try await store.insert(chunk)
        let retrieved = try await store.get(id: "chunk-1")

        #expect(retrieved != nil)
        #expect(retrieved?.id == "chunk-1")
        #expect(retrieved?.path == "/test/file.swift")
        #expect(retrieved?.content == chunk.content)
        #expect(retrieved?.kind == .function)
        #expect(retrieved?.symbols == ["testFunction"])
    }

    @Test("Insert batch of chunks")
    func testInsertBatch() async throws {
        let store = try GRDBChunkStore()
        let chunks = [
            makeChunk(id: "batch-1", path: "/test/file1.swift"),
            makeChunk(id: "batch-2", path: "/test/file2.swift"),
            makeChunk(id: "batch-3", path: "/test/file3.swift")
        ]

        try await store.insertBatch(chunks)
        let count = try await store.count()

        #expect(count == 3)
    }

    @Test("Get chunks by path")
    func testGetByPath() async throws {
        let store = try GRDBChunkStore()
        try await store.insertBatch([
            makeChunk(id: "path-1", path: "/test/file.swift", startLine: 1),
            makeChunk(id: "path-2", path: "/test/file.swift", startLine: 10),
            makeChunk(id: "path-3", path: "/test/other.swift", startLine: 1)
        ])

        let chunks = try await store.getByPath("/test/file.swift")

        #expect(chunks.count == 2)
        #expect(chunks[0].startLine < chunks[1].startLine) // Ordered by line
    }

    @Test("Update chunk")
    func testUpdate() async throws {
        let store = try GRDBChunkStore()
        let original = makeChunk(id: "update-1", content: "original content")
        try await store.insert(original)

        let updated = CodeChunk(
            id: "update-1",
            path: original.path,
            content: "updated content",
            startLine: original.startLine,
            endLine: original.endLine,
            kind: original.kind,
            symbols: ["updatedSymbol"],
            references: original.references,
            fileHash: original.fileHash,
            createdAt: original.createdAt
        )

        try await store.update(updated)
        let retrieved = try await store.get(id: "update-1")

        #expect(retrieved?.content == "updated content")
        #expect(retrieved?.symbols == ["updatedSymbol"])
    }

    @Test("Delete chunk by ID")
    func testDeleteByID() async throws {
        let store = try GRDBChunkStore()
        try await store.insert(makeChunk(id: "delete-1"))

        try await store.delete(id: "delete-1")
        let retrieved = try await store.get(id: "delete-1")

        #expect(retrieved == nil)
    }

    @Test("Delete chunks by path")
    func testDeleteByPath() async throws {
        let store = try GRDBChunkStore()
        try await store.insertBatch([
            makeChunk(id: "del-path-1", path: "/test/delete.swift"),
            makeChunk(id: "del-path-2", path: "/test/delete.swift"),
            makeChunk(id: "del-path-3", path: "/test/keep.swift")
        ])

        try await store.deleteByPath("/test/delete.swift")
        let remaining = try await store.count()

        #expect(remaining == 1)
    }

    // MARK: - FTS Search

    @Test("FTS search finds matching content")
    func testFTSSearch() async throws {
        let store = try GRDBChunkStore()
        try await store.insertBatch([
            makeChunk(id: "fts-1", content: "func authenticate(user: User) { }"),
            makeChunk(id: "fts-2", content: "func validatePassword(password: String) { }"),
            makeChunk(id: "fts-3", content: "struct UserProfile { var name: String }")
        ])

        let results = try await store.searchFTS(query: "authenticate", limit: 10)

        #expect(results.count >= 1)
        #expect(results[0].chunk.id == "fts-1")
        #expect(results[0].score > 0)
    }

    @Test("FTS search with multiple terms")
    func testFTSMultipleTerms() async throws {
        let store = try GRDBChunkStore()
        try await store.insertBatch([
            makeChunk(id: "multi-1", content: "func handleLogin(username: String, password: String)"),
            makeChunk(id: "multi-2", content: "func processPayment(amount: Double)"),
            makeChunk(id: "multi-3", content: "func validatePassword(password: String) // verify password")
        ])

        let results = try await store.searchFTS(query: "password", limit: 10)

        // FTS5 finds chunks containing "password" as a word token
        #expect(results.count >= 2)
    }

    @Test("FTS search returns empty for no matches")
    func testFTSNoMatches() async throws {
        let store = try GRDBChunkStore()
        try await store.insert(makeChunk(id: "no-match", content: "func doSomething()"))

        let results = try await store.searchFTS(query: "nonexistent", limit: 10)

        #expect(results.isEmpty)
    }

    // MARK: - File Hash Tracking

    @Test("Record and check file hash")
    func testFileHashTracking() async throws {
        let store = try GRDBChunkStore()

        let hasHashBefore = try await store.hasFileHash("hash123")
        #expect(hasHashBefore == false)

        try await store.recordFileHash("hash123", path: "/test/file.swift")

        let hasHashAfter = try await store.hasFileHash("hash123")
        #expect(hasHashAfter == true)
    }

    @Test("Delete file hash")
    func testDeleteFileHash() async throws {
        let store = try GRDBChunkStore()
        try await store.recordFileHash("hash-del", path: "/test/file.swift")

        try await store.deleteFileHash(path: "/test/file.swift")
        let hasHash = try await store.hasFileHash("hash-del")

        #expect(hasHash == false)
    }

    // MARK: - Utilities

    @Test("Get all IDs")
    func testAllIDs() async throws {
        let store = try GRDBChunkStore()
        try await store.insertBatch([
            makeChunk(id: "id-1"),
            makeChunk(id: "id-2"),
            makeChunk(id: "id-3")
        ])

        let ids = try await store.allIDs()

        #expect(Set(ids) == Set(["id-1", "id-2", "id-3"]))
    }

    @Test("Get all paths")
    func testAllPaths() async throws {
        let store = try GRDBChunkStore()
        try await store.insertBatch([
            makeChunk(id: "paths-1", path: "/test/a.swift"),
            makeChunk(id: "paths-2", path: "/test/a.swift"),
            makeChunk(id: "paths-3", path: "/test/b.swift")
        ])

        let paths = try await store.allPaths()

        #expect(Set(paths) == Set(["/test/a.swift", "/test/b.swift"]))
    }

    @Test("Clear store")
    func testClear() async throws {
        let store = try GRDBChunkStore()
        try await store.insertBatch([
            makeChunk(id: "clear-1"),
            makeChunk(id: "clear-2")
        ])
        try await store.recordFileHash("clear-hash", path: "/test/file.swift")

        try await store.clear()
        let count = try await store.count()
        let hasHash = try await store.hasFileHash("clear-hash")

        #expect(count == 0)
        #expect(hasHash == false)
    }

    @Test("Get chunks by IDs")
    func testGetByIDs() async throws {
        let store = try GRDBChunkStore()
        try await store.insertBatch([
            makeChunk(id: "byid-1"),
            makeChunk(id: "byid-2"),
            makeChunk(id: "byid-3")
        ])

        let chunks = try await store.getByIDs(["byid-1", "byid-3", "nonexistent"])

        #expect(chunks.count == 2)
        #expect(Set(chunks.map(\.id)) == Set(["byid-1", "byid-3"]))
    }
}

// MARK: - USearchVectorStore Tests

@Suite("USearchVectorStore Tests")
struct USearchVectorStoreTests {
    let dimension = 4

    // MARK: - Basic Operations

    @Test("Add and contains vector")
    func testAddAndContains() async throws {
        let store = try USearchVectorStore(dimension: dimension)
        let vector: [Float] = [0.1, 0.2, 0.3, 0.4]

        try await store.add(id: "vec-1", vector: vector)
        let contains = try await store.contains(id: "vec-1")

        #expect(contains == true)
    }

    @Test("Add batch of vectors")
    func testAddBatch() async throws {
        let store = try USearchVectorStore(dimension: dimension)
        let items: [(id: String, vector: [Float])] = [
            ("batch-1", [0.1, 0.2, 0.3, 0.4]),
            ("batch-2", [0.5, 0.6, 0.7, 0.8]),
            ("batch-3", [0.9, 1.0, 1.1, 1.2])
        ]

        try await store.addBatch(items)
        let count = try await store.count()

        #expect(count == 3)
    }

    @Test("Search finds similar vectors")
    func testSearch() async throws {
        let store = try USearchVectorStore(dimension: dimension)

        // Add vectors with distinct patterns
        try await store.addBatch([
            ("similar", [1.0, 0.0, 0.0, 0.0]),
            ("different", [0.0, 1.0, 0.0, 0.0]),
            ("other", [0.0, 0.0, 1.0, 0.0])
        ])

        // Search for vector similar to "similar"
        let results = try await store.search(vector: [0.9, 0.1, 0.0, 0.0], limit: 3)

        #expect(results.count == 3)
        #expect(results[0].id == "similar")
        #expect(results[0].similarity > results[1].similarity)
    }

    @Test("Search with minimum similarity threshold")
    func testSearchWithThreshold() async throws {
        let store = try USearchVectorStore(dimension: dimension)

        try await store.addBatch([
            ("close", [1.0, 0.0, 0.0, 0.0]),
            ("far", [0.0, 1.0, 0.0, 0.0])
        ])

        let results = try await store.search(
            vector: [1.0, 0.0, 0.0, 0.0],
            limit: 10,
            minSimilarity: 0.9
        )

        #expect(results.count == 1)
        #expect(results[0].id == "close")
    }

    @Test("Delete vector")
    func testDelete() async throws {
        let store = try USearchVectorStore(dimension: dimension)
        try await store.add(id: "del-1", vector: [0.1, 0.2, 0.3, 0.4])

        try await store.delete(id: "del-1")
        let contains = try await store.contains(id: "del-1")

        #expect(contains == false)
    }

    @Test("Update vector by re-adding")
    func testUpdateVector() async throws {
        let store = try USearchVectorStore(dimension: dimension)
        try await store.add(id: "update-1", vector: [0.1, 0.2, 0.3, 0.4])

        // Re-add with same ID should update
        try await store.add(id: "update-1", vector: [0.5, 0.6, 0.7, 0.8])
        let count = try await store.count()

        #expect(count == 1)
    }

    // MARK: - Dimension Validation

    @Test("Throws on dimension mismatch")
    func testDimensionMismatch() async throws {
        let store = try USearchVectorStore(dimension: dimension)

        await #expect(throws: VectorStoreError.self) {
            try await store.add(id: "bad", vector: [0.1, 0.2]) // Wrong dimension
        }
    }

    @Test("Search throws on dimension mismatch")
    func testSearchDimensionMismatch() async throws {
        let store = try USearchVectorStore(dimension: dimension)
        try await store.add(id: "vec-1", vector: [0.1, 0.2, 0.3, 0.4])

        await #expect(throws: VectorStoreError.self) {
            _ = try await store.search(vector: [0.1, 0.2], limit: 10)
        }
    }

    // MARK: - Utilities

    @Test("Get all IDs")
    func testAllIDs() async throws {
        let store = try USearchVectorStore(dimension: dimension)
        try await store.addBatch([
            ("id-1", [0.1, 0.2, 0.3, 0.4]),
            ("id-2", [0.5, 0.6, 0.7, 0.8])
        ])

        let ids = try await store.allIDs()

        #expect(Set(ids) == Set(["id-1", "id-2"]))
    }

    @Test("Clear store")
    func testClear() async throws {
        let store = try USearchVectorStore(dimension: dimension)
        try await store.addBatch([
            ("clear-1", [0.1, 0.2, 0.3, 0.4]),
            ("clear-2", [0.5, 0.6, 0.7, 0.8])
        ])

        try await store.clear()
        let count = try await store.count()

        #expect(count == 0)
    }

    @Test("Search on empty store returns empty")
    func testSearchEmpty() async throws {
        let store = try USearchVectorStore(dimension: dimension)

        let results = try await store.search(vector: [0.1, 0.2, 0.3, 0.4], limit: 10)

        #expect(results.isEmpty)
    }
}

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
            (makeChunk(id: "batch-3"), [0.9, 1.0, 1.1, 1.2])
        ]

        try await manager.indexBatch(items)
        let stats = try await manager.statistics()

        #expect(stats.chunkCount == 3)
        #expect(stats.vectorCount == 3)
    }

    // MARK: - Incremental Indexing

    @Test("Check needs indexing for new file")
    func testNeedsIndexingNew() async throws {
        let manager = try await makeIndexManager()

        let needsIndexing = try await manager.needsIndexing(fileHash: "new-hash")

        #expect(needsIndexing == true)
    }

    @Test("Check needs indexing for indexed file")
    func testNeedsIndexingExisting() async throws {
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
            (makeChunk(id: "old-2", path: "/test/file.swift", fileHash: "old-hash"), [0.5, 0.6, 0.7, 0.8])
        ])
        try await manager.recordIndexed(fileHash: "old-hash", path: "/test/file.swift")

        // Reindex with new chunks
        let newChunks: [(chunk: CodeChunk, vector: [Float])] = [
            (makeChunk(id: "new-1", path: "/test/file.swift", fileHash: "new-hash"), [0.1, 0.2, 0.3, 0.4])
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
    func testSemanticSearch() async throws {
        let manager = try await makeIndexManager()
        try await manager.indexBatch([
            (makeChunk(id: "sem-1", content: "authentication"), [1.0, 0.0, 0.0, 0.0]),
            (makeChunk(id: "sem-2", content: "payment"), [0.0, 1.0, 0.0, 0.0]),
            (makeChunk(id: "sem-3", content: "logging"), [0.0, 0.0, 1.0, 0.0])
        ])

        let results = try await manager.searchSemantic(
            vector: [0.9, 0.1, 0.0, 0.0],
            limit: 3
        )

        #expect(results.count == 3)
        #expect(results[0].chunk.id == "sem-1")
    }

    @Test("FTS search through manager")
    func testFTSSearch() async throws {
        let manager = try await makeIndexManager()
        try await manager.indexBatch([
            (makeChunk(id: "fts-1", content: "func authenticate(user: User) // handle authentication"), [0.1, 0.2, 0.3, 0.4]),
            (makeChunk(id: "fts-2", content: "func processPayment()"), [0.5, 0.6, 0.7, 0.8])
        ])

        let results = try await manager.searchFTS(query: "authentication", limit: 10)

        #expect(results.count >= 1)
        #expect(results[0].chunk.id == "fts-1")
    }

    @Test("Hybrid search combines semantic and FTS")
    func testHybridSearch() async throws {
        let manager = try await makeIndexManager()
        try await manager.indexBatch([
            (makeChunk(id: "hyb-1", content: "func authenticateUser(credentials: Credentials)"), [1.0, 0.0, 0.0, 0.0]),
            (makeChunk(id: "hyb-2", content: "func validateToken(token: String)"), [0.8, 0.2, 0.0, 0.0]),
            (makeChunk(id: "hyb-3", content: "func processPayment(amount: Double)"), [0.0, 1.0, 0.0, 0.0])
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
            (makeChunk(id: "stat-3", path: "/test/b.swift"), [0.9, 1.0, 1.1, 1.2])
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
            (makeChunk(id: "cons-2"), [0.5, 0.6, 0.7, 0.8])
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
            (makeChunk(id: "clr-2"), [0.5, 0.6, 0.7, 0.8])
        ])

        try await manager.clear()
        let stats = try await manager.statistics()

        #expect(stats.chunkCount == 0)
        #expect(stats.vectorCount == 0)
    }

    // MARK: - Helpers

    private func makeIndexManager() async throws -> IndexManager {
        let chunkStore = try GRDBChunkStore()
        let vectorStore = try USearchVectorStore(dimension: dimension)
        return IndexManager(chunkStore: chunkStore, vectorStore: vectorStore)
    }
}

// MARK: - Test Helpers

private func makeChunk(
    id: String,
    path: String = "/test/file.swift",
    content: String = "func testFunction() { }",
    startLine: Int = 1,
    endLine: Int = 1,
    kind: ChunkKind = .function,
    symbols: [String] = ["testFunction"],
    references: [String] = [],
    fileHash: String = "testhash123"
) -> CodeChunk {
    CodeChunk(
        id: id,
        path: path,
        content: content,
        startLine: startLine,
        endLine: endLine,
        kind: kind,
        symbols: symbols,
        references: references,
        fileHash: fileHash
    )
}
