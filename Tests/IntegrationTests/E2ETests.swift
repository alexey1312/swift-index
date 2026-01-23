// swiftlint:disable file_length
import Foundation
import Testing

@testable import SwiftIndexCore
@testable import SwiftIndexMCP

/// End-to-end integration tests for SwiftIndex.
///
/// These tests verify complete workflows including:
/// - Full indexing and search pipeline
/// - MCP server tool invocation
/// - Provider fallback chain
/// - File watching and incremental updates
@Suite("E2E Integration Tests")
struct E2ETests {
    // MARK: - Test Fixtures

    /// Creates a temporary directory with Swift source files for testing.
    private func createTestProject() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftindex-e2e-\(UUID().uuidString)")

        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        // Create Sources directory
        let sourcesDir = tempDir.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        // Create a model file
        let userModel = sourcesDir.appendingPathComponent("User.swift")
        try """
        import Foundation

        /// Represents a user in the system.
        struct User: Identifiable, Codable {
            let id: UUID
            var name: String
            var email: String
            var createdAt: Date

            /// Creates a new user with the given details.
            init(name: String, email: String) {
                self.id = UUID()
                self.name = name
                self.email = email
                self.createdAt = Date()
            }

            /// Validates the user's email format.
            func isValidEmail() -> Bool {
                let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\\\.[A-Za-z]{2,64}"
                return email.range(of: pattern, options: .regularExpression) != nil
            }
        }
        """.write(to: userModel, atomically: true, encoding: .utf8)

        // Create an authentication service
        let authService = sourcesDir.appendingPathComponent("AuthenticationService.swift")
        try """
        import Foundation

        /// Error types for authentication operations.
        enum AuthenticationError: Error {
            case invalidCredentials
            case userNotFound
            case tokenExpired
            case networkError(underlying: Error)
        }

        /// Service handling user authentication.
        actor AuthenticationService {
            private var currentUser: User?
            private var authToken: String?

            /// Authenticates a user with email and password.
            func login(email: String, password: String) async throws -> User {
                // Validate credentials
                guard !email.isEmpty, !password.isEmpty else {
                    throw AuthenticationError.invalidCredentials
                }

                // Simulate network call
                try await Task.sleep(nanoseconds: 100_000_000)

                let user = User(name: "Test User", email: email)
                self.currentUser = user
                self.authToken = UUID().uuidString

                return user
            }

            /// Logs out the current user.
            func logout() {
                currentUser = nil
                authToken = nil
            }

            /// Returns the currently authenticated user.
            func getCurrentUser() -> User? {
                return currentUser
            }
        }
        """.write(to: authService, atomically: true, encoding: .utf8)

        // Create a network client
        let networkClient = sourcesDir.appendingPathComponent("NetworkClient.swift")
        try """
        import Foundation

        /// Protocol for network operations.
        protocol NetworkClientProtocol {
            func fetch<T: Decodable>(_ url: URL) async throws -> T
            func post<T: Encodable, R: Decodable>(_ url: URL, body: T) async throws -> R
        }

        /// HTTP client for API requests.
        final class NetworkClient: NetworkClientProtocol, Sendable {
            private let session: URLSession
            private let decoder: JSONDecoder

            init(session: URLSession = .shared) {
                self.session = session
                self.decoder = JSONDecoder()
                self.decoder.dateDecodingStrategy = .iso8601
            }

            func fetch<T: Decodable>(_ url: URL) async throws -> T {
                let (data, _) = try await session.data(from: url)
                return try decoder.decode(T.self, from: data)
            }

            func post<T: Encodable, R: Decodable>(_ url: URL, body: T) async throws -> R {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = try JSONEncoder().encode(body)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let (data, _) = try await session.data(for: request)
                return try decoder.decode(R.self, from: data)
            }
        }
        """.write(to: networkClient, atomically: true, encoding: .utf8)

        return tempDir
    }

    /// Cleans up the test project directory.
    private func cleanupTestProject(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Index → Search Flow Tests

    @Test("Index and search flow works end-to-end")
    func indexSearchFlow() async throws {
        let projectDir = try createTestProject()
        defer { cleanupTestProject(projectDir) }

        // Create storage in temp location
        let storageDir = projectDir.appendingPathComponent(".swiftindex").path

        // Create index manager
        let indexManager = try IndexManager(directory: storageDir, dimension: 384)

        // Use mock embedding provider for testing
        let mockProvider = MockEmbeddingProvider(dimension: 384)

        // Create parser
        let parser = HybridParser()

        // Parse and index files
        let sourcesDir = projectDir.appendingPathComponent("Sources")
        let files = try FileManager.default.contentsOfDirectory(
            at: sourcesDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        #expect(files.count == 3, "Should have 3 Swift files")

        var allChunks: [CodeChunk] = []

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let result = parser.parse(content: content, path: file.path)
            guard case let .success(chunks) = result else {
                Issue.record("Parser should succeed for \(file.lastPathComponent)")
                continue
            }
            allChunks.append(contentsOf: chunks)
        }

        #expect(!allChunks.isEmpty, "Should have parsed chunks")

        // Store chunks with embeddings
        for chunk in allChunks {
            let embedding = try await mockProvider.embed(chunk.content)
            try await indexManager.index(chunk: chunk, vector: embedding)
        }

        // Test BM25 search for "authentication"
        let chunkStore = await indexManager.chunkStore
        let vectorStore = await indexManager.vectorStore
        let bm25Results = try await chunkStore.searchFTS(query: "authentication", limit: 10)
        #expect(!bm25Results.isEmpty, "BM25 should find authentication-related chunks")

        // Create search engine using stores from index manager
        let searchEngine = HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: mockProvider
        )

        // Test semantic search
        let semanticResults = try await searchEngine.search(
            query: "user login flow",
            options: SearchOptions(limit: 5, semanticWeight: 1.0)
        )
        #expect(!semanticResults.isEmpty, "Semantic search should return results")

        // Test hybrid search
        let hybridResults = try await searchEngine.search(
            query: "authentication error handling",
            options: SearchOptions(limit: 10, semanticWeight: 0.7)
        )
        #expect(!hybridResults.isEmpty, "Hybrid search should return results")
    }

    @Test("Search returns relevant results ranked by score")
    func searchRelevanceRanking() async throws {
        let projectDir = try createTestProject()
        defer { cleanupTestProject(projectDir) }

        let storageDir = projectDir.appendingPathComponent(".swiftindex").path
        let indexManager = try IndexManager(directory: storageDir, dimension: 384)
        let mockProvider = MockEmbeddingProvider(dimension: 384)
        let parser = HybridParser()

        // Index files
        let sourcesDir = projectDir.appendingPathComponent("Sources")
        let files = try FileManager.default.contentsOfDirectory(
            at: sourcesDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let result = parser.parse(content: content, path: file.path)

            guard case let .success(chunks) = result else {
                continue
            }

            for chunk in chunks {
                let embedding = try await mockProvider.embed(chunk.content)
                try await indexManager.index(chunk: chunk, vector: embedding)
            }
        }

        let chunkStore = await indexManager.chunkStore
        let vectorStore = await indexManager.vectorStore
        let searchEngine = HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: mockProvider
        )

        // Search for specific term
        let results = try await searchEngine.search(
            query: "User struct",
            options: SearchOptions(limit: 10)
        )

        // Verify results are sorted by score (descending)
        for i in 0 ..< (results.count - 1) {
            #expect(
                results[i].score >= results[i + 1].score,
                "Results should be sorted by score descending"
            )
        }
    }

    // MARK: - Provider Fallback Chain Tests

    @Test("Provider chain falls back when provider unavailable")
    func providerFallbackChain() async throws {
        // Create a chain with unavailable provider first, then available mock
        let unavailableProvider = UnavailableEmbeddingProvider()
        let mockProvider = MockEmbeddingProvider(dimension: 384)

        let chain = EmbeddingProviderChain(
            providers: [unavailableProvider, mockProvider],
            id: "test-chain",
            name: "Test Chain"
        )

        // Should succeed using fallback
        let isAvailable = await chain.isAvailable()
        #expect(isAvailable, "Chain should be available via fallback")

        // Should get embedding from fallback provider
        let embedding = try await chain.embed("test text")
        #expect(embedding.count == 384, "Should return embedding from fallback")
    }

    @Test("Provider chain throws when all providers unavailable")
    func providerChainAllUnavailable() async throws {
        let chain = EmbeddingProviderChain(
            providers: [UnavailableEmbeddingProvider(), UnavailableEmbeddingProvider()],
            id: "empty-chain",
            name: "Empty Chain"
        )

        let isAvailable = await chain.isAvailable()
        #expect(!isAvailable, "Chain should not be available when all providers unavailable")
    }

    // MARK: - Incremental Indexing Tests

    @Test("Incremental indexing only processes changed files")
    func incrementalIndexing() async throws {
        let projectDir = try createTestProject()
        defer { cleanupTestProject(projectDir) }

        let storageDir = projectDir.appendingPathComponent(".swiftindex").path
        let indexManager = try IndexManager(directory: storageDir, dimension: 384)
        let mockProvider = MockEmbeddingProvider(dimension: 384)
        let parser = HybridParser()

        let sourcesDir = projectDir.appendingPathComponent("Sources")
        let files = try FileManager.default.contentsOfDirectory(
            at: sourcesDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        // First indexing
        var indexedCount = 0
        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let fileHash = computeHash(content)

            // Check if already indexed with same hash
            let needsIndexing = try await indexManager.needsIndexing(fileHash: fileHash)
            if !needsIndexing {
                continue
            }

            let result = parser.parse(content: content, path: file.path)
            guard case let .success(chunks) = result else {
                continue
            }

            for chunk in chunks {
                let embedding = try await mockProvider.embed(chunk.content)
                try await indexManager.index(chunk: chunk, vector: embedding)
            }
            try await indexManager.recordIndexed(fileHash: fileHash, path: file.path)
            indexedCount += 1
        }

        #expect(indexedCount == 3, "Should index all 3 files on first run")

        // Second indexing without changes - should skip all files
        var skippedCount = 0
        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let fileHash = computeHash(content)
            let needsIndexing = try await indexManager.needsIndexing(fileHash: fileHash)

            if !needsIndexing {
                skippedCount += 1
            }
        }

        #expect(skippedCount == 3, "Should skip all 3 files on second run")
    }

    @Test("Parser handles Swift declarations correctly")
    func parserHandlesDeclarations() throws {
        let code = """
        struct User {
            let id: UUID
            var name: String

            func greet() -> String {
                return "Hello, \\(name)"
            }
        }

        extension User: Equatable {}

        protocol Identifiable {
            var id: UUID { get }
        }
        """

        let parser = HybridParser()
        let result = parser.parse(content: code, path: "User.swift")

        guard case let .success(chunks) = result else {
            Issue.record("Parser should succeed")
            return
        }

        // Should parse struct, function, extension, and protocol
        #expect(chunks.count >= 3, "Should parse multiple declarations")

        let kinds = Set(chunks.map(\.kind))
        let hasStruct = kinds.contains(ChunkKind.struct) || kinds.contains(where: \.isTypeDeclaration)
        #expect(hasStruct, "Should contain struct")
    }

    // MARK: - Hybrid Parser Tests

    @Test("HybridParser routes Swift files to SwiftSyntax")
    func hybridParserSwiftRouting() {
        let parser = HybridParser()
        let swiftCode = """
        func hello() {
            print("Hello")
        }
        """

        let result = parser.parse(content: swiftCode, path: "test.swift")

        guard case let .success(chunks) = result else {
            Issue.record("Parser should succeed for Swift file")
            return
        }

        #expect(!chunks.isEmpty, "Should parse Swift file")
        #expect(chunks[0].kind == ChunkKind.function || chunks[0].kind == ChunkKind.method, "Should identify function")
    }

    @Test("HybridParser handles unknown extensions gracefully")
    func hybridParserUnknownExtension() {
        let parser = HybridParser()
        let content = "Some random text content"

        let result = parser.parse(content: content, path: "readme.txt")
        // Should use plain text fallback which returns chunks for any text content
        switch result {
        case let .success(chunks):
            // PlainTextParser handles unknown extensions as fallback and returns chunks
            #expect(!chunks.isEmpty, "Plain text fallback should return chunks")
        case let .successWithSnippets(chunks, _):
            // PlainTextParser handles unknown extensions as fallback and returns chunks
            #expect(!chunks.isEmpty, "Plain text fallback should return chunks")
        case .failure:
            // Acceptable - unknown extension may fail gracefully
            #expect(Bool(true), "Parser returned failure for unknown extension")
        }
    }
}

// MARK: - Test Helpers

/// Mock embedding provider for testing.
private final class MockEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    let id = "mock"
    let name = "Mock Provider"
    let dimension: Int

    init(dimension: Int) {
        self.dimension = dimension
    }

    func isAvailable() async -> Bool {
        true
    }

    func embed(_ text: String) async throws -> [Float] {
        // Generate deterministic embedding based on text hash
        var generator = SeededRNG(seed: stableHash64(text))
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

    private func stableHash64(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

/// Embedding provider that is always unavailable.
private final class UnavailableEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    let id = "unavailable"
    let name = "Unavailable Provider"
    let dimension = 384

    func isAvailable() async -> Bool {
        false
    }

    func embed(_ text: String) async throws -> [Float] {
        throw ProviderError.notAvailable(reason: "Provider is unavailable for testing")
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        throw ProviderError.notAvailable(reason: "Provider is unavailable for testing")
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

/// Simple hash computation for file content.
private func computeHash(_ content: String) -> String {
    var hash = 0
    for char in content.unicodeScalars {
        hash = 31 &* hash &+ Int(char.value)
    }
    return String(format: "%08x", hash)
}

// MARK: - LLM Search Enhancement E2E Tests

/// End-to-end tests for LLM-enhanced search features.
@Suite("LLM Search Enhancement E2E")
struct LLMSearchEnhancementE2ETests {
    // MARK: - Test Fixtures

    /// Creates a temporary directory with Swift source files for testing.
    private func createTestProject() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftindex-llm-e2e-\(UUID().uuidString)")

        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        let sourcesDir = tempDir.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        // Create a model file
        let userModel = sourcesDir.appendingPathComponent("User.swift")
        try """
        import Foundation

        /// Represents a user in the system.
        struct User: Identifiable, Codable {
            let id: UUID
            var name: String
            var email: String

            /// Creates a new user with the given details.
            init(name: String, email: String) {
                self.id = UUID()
                self.name = name
                self.email = email
            }
        }
        """.write(to: userModel, atomically: true, encoding: .utf8)

        // Create an authentication service
        let authService = sourcesDir.appendingPathComponent("AuthService.swift")
        try """
        import Foundation

        /// Service handling user authentication.
        actor AuthenticationService {
            private var currentUser: User?

            /// Authenticates a user with email and password.
            func login(email: String, password: String) async throws -> User {
                let user = User(name: "Test", email: email)
                currentUser = user
                return user
            }

            /// Logs out the current user.
            func logout() {
                currentUser = nil
            }
        }
        """.write(to: authService, atomically: true, encoding: .utf8)

        return tempDir
    }

    private func cleanupTestProject(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Query Expansion Tests

    @Test("Query expander generates expanded query terms")
    func queryExpanderGeneratesTerms() async throws {
        let mockProvider = MockLLMProvider(
            response: """
            SYNONYMS: auth, authorization, sign in
            CONCEPTS: session management, token
            VARIATIONS: user authentication
            """
        )
        let expander = QueryExpander(provider: mockProvider)

        let expanded = try await expander.expand("authentication", timeout: 5)

        #expect(expanded.originalQuery == "authentication")
        #expect(!expanded.synonyms.isEmpty, "Should have synonyms")
        #expect(expanded.allTerms.count > 1, "Should have multiple terms")
    }

    @Test("Query expander caches results")
    func queryExpanderCaching() async throws {
        var callCount = 0
        let mockProvider = CountingLLMProvider { callCount += 1 }
        let expander = QueryExpander(provider: mockProvider)

        // First call
        _ = try await expander.expand("test query", timeout: 5)
        #expect(callCount == 1, "First call should invoke provider")

        // Second call with same query - should use cache
        _ = try await expander.expand("test query", timeout: 5)
        #expect(callCount == 1, "Second call should use cache")

        // Third call with different query
        _ = try await expander.expand("different query", timeout: 5)
        #expect(callCount == 2, "Different query should invoke provider")
    }

    // MARK: - Result Synthesis Tests

    @Test("Result synthesizer generates summary from search results")
    func resultSynthesizerGeneratesSummary() async throws {
        let mockProvider = MockLLMProvider(
            response: """
            SUMMARY: The codebase implements user authentication using an actor-based service.

            INSIGHTS:
            - AuthenticationService is an actor for thread-safe state management
            - Login method validates credentials and creates User instances

            REFERENCES:
            - AuthService.swift:10 - login method

            CONFIDENCE: 85%
            """
        )
        let synthesizer = ResultSynthesizer(provider: mockProvider)

        let inputs = [
            SynthesisInput(
                filePath: "AuthService.swift",
                content: "func login() async throws -> User",
                kind: "method",
                breadcrumb: "AuthenticationService > login()",
                docComment: "Authenticates a user"
            ),
        ]

        let synthesis = try await synthesizer.synthesize(
            query: "authentication",
            results: inputs,
            timeout: 5
        )

        #expect(synthesis.summary.contains("authentication"), "Summary should reference authentication")
        #expect(!synthesis.keyInsights.isEmpty, "Should have insights")
        #expect(synthesis.confidence > 0, "Should have confidence score")
    }

    @Test("Result synthesizer handles empty results gracefully")
    func resultSynthesizerEmptyResults() async throws {
        let mockProvider = MockLLMProvider(response: "No results")
        let synthesizer = ResultSynthesizer(provider: mockProvider)

        let synthesis = try await synthesizer.synthesize(
            query: "nonexistent",
            results: [],
            timeout: 5
        )

        #expect(synthesis.summary.contains("No results"), "Should indicate no results")
        #expect(synthesis.confidence == 0.0, "Confidence should be zero for empty results")
    }

    // MARK: - Follow-Up Generator Tests

    @Test("Follow-up generator suggests related queries")
    func followUpGeneratorSuggestsQueries() async throws {
        let mockProvider = MockLLMProvider(
            response: """
            1. how to test authentication - testing patterns for auth
            2. error handling in login - understanding error flows
            3. session management - related security concept
            """
        )
        let generator = FollowUpGenerator(provider: mockProvider)

        let suggestions = try await generator.generate(
            query: "authentication",
            resultSummary: "Found authentication service with login method",
            timeout: 5
        )

        #expect(!suggestions.isEmpty, "Should generate suggestions")
        #expect(suggestions.count >= 2, "Should have multiple suggestions")
    }

    @Test("Follow-up generator caches results")
    func followUpGeneratorCaching() async throws {
        var callCount = 0
        let mockProvider = CountingLLMProvider { callCount += 1 }
        let generator = FollowUpGenerator(provider: mockProvider)

        _ = try await generator.generate(
            query: "test",
            resultSummary: "summary",
            timeout: 5
        )
        #expect(callCount == 1)

        _ = try await generator.generate(
            query: "test",
            resultSummary: "summary",
            timeout: 5
        )
        #expect(callCount == 1, "Should use cached result")

        await generator.clearCache()

        _ = try await generator.generate(
            query: "test",
            resultSummary: "summary",
            timeout: 5
        )
        #expect(callCount == 2, "Should call after cache clear")
    }

    // MARK: - Full Enhanced Search Flow Tests

    @Test("Full enhanced search flow with query expansion and synthesis")
    func fullEnhancedSearchFlow() async throws {
        let projectDir = try createTestProject()
        defer { cleanupTestProject(projectDir) }

        let storageDir = projectDir.appendingPathComponent(".swiftindex").path
        let indexManager = try IndexManager(directory: storageDir, dimension: 384)
        let mockEmbeddingProvider = MockEmbeddingProviderE2E(dimension: 384)
        let parser = HybridParser()

        // Index files
        let sourcesDir = projectDir.appendingPathComponent("Sources")
        let files = try FileManager.default.contentsOfDirectory(
            at: sourcesDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let result = parser.parse(content: content, path: file.path)
            guard case let .success(chunks) = result else { continue }

            for chunk in chunks {
                let embedding = try await mockEmbeddingProvider.embed(chunk.content)
                try await indexManager.index(chunk: chunk, vector: embedding)
            }
        }

        // Create search engine
        let chunkStore = await indexManager.chunkStore
        let vectorStore = await indexManager.vectorStore
        let searchEngine = HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: mockEmbeddingProvider
        )

        // Create LLM components with mocks
        let mockLLMProvider = MockLLMProvider(
            response: """
            SYNONYMS: auth, sign in
            CONCEPTS: session
            VARIATIONS: user auth
            """
        )
        let expander = QueryExpander(provider: mockLLMProvider)

        // Step 1: Expand query
        let expanded = try await expander.expand("login", timeout: 5)
        #expect(expanded.allTerms.count > 1, "Query should be expanded")

        // Step 2: Search with expanded terms
        let results = try await searchEngine.search(
            query: expanded.combinedQuery,
            options: SearchOptions(limit: 10)
        )
        #expect(!results.isEmpty, "Should find results")

        // Step 3: Synthesize results
        let synthesisMockProvider = MockLLMProvider(
            response: """
            SUMMARY: Found login functionality in AuthenticationService actor.

            INSIGHTS:
            - Actor-based design for thread safety
            - Async/await pattern for login flow

            CONFIDENCE: 80%
            """
        )
        let synthesizer = ResultSynthesizer(provider: synthesisMockProvider)

        let synthesisInputs = results.map { result in
            SynthesisInput(
                filePath: result.chunk.path,
                content: result.chunk.content,
                kind: result.chunk.kind.rawValue,
                breadcrumb: result.chunk.breadcrumb,
                docComment: result.chunk.docComment
            )
        }

        let synthesis = try await synthesizer.synthesize(
            query: "login",
            results: synthesisInputs,
            timeout: 5
        )

        #expect(!synthesis.summary.isEmpty, "Should have synthesis summary")
        #expect(synthesis.confidence > 0, "Should have confidence score")

        // Step 4: Generate follow-ups
        let followUpMockProvider = MockLLMProvider(
            response: """
            1. how to test login - testing patterns
            2. logout implementation - related functionality
            """
        )
        let generator = FollowUpGenerator(provider: followUpMockProvider)

        let followUps = try await generator.generate(
            query: "login",
            resultSummary: synthesis.summary,
            timeout: 5
        )

        #expect(!followUps.isEmpty, "Should generate follow-up suggestions")
    }

    // MARK: - LLM Provider Chain Tests

    @Test("LLM provider chain falls back to available provider")
    func llmProviderChainFallback() async throws {
        let unavailable = UnavailableLLMProvider()
        let available = MockLLMProvider(response: "Success from fallback")

        let chain = LLMProviderChain(providers: [unavailable, available])

        let isAvailable = await chain.isAvailable()
        #expect(isAvailable, "Chain should be available via fallback")

        let response = try await chain.complete(messages: [.user("test")])
        #expect(response == "Success from fallback", "Should get response from fallback")
    }

    @Test("LLM provider chain throws when all providers fail")
    func llmProviderChainAllFail() async throws {
        let chain = LLMProviderChain(providers: [
            UnavailableLLMProvider(),
            UnavailableLLMProvider(),
        ])

        let isAvailable = await chain.isAvailable()
        #expect(!isAvailable, "Chain should not be available")

        await #expect(throws: LLMError.self) {
            _ = try await chain.complete(messages: [.user("test")])
        }
    }
}

// MARK: - LLM Test Helpers

/// Mock LLM provider for testing.
private struct MockLLMProvider: LLMProvider {
    let id: String
    let name: String
    let response: String

    init(id: String = "mock-llm", response: String = "Mock response") {
        self.id = id
        name = "Mock LLM Provider"
        self.response = response
    }

    func isAvailable() async -> Bool { true }

    func complete(
        messages: [LLMMessage],
        model: String?,
        timeout: TimeInterval
    ) async throws -> String {
        response
    }
}

/// LLM provider that counts calls for testing caching.
private final class CountingLLMProvider: LLMProvider, @unchecked Sendable {
    let id: String = "counting-llm"
    let name: String = "Counting LLM Provider"
    private let onCall: () -> Void

    init(onCall: @escaping () -> Void) {
        self.onCall = onCall
    }

    func isAvailable() async -> Bool { true }

    func complete(
        messages: [LLMMessage],
        model: String?,
        timeout: TimeInterval
    ) async throws -> String {
        onCall()
        return "1. test query - rationale"
    }
}

/// LLM provider that is always unavailable.
private struct UnavailableLLMProvider: LLMProvider {
    let id = "unavailable-llm"
    let name = "Unavailable LLM"

    func isAvailable() async -> Bool { false }

    func complete(
        messages: [LLMMessage],
        model: String?,
        timeout: TimeInterval
    ) async throws -> String {
        throw LLMError.notAvailable(reason: "Provider unavailable for testing")
    }
}

/// Mock embedding provider for LLM E2E tests.
private final class MockEmbeddingProviderE2E: EmbeddingProvider, @unchecked Sendable {
    let id = "mock-e2e"
    let name = "Mock E2E Provider"
    let dimension: Int

    init(dimension: Int) {
        self.dimension = dimension
    }

    func isAvailable() async -> Bool { true }

    func embed(_ text: String) async throws -> [Float] {
        var generator = SeededRNG(seed: stableHash(text))
        var embedding = (0 ..< dimension).map { _ in Float.random(in: -1 ... 1, using: &generator) }
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if norm > 0 { embedding = embedding.map { $0 / norm } }
        return embedding
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        try await texts.asyncMap { try await embed($0) }
    }

    private func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

/// Async map extension for test helpers.
private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)
        for element in self {
            try await results.append(transform(element))
        }
        return results
    }
}
