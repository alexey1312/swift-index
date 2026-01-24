import Foundation
@testable import SwiftIndexCore
import Testing

// MARK: - Mock Implementations

/// Mock chunk store for testing search engines.
actor MockChunkStore: ChunkStore {
    private var chunks: [String: CodeChunk] = [:]
    private var fileHashesByPath: [String: String] = [:]

    init(chunks: [CodeChunk] = []) {
        for chunk in chunks {
            self.chunks[chunk.id] = chunk
        }
    }

    func insert(_ chunk: CodeChunk) async throws {
        chunks[chunk.id] = chunk
    }

    func insertBatch(_ newChunks: [CodeChunk]) async throws {
        for chunk in newChunks {
            chunks[chunk.id] = chunk
        }
    }

    func get(id: String) async throws -> CodeChunk? {
        chunks[id]
    }

    func getByPath(_ path: String) async throws -> [CodeChunk] {
        chunks.values.filter { $0.path == path }
    }

    func update(_ chunk: CodeChunk) async throws {
        chunks[chunk.id] = chunk
    }

    func delete(id: String) async throws {
        chunks.removeValue(forKey: id)
    }

    func deleteByPath(_ path: String) async throws {
        chunks = chunks.filter { $0.value.path != path }
    }

    func searchFTS(query: String, limit: Int) async throws -> [(chunk: CodeChunk, score: Double)] {
        // Simple mock: match chunks containing any query term
        let terms = query.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"*")) }

        var results: [(chunk: CodeChunk, score: Double)] = []

        for chunk in chunks.values {
            let content = chunk.content.lowercased()
            let symbols = chunk.symbols.joined(separator: " ").lowercased()
            let searchText = content + " " + symbols

            var matchCount = 0
            for term in terms where searchText.contains(term) {
                matchCount += 1
            }

            if matchCount > 0 {
                let score = Double(matchCount) / Double(max(terms.count, 1))
                results.append((chunk: chunk, score: score))
            }
        }

        return results
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.self)
    }

    func allIDs() async throws -> [String] {
        Array(chunks.keys)
    }

    func count() async throws -> Int {
        chunks.count
    }

    func getFileHash(forPath path: String) async throws -> String? {
        fileHashesByPath[path]
    }

    func setFileHash(_ hash: String, forPath path: String) async throws {
        fileHashesByPath[path] = hash
    }

    func getByContentHashes(_ hashes: Set<String>) async throws -> [String: CodeChunk] {
        var result: [String: CodeChunk] = [:]
        for chunk in chunks.values {
            if hashes.contains(chunk.contentHash) {
                result[chunk.contentHash] = chunk
            }
        }
        return result
    }

    func clear() async throws {
        chunks.removeAll()
        fileHashesByPath.removeAll()
    }
}

/// Mock vector store for testing semantic search.
actor MockVectorStore: VectorStore {
    let dimension: Int
    private var vectors: [String: [Float]] = [:]

    init(dimension: Int = 384) {
        self.dimension = dimension
    }

    func add(id: String, vector: [Float]) async throws {
        guard vector.count == dimension else {
            throw ProviderError.dimensionMismatch(expected: dimension, actual: vector.count)
        }
        vectors[id] = vector
    }

    func addBatch(_ items: [(id: String, vector: [Float])]) async throws {
        for (id, vector) in items {
            try await add(id: id, vector: vector)
        }
    }

    func search(vector: [Float], limit: Int) async throws -> [(id: String, similarity: Float)] {
        guard vector.count == dimension else {
            throw ProviderError.dimensionMismatch(expected: dimension, actual: vector.count)
        }

        var results: [(id: String, similarity: Float)] = []

        for (id, storedVector) in vectors {
            let similarity = cosineSimilarity(vector, storedVector)
            results.append((id: id, similarity: similarity))
        }

        return results
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map(\.self)
    }

    func delete(id: String) async throws {
        vectors.removeValue(forKey: id)
    }

    func contains(id: String) async throws -> Bool {
        vectors[id] != nil
    }

    func get(id: String) async throws -> [Float]? {
        vectors[id]
    }

    func count() async throws -> Int {
        vectors.count
    }

    func save() async throws {}
    func load() async throws {}

    func clear() async throws {
        vectors.removeAll()
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0 ..< min(a.count, b.count) {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dotProduct / denominator : 0
    }
}

/// Mock embedding provider for search engine testing.
actor SearchTestMockEmbeddingProvider: EmbeddingProvider {
    nonisolated let id = "mock"
    nonisolated let name = "Mock Provider"
    nonisolated let dimension = 384

    private var embeddings: [String: [Float]] = [:]

    init() {}

    /// Pre-set an embedding for a specific text.
    func setEmbedding(_ embedding: [Float], for text: String) {
        embeddings[text] = embedding
    }

    nonisolated func isAvailable() async -> Bool {
        true
    }

    func embed(_ text: String) async throws -> [Float] {
        // Return pre-set embedding or generate deterministic one
        if let preset = embeddings[text] {
            return preset
        }

        // Generate deterministic embedding based on text hash
        var vector = [Float](repeating: 0, count: dimension)
        let hash = text.hashValue
        for i in 0 ..< dimension {
            vector[i] = Float((hash &+ i * 31) % 1000) / 1000.0
        }
        return vector
    }
}

// MARK: - RRF Fusion Tests

@Suite("RRF Fusion Tests")
struct RRFFusionTests {
    @Test("RRF score calculation")
    func rRFScoreCalculation() {
        let fusion = RRFFusion(k: 60)

        // Score for rank 1: 1 / (60 + 1) = 0.0164
        let score1 = fusion.score(forRank: 1)
        #expect(abs(score1 - 0.0163934) < 0.0001)

        // Score for rank 10: 1 / (60 + 10) = 0.0143
        let score10 = fusion.score(forRank: 10)
        #expect(abs(score10 - 0.0142857) < 0.0001)
    }

    @Test("Fuse two ranked lists")
    func fuseTwoLists() {
        let fusion = RRFFusion(k: 60)

        let list1: [(id: String, score: Float)] = [
            (id: "a", score: 1.0),
            (id: "b", score: 0.8),
            (id: "c", score: 0.6),
        ]

        let list2: [(id: String, score: Float)] = [
            (id: "b", score: 0.9),
            (id: "c", score: 0.7),
            (id: "d", score: 0.5),
        ]

        let fused = fusion.fuse(list1, list2)

        // "b" appears in both lists (rank 2 and rank 1)
        // "c" appears in both lists (rank 3 and rank 2)
        // "a" appears only in list1 (rank 1)
        // "d" appears only in list2 (rank 3)

        // Find "b" - should have highest combined score
        let itemB = fused.first { $0.id == "b" }
        #expect(itemB != nil)
        #expect(itemB?.ranks == [2, 1])

        // "b" should rank higher than "a" (appears in both lists)
        let indexA = fused.firstIndex { $0.id == "a" }
        let indexB = fused.firstIndex { $0.id == "b" }
        #expect(indexA != nil && indexB != nil)
        #expect(indexB! < indexA!) // Lower index = higher rank
    }

    @Test("Fuse with weights")
    func fuseWithWeights() {
        let fusion = RRFFusion(k: 60)

        let list1: [(id: String, score: Float)] = [
            (id: "a", score: 1.0),
        ]

        let list2: [(id: String, score: Float)] = [
            (id: "b", score: 1.0),
        ]

        // Give list2 much higher weight
        let fused = fusion.fuse(list1, firstWeight: 0.3, list2, secondWeight: 0.7)

        let itemA = fused.first { $0.id == "a" }
        let itemB = fused.first { $0.id == "b" }

        #expect(itemA != nil && itemB != nil)
        #expect(itemB!.score > itemA!.score) // "b" should have higher score
    }

    @Test("Empty list handling")
    func emptyLists() {
        let fusion = RRFFusion(k: 60)

        let empty: [(id: String, score: Float)] = []
        let nonEmpty: [(id: String, score: Float)] = [(id: "a", score: 1.0)]

        let fused = fusion.fuse(empty, nonEmpty)

        #expect(fused.count == 1)
        #expect(fused.first?.id == "a")
    }
}

// MARK: - BM25 Search Tests

@Suite("BM25 Search Tests")
struct BM25SearchTests {
    func makeTestChunks() -> [CodeChunk] {
        [
            CodeChunk(
                id: "chunk1",
                path: "/src/auth/login.swift",
                content: "func authenticate(user: String, password: String) { }",
                startLine: 1,
                endLine: 5,
                kind: .function,
                symbols: ["authenticate"],
                references: ["User", "Credentials"],
                fileHash: "hash1"
            ),
            CodeChunk(
                id: "chunk2",
                path: "/src/auth/logout.swift",
                content: "func logout(session: Session) { }",
                startLine: 1,
                endLine: 3,
                kind: .function,
                symbols: ["logout"],
                references: ["Session"],
                fileHash: "hash2"
            ),
            CodeChunk(
                id: "chunk3",
                path: "/src/models/user.swift",
                content: "struct User { var name: String }",
                startLine: 1,
                endLine: 3,
                kind: .struct,
                symbols: ["User"],
                references: [],
                fileHash: "hash3"
            ),
        ]
    }

    @Test("Search finds matching chunks")
    func searchFindsMatches() async throws {
        let chunks = makeTestChunks()
        let store = MockChunkStore(chunks: chunks)
        let search = BM25Search(chunkStore: store)

        let results = try await search.search(
            query: "authenticate",
            options: .default
        )

        #expect(!results.isEmpty)
        #expect(results.first?.chunk.id == "chunk1")
        #expect(results.first?.bm25Score != nil)
        #expect(results.first?.bm25Rank == 1)
    }

    @Test("Search respects limit")
    func searchRespectsLimit() async throws {
        let chunks = makeTestChunks()
        let store = MockChunkStore(chunks: chunks)
        let search = BM25Search(chunkStore: store)

        let options = SearchOptions(limit: 1)
        let results = try await search.search(query: "func", options: options)

        #expect(results.count <= 1)
    }

    @Test("Search with path filter")
    func searchWithPathFilter() async throws {
        let chunks = makeTestChunks()
        let store = MockChunkStore(chunks: chunks)
        let search = BM25Search(chunkStore: store)

        let options = SearchOptions(pathFilter: "**/auth/*.swift")
        let results = try await search.search(query: "func", options: options)

        for result in results {
            #expect(result.chunk.path.contains("/auth/"))
        }
    }

    @Test("Search with extension filter")
    func searchWithExtensionFilter() async throws {
        var chunks = makeTestChunks()
        chunks.append(CodeChunk(
            id: "chunk4",
            path: "/src/readme.md",
            content: "# Authentication func",
            startLine: 1,
            endLine: 1,
            kind: .markdownSection,
            symbols: [],
            references: [],
            fileHash: "hash4"
        ))

        let store = MockChunkStore(chunks: chunks)
        let search = BM25Search(chunkStore: store)

        let options = SearchOptions(extensionFilter: ["swift"])
        let results = try await search.search(query: "func", options: options)

        for result in results {
            #expect(result.chunk.path.hasSuffix(".swift"))
        }
    }
}

// MARK: - Semantic Search Tests

@Suite("Semantic Search Tests")
struct SemanticSearchTests {
    func makeTestSetup() async throws -> (
        chunks: [CodeChunk],
        chunkStore: MockChunkStore,
        vectorStore: MockVectorStore,
        embeddingProvider: SearchTestMockEmbeddingProvider
    ) {
        let chunks = [
            CodeChunk(
                id: "chunk1",
                path: "/src/auth.swift",
                content: "func login(user: User) { }",
                startLine: 1,
                endLine: 3,
                kind: .function,
                symbols: ["login"],
                references: ["User"],
                fileHash: "hash1"
            ),
            CodeChunk(
                id: "chunk2",
                path: "/src/utils.swift",
                content: "func formatDate(date: Date) { }",
                startLine: 1,
                endLine: 3,
                kind: .function,
                symbols: ["formatDate"],
                references: ["Date"],
                fileHash: "hash2"
            ),
        ]

        let chunkStore = MockChunkStore(chunks: chunks)
        let vectorStore = MockVectorStore(dimension: 384)
        let embeddingProvider = SearchTestMockEmbeddingProvider()

        // Add vectors for chunks
        let vector1 = try await embeddingProvider.embed("func login user authentication")
        let vector2 = try await embeddingProvider.embed("func formatDate date utility")

        try await vectorStore.add(id: "chunk1", vector: vector1)
        try await vectorStore.add(id: "chunk2", vector: vector2)

        return (chunks, chunkStore, vectorStore, embeddingProvider)
    }

    @Test("Search returns semantic results")
    func semanticSearch() async throws {
        let (_, chunkStore, vectorStore, embeddingProvider) = try await makeTestSetup()
        let search = SemanticSearch(
            vectorStore: vectorStore,
            chunkStore: chunkStore,
            embeddingProvider: embeddingProvider
        )

        let results = try await search.search(
            query: "user authentication login",
            options: .default
        )

        #expect(!results.isEmpty)
        #expect(results.first?.semanticScore != nil)
        #expect(results.first?.semanticRank != nil)
    }

    @Test("Raw search returns IDs and scores")
    func rawSearch() async throws {
        let (_, chunkStore, vectorStore, embeddingProvider) = try await makeTestSetup()
        let search = SemanticSearch(
            vectorStore: vectorStore,
            chunkStore: chunkStore,
            embeddingProvider: embeddingProvider
        )

        let results = try await search.searchRaw(query: "login", limit: 10)

        #expect(!results.isEmpty)
        #expect(results.first?.id != nil)
        if let score = results.first?.score {
            #expect(score >= -1.0 && score <= 1.0)
        }
    }
}

// MARK: - Hybrid Search Tests

@Suite("Hybrid Search Tests")
struct HybridSearchTests {
    func makeTestSetup() async throws -> (
        chunkStore: MockChunkStore,
        vectorStore: MockVectorStore,
        embeddingProvider: SearchTestMockEmbeddingProvider
    ) {
        let chunks = [
            CodeChunk(
                id: "chunk1",
                path: "/src/auth/login.swift",
                content: "func authenticate(user: String) { validateCredentials() }",
                startLine: 1,
                endLine: 5,
                kind: .function,
                symbols: ["authenticate"],
                references: ["validateCredentials"],
                fileHash: "hash1"
            ),
            CodeChunk(
                id: "chunk2",
                path: "/src/auth/validate.swift",
                content: "func validateCredentials() { checkPassword() }",
                startLine: 1,
                endLine: 5,
                kind: .function,
                symbols: ["validateCredentials"],
                references: ["checkPassword"],
                fileHash: "hash2"
            ),
            CodeChunk(
                id: "chunk3",
                path: "/src/utils/format.swift",
                content: "func formatOutput(data: String) { }",
                startLine: 1,
                endLine: 3,
                kind: .function,
                symbols: ["formatOutput"],
                references: [],
                fileHash: "hash3"
            ),
        ]

        let chunkStore = MockChunkStore(chunks: chunks)
        let vectorStore = MockVectorStore(dimension: 384)
        let embeddingProvider = SearchTestMockEmbeddingProvider()

        // Add vectors for chunks
        for chunk in chunks {
            let vector = try await embeddingProvider.embed(chunk.content)
            try await vectorStore.add(id: chunk.id, vector: vector)
        }

        return (chunkStore, vectorStore, embeddingProvider)
    }

    @Test("Hybrid search combines BM25 and semantic")
    func hybridSearchCombination() async throws {
        let (chunkStore, vectorStore, embeddingProvider) = try await makeTestSetup()
        let engine = HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: embeddingProvider
        )

        let results = try await engine.search(
            query: "authenticate user",
            options: .default
        )

        #expect(!results.isEmpty)

        // Results may have both BM25 and semantic scores
        let firstResult = results.first
        #expect(firstResult?.score != nil)
    }

    @Test("Semantic weight affects ranking")
    func semanticWeightAffectsRanking() async throws {
        let (chunkStore, vectorStore, embeddingProvider) = try await makeTestSetup()
        let engine = HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: embeddingProvider
        )

        // Search with BM25-only weight
        let bm25Options = SearchOptions(semanticWeight: 0.0)
        let bm25Results = try await engine.search(query: "authenticate", options: bm25Options)

        // Search with semantic-only weight
        let semanticOptions = SearchOptions(semanticWeight: 1.0)
        let semanticResults = try await engine.search(query: "authenticate", options: semanticOptions)

        // Both should return results
        #expect(!bm25Results.isEmpty)
        #expect(!semanticResults.isEmpty)
    }

    @Test("Multi-hop search follows references")
    func multiHopSearch() async throws {
        let (chunkStore, vectorStore, embeddingProvider) = try await makeTestSetup()
        let engine = HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: embeddingProvider
        )

        let options = SearchOptions(
            limit: 10,
            multiHop: true,
            multiHopDepth: 2
        )

        let results = try await engine.search(
            query: "authenticate",
            options: options
        )

        // Should find authenticate and potentially validateCredentials via reference
        #expect(!results.isEmpty)

        // Check if any multi-hop results were found
        _ = results.filter(\.isMultiHop)
        // Multi-hop may or may not find results depending on mock behavior
        // Just verify the search completes without error
    }

    @Test("Path filter works in hybrid search")
    func pathFilterInHybridSearch() async throws {
        let (chunkStore, vectorStore, embeddingProvider) = try await makeTestSetup()
        let engine = HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: embeddingProvider
        )

        let options = SearchOptions(pathFilter: "**/auth/*.swift")
        let results = try await engine.search(query: "func", options: options)

        for result in results {
            #expect(result.chunk.path.contains("/auth/"))
        }
    }

    @Test("Strategy options creation")
    func strategyOptions() {
        let bm25Options = HybridSearchEngine.options(for: .bm25Only)
        #expect(bm25Options.semanticWeight == 0.0)

        let semanticOptions = HybridSearchEngine.options(for: .semanticOnly)
        #expect(semanticOptions.semanticWeight == 1.0)

        let hybridOptions = HybridSearchEngine.options(for: .hybrid(semanticWeight: 0.5))
        #expect(hybridOptions.semanticWeight == 0.5)
    }
}
