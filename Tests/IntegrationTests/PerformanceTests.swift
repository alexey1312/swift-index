import Foundation
import Testing

@testable import SwiftIndexCore

/// Performance tests for SwiftIndex components.
///
/// These tests measure and benchmark:
/// - Parser throughput
/// - Search latency
/// - Indexing throughput
/// - Vector operations
@Suite("Performance Tests")
struct PerformanceTests {
    // MARK: - Test Fixtures

    /// Sample Swift code for parsing benchmarks.
    private let sampleCode = """
    import Foundation

    /// Represents a user in the system with authentication capabilities.
    struct User: Identifiable, Codable, Sendable {
        let id: UUID
        var name: String
        var email: String
        var createdAt: Date
        var preferences: [String: String]

        /// Creates a new user with the given details.
        init(name: String, email: String) {
            self.id = UUID()
            self.name = name
            self.email = email
            self.createdAt = Date()
            self.preferences = [:]
        }

        /// Validates the user's email format using regex.
        func isValidEmail() -> Bool {
            let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\\\.[A-Za-z]{2,64}"
            return email.range(of: pattern, options: .regularExpression) != nil
        }

        /// Updates user preferences with new values.
        mutating func updatePreferences(_ newPrefs: [String: String]) {
            for (key, value) in newPrefs {
                preferences[key] = value
            }
        }
    }

    /// Service handling user authentication.
    actor AuthenticationService {
        private var currentUser: User?
        private var authToken: String?
        private var tokenExpiry: Date?

        /// Authenticates a user with email and password.
        func login(email: String, password: String) async throws -> User {
            guard !email.isEmpty, !password.isEmpty else {
                throw AuthError.invalidCredentials
            }

            // Simulate network call
            try await Task.sleep(nanoseconds: 1_000_000)

            let user = User(name: "Test User", email: email)
            self.currentUser = user
            self.authToken = UUID().uuidString
            self.tokenExpiry = Date().addingTimeInterval(3600)

            return user
        }

        /// Logs out the current user.
        func logout() {
            currentUser = nil
            authToken = nil
            tokenExpiry = nil
        }

        /// Returns the currently authenticated user.
        func getCurrentUser() -> User? {
            return currentUser
        }

        /// Checks if the current session is valid.
        func isSessionValid() -> Bool {
            guard let expiry = tokenExpiry else { return false }
            return Date() < expiry
        }
    }

    /// Authentication errors.
    enum AuthError: Error {
        case invalidCredentials
        case sessionExpired
        case networkError(String)
    }

    /// Protocol for network operations.
    protocol NetworkClient {
        func fetch<T: Decodable>(_ url: URL) async throws -> T
        func post<T: Encodable, R: Decodable>(_ url: URL, body: T) async throws -> R
    }
    """

    // MARK: - Parser Performance Tests

    @Test("Parser throughput - single file")
    func parserThroughputSingleFile() throws {
        let parser = HybridParser()
        let iterations = 100

        let startTime = CFAbsoluteTimeGetCurrent()

        for _ in 0 ..< iterations {
            let result = parser.parse(content: sampleCode, path: "User.swift")
            guard case let .success(chunks) = result else {
                Issue.record("Parser should succeed")
                return
            }
            #expect(!chunks.isEmpty)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let throughput = Double(iterations) / elapsed

        // Log performance metrics
        print("Parser throughput: \(String(format: "%.1f", throughput)) files/sec")
        print("Average parse time: \(String(format: "%.2f", elapsed / Double(iterations) * 1000)) ms")

        // Ensure reasonable performance (at least 10 files/second in debug builds)
        // Relaxed threshold for CI due to variable runner performance
        let isCI = {
            let value = ProcessInfo.processInfo.environment["CI"]?.lowercased()
            return value == "1" || value == "true" || value == "yes"
        }()
        let minimumThroughput = isCI ? 5.0 : 10.0
        #expect(throughput > minimumThroughput, "Parser should process at least \(minimumThroughput) files/second")
    }

    @Test("Parser throughput - large file")
    func parserThroughputLargeFile() throws {
        let parser = HybridParser()

        // Generate a large file by repeating the sample code
        var largeCode = ""
        for i in 0 ..< 50 {
            largeCode += sampleCode.replacingOccurrences(of: "User", with: "User\(i)")
            largeCode += "\n\n"
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        let result = parser.parse(content: largeCode, path: "LargeFile.swift")

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        guard case let .success(chunks) = result else {
            Issue.record("Parser should succeed for large file")
            return
        }

        print("Large file parsing: \(chunks.count) chunks in \(String(format: "%.2f", elapsed * 1000)) ms")
        print("Code size: \(largeCode.count) characters")

        // Should parse large files in reasonable time (under 180 seconds for 50x repeated code in debug builds)
        #expect(elapsed < 180, "Large file should parse in under 180 seconds")
        #expect(chunks.count >= 100, "Should extract many chunks from large file")
    }

    // MARK: - Indexing Performance Tests

    @Test("Indexing throughput with mock embeddings")
    func indexingThroughput() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftindex-perf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storageDir = tempDir.appendingPathComponent(".swiftindex").path
        let indexManager = try IndexManager(directory: storageDir, dimension: 384)
        let mockProvider = MockEmbeddingProvider(dimension: 384)
        let parser = HybridParser()

        // Parse sample code
        let result = parser.parse(content: sampleCode, path: "User.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Parser should succeed")
            return
        }

        // Measure indexing throughput
        let iterations = 100
        var totalChunks = 0

        let startTime = CFAbsoluteTimeGetCurrent()

        for i in 0 ..< iterations {
            for chunk in chunks {
                // Create unique chunk for each iteration
                let uniqueChunk = CodeChunk(
                    id: "\(chunk.id)-\(i)",
                    path: "User\(i).swift",
                    content: chunk.content,
                    startLine: chunk.startLine,
                    endLine: chunk.endLine,
                    kind: chunk.kind,
                    symbols: chunk.symbols,
                    references: chunk.references,
                    fileHash: chunk.fileHash
                )

                let embedding = try await mockProvider.embed(uniqueChunk.content)
                try await indexManager.index(chunk: uniqueChunk, vector: embedding)
                totalChunks += 1
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let throughput = Double(totalChunks) / elapsed

        print("Indexing throughput: \(String(format: "%.1f", throughput)) chunks/sec")
        print("Total chunks indexed: \(totalChunks)")
        print("Total time: \(String(format: "%.2f", elapsed)) seconds")

        let isCI = ProcessInfo.processInfo.environment["CI"] == "true"
        let minimumThroughput = isCI ? 30.0 : 50.0

        // Should index at least 50 chunks/second with mock embeddings (relaxed for CI)
        #expect(throughput > minimumThroughput, "Should index at least \(minimumThroughput) chunks/second")
    }

    @Test("Batch indexing performance")
    func batchIndexingPerformance() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftindex-perf-batch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storageDir = tempDir.appendingPathComponent(".swiftindex").path
        let indexManager = try IndexManager(directory: storageDir, dimension: 384)
        let mockProvider = MockEmbeddingProvider(dimension: 384)
        let parser = HybridParser()

        // Parse sample code
        let result = parser.parse(content: sampleCode, path: "User.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Parser should succeed")
            return
        }

        // Create batch of items
        var batch: [(chunk: CodeChunk, vector: [Float])] = []
        let batchSize = 1000

        for i in 0 ..< batchSize {
            let baseChunk = chunks[i % chunks.count]
            let uniqueChunk = CodeChunk(
                id: "batch-\(i)",
                path: "File\(i).swift",
                content: baseChunk.content,
                startLine: baseChunk.startLine,
                endLine: baseChunk.endLine,
                kind: baseChunk.kind,
                symbols: baseChunk.symbols,
                references: baseChunk.references,
                fileHash: baseChunk.fileHash
            )
            let embedding = try await mockProvider.embed(uniqueChunk.content)
            batch.append((chunk: uniqueChunk, vector: embedding))
        }

        // Measure batch indexing
        let startTime = CFAbsoluteTimeGetCurrent()
        try await indexManager.indexBatch(batch)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        let throughput = Double(batchSize) / elapsed

        print("Batch indexing throughput: \(String(format: "%.1f", throughput)) chunks/sec")
        print("Batch size: \(batchSize)")
        print("Total time: \(String(format: "%.2f", elapsed)) seconds")

        // Batch should be reasonably fast in debug builds (relaxed for CI)
        let isCI = {
            let value = ProcessInfo.processInfo.environment["CI"]?.lowercased()
            return value == "1" || value == "true" || value == "yes"
        }()
        let minThroughput = isCI ? 50.0 : 100.0
        #expect(
            throughput > minThroughput,
            "Batch indexing should be at least \(Int(minThroughput)) chunks/second"
        )
    }

    // MARK: - Search Performance Tests

    @Test("Search latency with indexed data")
    func searchLatency() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftindex-perf-search-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storageDir = tempDir.appendingPathComponent(".swiftindex").path
        let indexManager = try IndexManager(directory: storageDir, dimension: 384)
        let mockProvider = MockEmbeddingProvider(dimension: 384)
        let parser = HybridParser()

        // Index sample data
        let result = parser.parse(content: sampleCode, path: "User.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Parser should succeed")
            return
        }

        // Index 500 unique chunks
        for i in 0 ..< 500 {
            let baseChunk = chunks[i % chunks.count]
            let uniqueChunk = CodeChunk(
                id: "search-\(i)",
                path: "File\(i).swift",
                content: baseChunk.content + " variant \(i)",
                startLine: baseChunk.startLine,
                endLine: baseChunk.endLine,
                kind: baseChunk.kind,
                symbols: baseChunk.symbols,
                references: baseChunk.references,
                fileHash: baseChunk.fileHash
            )
            let embedding = try await mockProvider.embed(uniqueChunk.content)
            try await indexManager.index(chunk: uniqueChunk, vector: embedding)
        }

        let chunkStore = await indexManager.chunkStore
        let vectorStore = await indexManager.vectorStore

        let searchEngine = HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: mockProvider
        )

        // Measure search latency
        let queries = [
            "user authentication",
            "login function",
            "email validation",
            "error handling",
            "network request",
        ]

        var totalLatency: Double = 0
        let iterations = 20

        for _ in 0 ..< iterations {
            for query in queries {
                let startTime = CFAbsoluteTimeGetCurrent()
                let results = try await searchEngine.search(
                    query: query,
                    options: SearchOptions(limit: 10)
                )
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                totalLatency += elapsed

                #expect(!results.isEmpty, "Search should return results")
            }
        }

        let averageLatency = totalLatency / Double(iterations * queries.count)

        print("Average search latency: \(String(format: "%.2f", averageLatency * 1000)) ms")
        print("Total searches: \(iterations * queries.count)")

        // Search should be fast (under 100ms average, relaxed for CI)
        #expect(averageLatency < 0.1, "Average search latency should be under 100ms")
    }

    @Test("BM25 FTS search performance")
    func bM25SearchPerformance() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftindex-perf-bm25-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storageDir = tempDir.appendingPathComponent(".swiftindex").path
        let indexManager = try IndexManager(directory: storageDir, dimension: 384)
        let mockProvider = MockEmbeddingProvider(dimension: 384)
        let parser = HybridParser()

        // Index sample data
        let result = parser.parse(content: sampleCode, path: "User.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Parser should succeed")
            return
        }

        // Index 1000 unique chunks
        for i in 0 ..< 1000 {
            let baseChunk = chunks[i % chunks.count]
            let uniqueChunk = CodeChunk(
                id: "bm25-\(i)",
                path: "File\(i).swift",
                content: baseChunk.content + " variant \(i)",
                startLine: baseChunk.startLine,
                endLine: baseChunk.endLine,
                kind: baseChunk.kind,
                symbols: baseChunk.symbols,
                references: baseChunk.references,
                fileHash: baseChunk.fileHash
            )
            let embedding = try await mockProvider.embed(uniqueChunk.content)
            try await indexManager.index(chunk: uniqueChunk, vector: embedding)
        }

        let chunkStore = await indexManager.chunkStore

        // Measure BM25 search latency
        let queries = ["authentication", "user", "email", "error", "network"]
        var totalLatency: Double = 0
        let iterations = 50

        for _ in 0 ..< iterations {
            for query in queries {
                let startTime = CFAbsoluteTimeGetCurrent()
                let results = try await chunkStore.searchFTS(query: query, limit: 10)
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                totalLatency += elapsed

                #expect(!results.isEmpty, "FTS should return results for '\(query)'")
            }
        }

        let averageLatency = totalLatency / Double(iterations * queries.count)

        print("Average BM25 search latency: \(String(format: "%.2f", averageLatency * 1000)) ms")
        print("Total searches: \(iterations * queries.count)")

        // BM25 should be very fast (under 10ms)
        #expect(averageLatency < 0.01, "BM25 search should be under 10ms")
    }

    // MARK: - Vector Store Performance Tests

    @Test("Vector similarity search performance")
    func vectorSearchPerformance() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftindex-perf-vector-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let vectorPath = tempDir.appendingPathComponent("vectors.usearch").path
        let vectorStore = try USearchVectorStore(dimension: 384, path: vectorPath)
        let mockProvider = MockEmbeddingProvider(dimension: 384)

        // Add vectors
        let vectorCount = 5000

        for i in 0 ..< vectorCount {
            let text = "Sample text for embedding \(i) with some variation"
            let embedding = try await mockProvider.embed(text)
            try await vectorStore.add(id: "vec-\(i)", vector: embedding)
        }

        // Measure search latency
        let iterations = 100
        var totalLatency: Double = 0

        for i in 0 ..< iterations {
            let queryVector = try await mockProvider.embed("Query text \(i)")
            let startTime = CFAbsoluteTimeGetCurrent()
            let results = try await vectorStore.search(vector: queryVector, limit: 10)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            totalLatency += elapsed

            #expect(results.count == 10, "Should return exactly 10 results")
        }

        let averageLatency = totalLatency / Double(iterations)

        print("Average vector search latency: \(String(format: "%.2f", averageLatency * 1000)) ms")
        print("Vector count: \(vectorCount)")
        print("Total searches: \(iterations)")

        // Vector search with 5000 vectors should be fast (under 5ms)
        #expect(averageLatency < 0.005, "Vector search should be under 5ms for 5000 vectors")
    }

    // MARK: - Memory Performance Tests

    @Test("Memory usage for large index")
    func memoryUsageForLargeIndex() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftindex-perf-memory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storageDir = tempDir.appendingPathComponent(".swiftindex").path
        let indexManager = try IndexManager(directory: storageDir, dimension: 384)
        let mockProvider = MockEmbeddingProvider(dimension: 384)
        let parser = HybridParser()

        // Parse sample code
        let result = parser.parse(content: sampleCode, path: "User.swift")
        guard case let .success(chunks) = result else {
            Issue.record("Parser should succeed")
            return
        }

        // Index 2000 unique chunks
        let itemCount = 2000
        var batch: [(chunk: CodeChunk, vector: [Float])] = []

        for i in 0 ..< itemCount {
            let baseChunk = chunks[i % chunks.count]
            let uniqueChunk = CodeChunk(
                id: "memory-\(i)",
                path: "File\(i / 10).swift",
                content: baseChunk.content,
                startLine: baseChunk.startLine,
                endLine: baseChunk.endLine,
                kind: baseChunk.kind,
                symbols: baseChunk.symbols,
                references: baseChunk.references,
                fileHash: baseChunk.fileHash
            )
            let embedding = try await mockProvider.embed(uniqueChunk.content)
            batch.append((chunk: uniqueChunk, vector: embedding))
        }

        try await indexManager.indexBatch(batch)

        // Verify index integrity
        let stats = try await indexManager.statistics()

        print("Indexed chunks: \(stats.chunkCount)")
        print("Indexed vectors: \(stats.vectorCount)")
        print("Indexed files: \(stats.fileCount)")
        print("Is consistent: \(stats.isConsistent)")

        #expect(stats.chunkCount == itemCount, "Should have indexed all chunks")
        #expect(stats.vectorCount == itemCount, "Should have indexed all vectors")
        #expect(stats.isConsistent, "Index should be consistent")
    }
}

// MARK: - Test Helpers

/// Mock embedding provider for performance tests.
private final class MockEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    let id = "mock-perf"
    let name = "Mock Performance Provider"
    let dimension: Int

    init(dimension: Int) {
        self.dimension = dimension
    }

    func isAvailable() async -> Bool {
        true
    }

    func embed(_ text: String) async throws -> [Float] {
        // Generate deterministic embedding based on text hash
        var generator = SeededRNG(seed: UInt64(bitPattern: Int64(text.hashValue)))
        var embedding = (0 ..< dimension).map { _ in Float.random(in: -1 ... 1, using: &generator) }

        // Normalize
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            embedding = embedding.map { $0 / norm }
        }

        return embedding
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        for text in texts {
            try await results.append(embed(text))
        }
        return results
    }
}

/// Seeded random number generator for deterministic tests.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
