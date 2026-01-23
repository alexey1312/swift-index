@testable import SwiftIndexCore
import Testing

// MARK: - InfoSnippet Storage Tests

@Suite("InfoSnippet Storage Tests")
struct InfoSnippetStorageTests {
    // MARK: - Basic CRUD

    @Test("Insert and retrieve snippet")
    func insertAndRetrieve() async throws {
        let store = try GRDBChunkStore()
        let snippet = makeSnippet(id: "snippet-1", path: "/test/README.md")

        try await store.insertSnippet(snippet)
        let retrieved = try await store.getSnippet(id: "snippet-1")

        #expect(retrieved != nil)
        #expect(retrieved?.id == "snippet-1")
        #expect(retrieved?.path == "/test/README.md")
        #expect(retrieved?.content == snippet.content)
        #expect(retrieved?.kind == .markdownSection)
    }

    @Test("Insert batch of snippets")
    func insertBatch() async throws {
        let store = try GRDBChunkStore()
        let snippets = [
            makeSnippet(id: "batch-1", path: "/test/file1.md"),
            makeSnippet(id: "batch-2", path: "/test/file2.md"),
            makeSnippet(id: "batch-3", path: "/test/file3.md"),
        ]

        try await store.insertSnippetBatch(snippets)
        let count = try await store.snippetCount()

        #expect(count == 3)
    }

    @Test("Get snippets by path")
    func getByPath() async throws {
        let store = try GRDBChunkStore()
        try await store.insertSnippetBatch([
            makeSnippet(id: "path-1", path: "/test/README.md", startLine: 1),
            makeSnippet(id: "path-2", path: "/test/README.md", startLine: 10),
            makeSnippet(id: "path-3", path: "/test/GUIDE.md", startLine: 1),
        ])

        let snippets = try await store.getSnippetsByPath("/test/README.md")

        #expect(snippets.count == 2)
        #expect(snippets[0].startLine < snippets[1].startLine) // Ordered by line
    }

    @Test("Get snippets by chunk ID")
    func getByChunkId() async throws {
        let store = try GRDBChunkStore()
        try await store.insertSnippetBatch([
            makeSnippet(id: "chunk-ref-1", chunkId: "parent-1"),
            makeSnippet(id: "chunk-ref-2", chunkId: "parent-1"),
            makeSnippet(id: "chunk-ref-3", chunkId: "parent-2"),
        ])

        let snippets = try await store.getSnippetsByChunkId("parent-1")

        #expect(snippets.count == 2)
        #expect(snippets.allSatisfy { $0.chunkId == "parent-1" })
    }

    @Test("Delete snippet by ID")
    func deleteByID() async throws {
        let store = try GRDBChunkStore()
        try await store.insertSnippet(makeSnippet(id: "delete-1"))

        try await store.deleteSnippet(id: "delete-1")
        let retrieved = try await store.getSnippet(id: "delete-1")

        #expect(retrieved == nil)
    }

    @Test("Delete snippets by path")
    func deleteByPath() async throws {
        let store = try GRDBChunkStore()
        try await store.insertSnippetBatch([
            makeSnippet(id: "del-path-1", path: "/test/delete.md"),
            makeSnippet(id: "del-path-2", path: "/test/delete.md"),
            makeSnippet(id: "del-path-3", path: "/test/keep.md"),
        ])

        try await store.deleteSnippetsByPath("/test/delete.md")
        let remaining = try await store.snippetCount()

        #expect(remaining == 1)
    }

    @Test("Delete snippets by chunk ID")
    func deleteByChunkId() async throws {
        let store = try GRDBChunkStore()
        try await store.insertSnippetBatch([
            makeSnippet(id: "del-chunk-1", chunkId: "remove-me"),
            makeSnippet(id: "del-chunk-2", chunkId: "remove-me"),
            makeSnippet(id: "del-chunk-3", chunkId: "keep-me"),
        ])

        try await store.deleteSnippetsByChunkId("remove-me")
        let remaining = try await store.snippetCount()

        #expect(remaining == 1)
    }

    // MARK: - Rich Metadata Tests

    @Test("Store and retrieve snippet with breadcrumb")
    func storeAndRetrieveBreadcrumb() async throws {
        let store = try GRDBChunkStore()
        let snippet = makeSnippet(
            id: "bread-1",
            breadcrumb: "README > Installation > macOS"
        )

        try await store.insertSnippet(snippet)
        let retrieved = try await store.getSnippet(id: "bread-1")

        #expect(retrieved != nil)
        #expect(retrieved?.breadcrumb == "README > Installation > macOS")
    }

    @Test("Store and retrieve all metadata fields")
    func storeAndRetrieveAllMetadata() async throws {
        let store = try GRDBChunkStore()
        let snippet = InfoSnippet(
            id: "meta-1",
            path: "/test/README.md",
            content: "## Installation\n\nRun `brew install swiftindex`",
            startLine: 5,
            endLine: 8,
            breadcrumb: "README > Installation",
            tokenCount: 15,
            language: "markdown",
            chunkId: "parent-chunk-123",
            kind: .markdownSection,
            fileHash: "hash123"
        )

        try await store.insertSnippet(snippet)
        let retrieved = try await store.getSnippet(id: "meta-1")

        #expect(retrieved != nil)
        #expect(retrieved?.path == "/test/README.md")
        #expect(retrieved?.startLine == 5)
        #expect(retrieved?.endLine == 8)
        #expect(retrieved?.breadcrumb == "README > Installation")
        #expect(retrieved?.tokenCount == 15)
        #expect(retrieved?.language == "markdown")
        #expect(retrieved?.chunkId == "parent-chunk-123")
        #expect(retrieved?.kind == .markdownSection)
    }

    // MARK: - FTS Search Tests

    @Test("FTS search finds matching content")
    func ftsSearch() async throws {
        let store = try GRDBChunkStore()
        try await store.insertSnippetBatch([
            makeSnippet(id: "fts-1", content: "## Installation\n\nInstall via Homebrew"),
            makeSnippet(id: "fts-2", content: "## Usage\n\nRun the CLI tool"),
            makeSnippet(id: "fts-3", content: "## Configuration\n\nEdit the config file"),
        ])

        let results = try await store.searchSnippetsFTS(query: "installation", limit: 10)

        #expect(results.count >= 1)
        #expect(results[0].snippet.id == "fts-1")
        #expect(results[0].score > 0)
    }

    @Test("FTS search finds breadcrumb content")
    func ftsSearchBreadcrumb() async throws {
        let store = try GRDBChunkStore()
        try await store.insertSnippetBatch([
            makeSnippet(
                id: "bread-fts-1",
                content: "General content here",
                breadcrumb: "Authentication Guide > OAuth2 Setup"
            ),
            makeSnippet(
                id: "bread-fts-2",
                content: "Other content",
                breadcrumb: "Getting Started > Basics"
            ),
        ])

        let results = try await store.searchSnippetsFTS(query: "OAuth2", limit: 10)

        #expect(results.count >= 1)
        #expect(results[0].snippet.id == "bread-fts-1")
    }

    @Test("FTS search returns empty for no matches")
    func ftsNoMatches() async throws {
        let store = try GRDBChunkStore()
        try await store.insertSnippet(makeSnippet(id: "no-match", content: "Some documentation"))

        let results = try await store.searchSnippetsFTS(query: "nonexistent", limit: 10)

        #expect(results.isEmpty)
    }

    // MARK: - Clear and Count

    @Test("Clear snippets")
    func clearSnippets() async throws {
        let store = try GRDBChunkStore()
        try await store.insertSnippetBatch([
            makeSnippet(id: "clear-1"),
            makeSnippet(id: "clear-2"),
        ])

        try await store.clearSnippets()
        let count = try await store.snippetCount()

        #expect(count == 0)
    }

    @Test("Clear all clears both chunks and snippets")
    func clearAllClearsBoth() async throws {
        let store = try GRDBChunkStore()
        try await store.insert(makeChunk(id: "chunk-1"))
        try await store.insertSnippet(makeSnippet(id: "snippet-1"))

        try await store.clear()
        let chunkCount = try await store.count()
        let snippetCount = try await store.snippetCount()

        #expect(chunkCount == 0)
        #expect(snippetCount == 0)
    }
}
