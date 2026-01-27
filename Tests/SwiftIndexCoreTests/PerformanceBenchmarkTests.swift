import Foundation
import GRDB
@testable import SwiftIndexCore
import Testing

// MARK: - Benchmark Mocks

/// Mock vector store for testing semantic search.
/// Copied and adapted from SearchEngineTests.swift to ensure isolation.
actor BenchmarkMockVectorStore: VectorStore {
    let dimension: Int
    private var vectors: [String: [Float]] = [:]

    // Allow setting search results directly for benchmarking
    private var searchResultsOverride: [(id: String, similarity: Float)]?

    init(dimension: Int = 384) {
        self.dimension = dimension
    }

    func setSearchResults(_ results: [(id: String, similarity: Float)]) {
        searchResultsOverride = results
    }

    func add(id: String, vector: [Float]) async throws {
        vectors[id] = vector
    }

    func addBatch(_ items: [(id: String, vector: [Float])]) async throws {
        for (id, vector) in items {
            try await add(id: id, vector: vector)
        }
    }

    func search(vector: [Float], limit: Int) async throws -> [(id: String, similarity: Float)] {
        if let override = searchResultsOverride {
            return override.prefix(limit).map(\.self)
        }

        var results: [(id: String, similarity: Float)] = []
        for (id, _) in vectors {
            let similarity: Float = 0.8 // Dummy similarity
            results.append((id: id, similarity: similarity))
        }
        return results.prefix(limit).map(\.self)
    }

    func delete(id: String) async throws {}
    func contains(id: String) async throws -> Bool { true }
    func get(id: String) async throws -> [Float]? { vectors[id] }
    func getBatch(ids: [String]) async throws -> [String: [Float]] { [:] }
    func count() async throws -> Int { vectors.count }
    func save() async throws {}
    func load() async throws {}
    func clear() async throws {}
}

actor BenchmarkMockEmbeddingProvider: EmbeddingProvider {
    nonisolated let id = "mock"
    nonisolated let name = "Mock Provider"
    nonisolated let dimension = 384

    func isAvailable() async -> Bool { true }
    func embed(_ text: String) async throws -> [Float] {
        [Float](repeating: 0.1, count: dimension)
    }
}

// MARK: - Performance Benchmark

@Suite("Performance Benchmark Tests")
struct PerformanceBenchmarkTests {
    @Test("Measure N+1 Query Performance", .tags(.benchmark))
    func measureNPlus1QueryPerformance() async throws {
        // Setup in-memory DB
        let chunkStore = try GRDBChunkStore()

        // Insert chunks
        let chunkCount = 5000
        print("Generating \(chunkCount) chunks...")

        var chunks: [CodeChunk] = []
        for i in 0 ..< chunkCount {
            chunks.append(makeChunk(
                id: "chunk_\(i)",
                path: "/src/file_\(i).swift",
                content: "func function_\(i)() {}",
                kind: .function
            ))
        }

        try await chunkStore.insertBatch(chunks)
        print("Inserted \(chunkCount) chunks.")

        // Prepare vector store results
        let vectorStore = BenchmarkMockVectorStore()
        let searchResults = (0 ..< chunkCount).map { i in
            (id: "chunk_\(i)", similarity: Float.random(in: 0.5 ... 1.0))
        }
        await vectorStore.setSearchResults(searchResults)

        let embeddingProvider = BenchmarkMockEmbeddingProvider()

        let engine = SemanticSearch(
            vectorStore: vectorStore,
            chunkStore: chunkStore,
            embeddingProvider: embeddingProvider
        )

        let options = SearchOptions(limit: chunkCount) // Fetch all

        print("Starting benchmark...")
        let clock = ContinuousClock()
        let result = try await clock.measure {
            _ = try await engine.search(query: "test", options: options)
        }

        print("Search took: \(result)")
    }
}

// Helper to define benchmark tag if not exists
extension Tag {
    @available(macOS 13.0, *)
    @Tag static var benchmark: Tag
}
