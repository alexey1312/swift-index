import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("OverlayIndexManager Tests")
struct OverlayIndexManagerTests {
    @Test("Local results override remote by path")
    func localOverridesRemoteByPath() async throws {
        let localChunk = CodeChunk(
            id: "local-1",
            path: "/project/Sources/Auth.swift",
            content: "local content",
            startLine: 1,
            endLine: 5,
            kind: .function,
            symbols: ["Auth"],
            references: [],
            fileHash: "hash-local"
        )

        let remoteChunk = CodeChunk(
            id: "remote-1",
            path: "/project/Sources/Auth.swift",
            content: "remote content",
            startLine: 1,
            endLine: 5,
            kind: .function,
            symbols: ["Auth"],
            references: [],
            fileHash: "hash-remote"
        )

        let localChunkStore = MockChunkStore(chunks: [localChunk])
        let remoteChunkStore = MockChunkStore(chunks: [remoteChunk])
        let localVectorStore = MockVectorStore()
        let remoteVectorStore = MockVectorStore()
        let embedder = SearchTestMockEmbeddingProvider()

        let engine = HybridSearchEngine(
            chunkStore: localChunkStore,
            vectorStore: localVectorStore,
            embeddingProvider: embedder,
            remoteChunkStore: remoteChunkStore,
            remoteVectorStore: remoteVectorStore,
            rrfK: 60
        )

        let results = try await engine.search(
            query: "content",
            options: SearchOptions(limit: 10, semanticWeight: 0.0)
        )

        #expect(results.count == 1)
        #expect(results.first?.chunk.id == "local-1")
    }

    @Test("Merges local and remote results with deduplication")
    func mergesResultsWithDeduplication() async throws {
        let localChunk = CodeChunk(
            id: "local-1",
            path: "/project/Sources/Local.swift",
            content: "local content",
            startLine: 1,
            endLine: 5,
            kind: .function,
            symbols: ["Local"],
            references: [],
            fileHash: "hash-local"
        )

        let remoteChunk = CodeChunk(
            id: "remote-1",
            path: "/project/Sources/Remote.swift",
            content: "remote content",
            startLine: 1,
            endLine: 5,
            kind: .function,
            symbols: ["Remote"],
            references: [],
            fileHash: "hash-remote"
        )

        let localChunkStore = MockChunkStore(chunks: [localChunk])
        let remoteChunkStore = MockChunkStore(chunks: [remoteChunk])
        let localVectorStore = MockVectorStore()
        let remoteVectorStore = MockVectorStore()
        let embedder = SearchTestMockEmbeddingProvider()

        let engine = HybridSearchEngine(
            chunkStore: localChunkStore,
            vectorStore: localVectorStore,
            embeddingProvider: embedder,
            remoteChunkStore: remoteChunkStore,
            remoteVectorStore: remoteVectorStore,
            rrfK: 60
        )

        let results = try await engine.search(
            query: "content",
            options: SearchOptions(limit: 10, semanticWeight: 0.0)
        )

        let ids = Set(results.map(\.chunk.id))
        #expect(ids == Set(["local-1", "remote-1"]))
    }
}
