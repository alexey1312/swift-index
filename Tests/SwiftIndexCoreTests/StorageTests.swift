import Foundation
@testable import SwiftIndexCore
import Testing

// MARK: - GRDBChunkStore Tests

@Suite("GRDBChunkStore Tests")
struct GRDBChunkStoreTests {
    // MARK: - Basic CRUD

    @Test("Insert and retrieve chunk")
    func insertAndRetrieve() async throws {
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
            makeChunk(id: "batch-3", path: "/test/file3.swift"),
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
            makeChunk(id: "path-3", path: "/test/other.swift", startLine: 1),
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
    func deleteByID() async throws {
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
            makeChunk(id: "del-path-3", path: "/test/keep.swift"),
        ])

        try await store.deleteByPath("/test/delete.swift")
        let remaining = try await store.count()

        #expect(remaining == 1)
    }

    // MARK: - Rich Metadata Tests

    @Test("Store and retrieve chunk with docComment")
    func storeAndRetrieveDocComment() async throws {
        let store = try GRDBChunkStore()
        let chunk = makeChunk(
            id: "doc-1",
            docComment: "Authenticates the user with given credentials.",
            signature: "func authenticate(user: String) -> Bool"
        )

        try await store.insert(chunk)
        let retrieved = try await store.get(id: "doc-1")

        #expect(retrieved != nil)
        #expect(retrieved?.docComment == "Authenticates the user with given credentials.")
        #expect(retrieved?.signature == "func authenticate(user: String) -> Bool")
    }

    @Test("Store and retrieve chunk with breadcrumb")
    func storeAndRetrieveBreadcrumb() async throws {
        let store = try GRDBChunkStore()
        let chunk = makeChunk(
            id: "bread-1",
            breadcrumb: "AuthManager > authenticate"
        )

        try await store.insert(chunk)
        let retrieved = try await store.get(id: "bread-1")

        #expect(retrieved != nil)
        #expect(retrieved?.breadcrumb == "AuthManager > authenticate")
    }

    @Test("Store and retrieve chunk with tokenCount and language")
    func storeAndRetrieveTokenCountAndLanguage() async throws {
        let store = try GRDBChunkStore()
        let content = "func test() { let x = 1 }"
        let chunk = CodeChunk(
            id: "token-1",
            path: "/test/file.swift",
            content: content,
            startLine: 1,
            endLine: 1,
            kind: .function,
            symbols: ["test"],
            references: [],
            fileHash: "hash123",
            language: "swift"
        )

        try await store.insert(chunk)
        let retrieved = try await store.get(id: "token-1")

        #expect(retrieved != nil)
        #expect(retrieved?.tokenCount == content.count / 4)
        #expect(retrieved?.language == "swift")
    }

    @Test("Batch insert preserves rich metadata")
    func batchInsertPreservesRichMetadata() async throws {
        let store = try GRDBChunkStore()
        let chunks = [
            makeChunk(
                id: "meta-1",
                docComment: "First function doc",
                signature: "func first()",
                breadcrumb: "Class > first",
                language: "swift"
            ),
            makeChunk(
                id: "meta-2",
                docComment: "Second function doc",
                signature: "func second()",
                breadcrumb: "Class > second",
                language: "swift"
            ),
        ]

        try await store.insertBatch(chunks)

        let retrieved1 = try await store.get(id: "meta-1")
        let retrieved2 = try await store.get(id: "meta-2")

        #expect(retrieved1?.docComment == "First function doc")
        #expect(retrieved1?.breadcrumb == "Class > first")
        #expect(retrieved2?.docComment == "Second function doc")
        #expect(retrieved2?.breadcrumb == "Class > second")
    }

    @Test("Update preserves rich metadata")
    func updatePreservesRichMetadata() async throws {
        let store = try GRDBChunkStore()
        let original = makeChunk(
            id: "update-meta-1",
            docComment: "Original doc",
            signature: "func original()"
        )
        try await store.insert(original)

        let updated = CodeChunk(
            id: "update-meta-1",
            path: original.path,
            content: "func updated() {}",
            startLine: original.startLine,
            endLine: original.endLine,
            kind: original.kind,
            symbols: ["updated"],
            references: [],
            fileHash: original.fileHash,
            docComment: "Updated doc comment",
            signature: "func updated()",
            breadcrumb: "NewClass > updated"
        )

        try await store.update(updated)
        let retrieved = try await store.get(id: "update-meta-1")

        #expect(retrieved?.docComment == "Updated doc comment")
        #expect(retrieved?.signature == "func updated()")
        #expect(retrieved?.breadcrumb == "NewClass > updated")
    }

    // MARK: - FTS Search

    @Test("FTS search finds matching content")
    func fTSSearch() async throws {
        let store = try GRDBChunkStore()
        try await store.insertBatch([
            makeChunk(id: "fts-1", content: "func authenticate(user: User) { }"),
            makeChunk(id: "fts-2", content: "func validatePassword(password: String) { }"),
            makeChunk(id: "fts-3", content: "struct UserProfile { var name: String }"),
        ])

        let results = try await store.searchFTS(query: "authenticate", limit: 10)

        #expect(results.count >= 1)
        #expect(results[0].chunk.id == "fts-1")
        #expect(results[0].score > 0)
    }

    @Test("FTS search with multiple terms")
    func fTSMultipleTerms() async throws {
        let store = try GRDBChunkStore()
        try await store.insertBatch([
            makeChunk(id: "multi-1", content: "func handleLogin(username: String, password: String)"),
            makeChunk(id: "multi-2", content: "func processPayment(amount: Double)"),
            makeChunk(id: "multi-3", content: "func validatePassword(password: String) // verify password"),
        ])

        let results = try await store.searchFTS(query: "password", limit: 10)

        // FTS5 finds chunks containing "password" as a word token
        #expect(results.count >= 2)
    }

    @Test("FTS search returns empty for no matches")
    func fTSNoMatches() async throws {
        let store = try GRDBChunkStore()
        try await store.insert(makeChunk(id: "no-match", content: "func doSomething()"))

        let results = try await store.searchFTS(query: "nonexistent", limit: 10)

        #expect(results.isEmpty)
    }

    @Test("FTS search finds matching docComment")
    func fTSSearchDocComment() async throws {
        let store = try GRDBChunkStore()
        try await store.insertBatch([
            makeChunk(
                id: "doc-search-1",
                content: "func processData() { }",
                docComment: "Authenticates the user with OAuth2 credentials"
            ),
            makeChunk(
                id: "doc-search-2",
                content: "func validateToken() { }",
                docComment: "Validates a JWT token"
            ),
        ])

        let results = try await store.searchFTS(query: "OAuth2", limit: 10)

        #expect(results.count >= 1)
        #expect(results[0].chunk.id == "doc-search-1")
    }

    // MARK: - File Hash Tracking

    @Test("Record and check file hash")
    func fileHashTracking() async throws {
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
            makeChunk(id: "id-3"),
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
            makeChunk(id: "paths-3", path: "/test/b.swift"),
        ])

        let paths = try await store.allPaths()

        #expect(Set(paths) == Set(["/test/a.swift", "/test/b.swift"]))
    }

    @Test("Clear store")
    func testClear() async throws {
        let store = try GRDBChunkStore()
        try await store.insertBatch([
            makeChunk(id: "clear-1"),
            makeChunk(id: "clear-2"),
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
            makeChunk(id: "byid-3"),
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
    func addAndContains() async throws {
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
            ("batch-3", [0.9, 1.0, 1.1, 1.2]),
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
            ("other", [0.0, 0.0, 1.0, 0.0]),
        ])

        // Search for vector similar to "similar"
        let results = try await store.search(vector: [0.9, 0.1, 0.0, 0.0], limit: 3)

        #expect(results.count == 3)
        #expect(results[0].id == "similar")
        #expect(results[0].similarity > results[1].similarity)
    }

    @Test("Search with minimum similarity threshold")
    func searchWithThreshold() async throws {
        let store = try USearchVectorStore(dimension: dimension)

        try await store.addBatch([
            ("close", [1.0, 0.0, 0.0, 0.0]),
            ("far", [0.0, 1.0, 0.0, 0.0]),
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
    func updateVector() async throws {
        let store = try USearchVectorStore(dimension: dimension)
        try await store.add(id: "update-1", vector: [0.1, 0.2, 0.3, 0.4])

        // Re-add with same ID should update
        try await store.add(id: "update-1", vector: [0.5, 0.6, 0.7, 0.8])
        let count = try await store.count()

        #expect(count == 1)
    }

    // MARK: - Dimension Validation

    @Test("Throws on dimension mismatch")
    func dimensionMismatch() async throws {
        let store = try USearchVectorStore(dimension: dimension)

        await #expect(throws: VectorStoreError.self) {
            try await store.add(id: "bad", vector: [0.1, 0.2]) // Wrong dimension
        }
    }

    @Test("Search throws on dimension mismatch")
    func searchDimensionMismatch() async throws {
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
            ("id-2", [0.5, 0.6, 0.7, 0.8]),
        ])

        let ids = try await store.allIDs()

        #expect(Set(ids) == Set(["id-1", "id-2"]))
    }

    @Test("Clear store")
    func testClear() async throws {
        let store = try USearchVectorStore(dimension: dimension)
        try await store.addBatch([
            ("clear-1", [0.1, 0.2, 0.3, 0.4]),
            ("clear-2", [0.5, 0.6, 0.7, 0.8]),
        ])

        try await store.clear()
        let count = try await store.count()

        #expect(count == 0)
    }

    @Test("Search on empty store returns empty")
    func searchEmpty() async throws {
        let store = try USearchVectorStore(dimension: dimension)

        let results = try await store.search(vector: [0.1, 0.2, 0.3, 0.4], limit: 10)

        #expect(results.isEmpty)
    }

    @Test("Get vector by ID")
    func getVector() async throws {
        let store = try USearchVectorStore(dimension: dimension)
        let originalVector: [Float] = [0.1, 0.2, 0.3, 0.4]

        try await store.add(id: "get-1", vector: originalVector)
        let retrieved = try await store.get(id: "get-1")

        #expect(retrieved != nil)
        #expect(retrieved?.count == dimension)
        // Vectors should be approximately equal (floating point comparison)
        if let retrieved {
            for (a, b) in zip(retrieved, originalVector) {
                #expect(abs(a - b) < 0.001)
            }
        }
    }

    @Test("Get vector returns nil for non-existent ID")
    func getVectorNonExistent() async throws {
        let store = try USearchVectorStore(dimension: dimension)

        let retrieved = try await store.get(id: "non-existent")

        #expect(retrieved == nil)
    }
}
