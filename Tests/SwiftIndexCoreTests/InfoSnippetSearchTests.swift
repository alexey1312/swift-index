import Foundation
@testable import SwiftIndexCore
import Testing

// MARK: - InfoSnippet Search Tests

@Suite("InfoSnippet Search Tests")
struct InfoSnippetSearchTests {
    func makeTestSetup() async throws -> (
        chunkStore: MockChunkStoreWithSnippets,
        vectorStore: MockVectorStore,
        embeddingProvider: SearchTestMockEmbeddingProvider
    ) {
        let chunks: [CodeChunk] = [
            CodeChunk(
                id: "chunk1",
                path: "/src/main.swift",
                content: "func main() { }",
                startLine: 1,
                endLine: 3,
                kind: .function,
                symbols: ["main"],
                references: [],
                fileHash: "hash1"
            ),
        ]

        let snippets: [InfoSnippet] = [
            InfoSnippet(
                id: "snippet1",
                path: "/README.md",
                content: "# Installation\n\nInstall via Homebrew:\n```\nbrew install swiftindex\n```",
                startLine: 1,
                endLine: 5,
                breadcrumb: "README > Installation",
                kind: .markdownSection,
                fileHash: "hash-readme"
            ),
            InfoSnippet(
                id: "snippet2",
                path: "/README.md",
                content: "# Usage\n\nRun the indexer:\n```\nswiftindex index .\n```",
                startLine: 6,
                endLine: 10,
                breadcrumb: "README > Usage",
                kind: .markdownSection,
                fileHash: "hash-readme"
            ),
            InfoSnippet(
                id: "snippet3",
                path: "/docs/API.md",
                content: "# API Reference\n\nThe search API supports hybrid search.",
                startLine: 1,
                endLine: 3,
                breadcrumb: "API > Reference",
                kind: .documentation,
                fileHash: "hash-api"
            ),
        ]

        let chunkStore = MockChunkStoreWithSnippets(chunks: chunks, snippets: snippets)
        let vectorStore = MockVectorStore(dimension: 384)
        let embeddingProvider = SearchTestMockEmbeddingProvider()

        // Add vectors for chunks
        for chunk in chunks {
            let vector = try await embeddingProvider.embed(chunk.content)
            try await vectorStore.add(id: chunk.id, vector: vector)
        }

        return (chunkStore, vectorStore, embeddingProvider)
    }

    @Test("Search info snippets by query")
    func searchInfoSnippets() async throws {
        let (chunkStore, vectorStore, embeddingProvider) = try await makeTestSetup()
        let engine = HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: embeddingProvider
        )

        let results = try await engine.searchInfoSnippets(
            query: "installation homebrew",
            limit: 10
        )

        #expect(!results.isEmpty)
        #expect(results.first?.snippet.content.contains("Homebrew") == true)
    }

    @Test("Search info snippets with path filter")
    func searchInfoSnippetsWithPathFilter() async throws {
        let (chunkStore, vectorStore, embeddingProvider) = try await makeTestSetup()
        let engine = HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: embeddingProvider
        )

        let results = try await engine.searchInfoSnippets(
            query: "API reference",
            limit: 10,
            pathFilter: "**/docs/*.md"
        )

        for result in results {
            #expect(result.snippet.path.contains("/docs/"))
        }
    }

    @Test("Info snippet search result properties")
    func infoSnippetResultProperties() async throws {
        let snippet = InfoSnippet(
            id: "test-snippet",
            path: "/README.md",
            content: "Test content",
            startLine: 1,
            endLine: 3,
            breadcrumb: "README",
            kind: .documentation,
            fileHash: "hash"
        )

        let result = InfoSnippetSearchResult(snippet: snippet, score: 10.5)

        #expect(result.id == "test-snippet")
        #expect(result.score == 10.5)
        #expect(result.relevancePercent >= 0 && result.relevancePercent <= 100)
    }

    @Test("Info snippet search result comparison")
    func infoSnippetResultComparison() {
        let snippet1 = InfoSnippet(
            id: "1",
            path: "/a.md",
            content: "First",
            startLine: 1,
            endLine: 1,
            kind: .documentation,
            fileHash: "h1"
        )

        let snippet2 = InfoSnippet(
            id: "2",
            path: "/b.md",
            content: "Second",
            startLine: 1,
            endLine: 1,
            kind: .documentation,
            fileHash: "h2"
        )

        let result1 = InfoSnippetSearchResult(snippet: snippet1, score: 15.0)
        let result2 = InfoSnippetSearchResult(snippet: snippet2, score: 10.0)

        // Higher score should be "less than" for sorting (comes first)
        #expect(result1 < result2)

        let sorted = [result2, result1].sorted()
        #expect(sorted.first?.snippet.id == "1")
    }
}

// MARK: - MockChunkStoreWithSnippets

/// Mock chunk store that also implements InfoSnippetStore for testing.
actor MockChunkStoreWithSnippets: ChunkStore, InfoSnippetStore {
    private var chunks: [String: CodeChunk] = [:]
    private var snippets: [String: InfoSnippet] = [:]
    private var fileHashesByPath: [String: String] = [:]

    init(chunks: [CodeChunk] = [], snippets: [InfoSnippet] = []) {
        for chunk in chunks {
            self.chunks[chunk.id] = chunk
        }
        for snippet in snippets {
            self.snippets[snippet.id] = snippet
        }
    }

    // MARK: - ChunkStore

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
        let terms = query.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        var results: [(chunk: CodeChunk, score: Double)] = []

        for chunk in chunks.values {
            let content = chunk.content.lowercased()
            var matchCount = 0
            for term in terms where content.contains(term) {
                matchCount += 1
            }

            if matchCount > 0 {
                let score = Double(matchCount) / Double(max(terms.count, 1))
                results.append((chunk: chunk, score: score))
            }
        }

        return results.sorted { $0.score > $1.score }.prefix(limit).map(\.self)
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

    func getTermFrequency(term: String) async throws -> Int {
        chunks.values.count(where: { chunk in
            chunk.symbols.contains(term) ||
                chunk.content.lowercased().contains(term.lowercased())
        })
    }

    // MARK: - InfoSnippetStore

    func insertSnippet(_ snippet: InfoSnippet) async throws {
        snippets[snippet.id] = snippet
    }

    func insertSnippetBatch(_ newSnippets: [InfoSnippet]) async throws {
        for snippet in newSnippets {
            snippets[snippet.id] = snippet
        }
    }

    func getSnippet(id: String) async throws -> InfoSnippet? {
        snippets[id]
    }

    func getSnippetsByPath(_ path: String) async throws -> [InfoSnippet] {
        snippets.values.filter { $0.path == path }
    }

    func getSnippetsByChunkId(_ chunkId: String) async throws -> [InfoSnippet] {
        snippets.values.filter { $0.chunkId == chunkId }
    }

    func deleteSnippet(id: String) async throws {
        snippets.removeValue(forKey: id)
    }

    func deleteSnippetsByPath(_ path: String) async throws {
        snippets = snippets.filter { $0.value.path != path }
    }

    func deleteSnippetsByChunkId(_ chunkId: String) async throws {
        snippets = snippets.filter { $0.value.chunkId != chunkId }
    }

    func searchSnippetsFTS(query: String, limit: Int) async throws -> [(snippet: InfoSnippet, score: Double)] {
        let terms = query.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        var results: [(snippet: InfoSnippet, score: Double)] = []

        for snippet in snippets.values {
            let content = snippet.content.lowercased()
            var matchCount = 0
            for term in terms where content.contains(term) {
                matchCount += 1
            }

            if matchCount > 0 {
                let score = Double(matchCount) / Double(max(terms.count, 1))
                results.append((snippet: snippet, score: score))
            }
        }

        return results.sorted { $0.score > $1.score }.prefix(limit).map(\.self)
    }

    func snippetCount() async throws -> Int {
        snippets.count
    }

    func clearSnippets() async throws {
        snippets.removeAll()
    }
}
