import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("Overlay Search Performance")
struct OverlayPerformanceTests {
    @Test("Overlay search stays under 200ms", .tags(.benchmark))
    func overlaySearchPerformance() async throws {
        let localStore = MockChunkStore()
        let remoteStore = MockChunkStore()
        let localVectorStore = MockVectorStore(dimension: 384)
        let remoteVectorStore = MockVectorStore(dimension: 384)
        let embeddingProvider = SearchTestMockEmbeddingProvider()

        let total = 800
        for i in 0 ..< total {
            let localChunk = CodeChunk(
                id: "local-\(i)",
                path: "/project/Sources/Local\(i).swift",
                content: "local content \(i)",
                startLine: 1,
                endLine: 2,
                kind: .function,
                symbols: ["Local\(i)"],
                references: [],
                fileHash: "local"
            )
            let remoteChunk = CodeChunk(
                id: "remote-\(i)",
                path: "/project/Sources/Remote\(i).swift",
                content: "remote content \(i)",
                startLine: 1,
                endLine: 2,
                kind: .function,
                symbols: ["Remote\(i)"],
                references: [],
                fileHash: "remote"
            )

            try await localStore.insert(localChunk)
            try await remoteStore.insert(remoteChunk)
            let vector = [Float](repeating: 0.1, count: 384)
            try await localVectorStore.add(id: localChunk.id, vector: vector)
            try await remoteVectorStore.add(id: remoteChunk.id, vector: vector)
        }

        let engine = HybridSearchEngine(
            chunkStore: localStore,
            vectorStore: localVectorStore,
            embeddingProvider: embeddingProvider,
            remoteChunkStore: remoteStore,
            remoteVectorStore: remoteVectorStore
        )

        let clock = ContinuousClock()
        let duration = try await clock.measure {
            _ = try await engine.search(
                query: "content",
                options: SearchOptions(limit: 20, semanticWeight: 0.5)
            )
        }

        #expect(duration < .milliseconds(200))
    }
}

private extension Tag {
    @available(macOS 13.0, *)
    @Tag static var benchmark: Tag
}
