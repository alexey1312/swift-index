import Foundation
@testable import SwiftIndexCore
import Testing

// MARK: - Counting Embedding Provider

/// Records every batch of texts it was asked to embed, so tests can assert
/// exactly how much re-embedding an incremental update triggered.
private actor EmbedRecorder {
    private(set) var batches: [[String]] = []

    func record(_ texts: [String]) {
        batches.append(texts)
    }

    var totalEmbedded: Int {
        batches.reduce(0) { $0 + $1.count }
    }

    var callCount: Int {
        batches.count
    }
}

private struct CountingEmbeddingProvider: EmbeddingProvider {
    let id = "counting"
    let name = "Counting Test Provider"
    let dimension: Int
    let recorder: EmbedRecorder
    var shouldFail = false

    func isAvailable() async -> Bool {
        true
    }

    func embed(_ text: String) async throws -> [Float] {
        try await embed([text])[0]
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        await recorder.record(texts)
        if shouldFail {
            throw ProviderError.embeddingFailed("test failure")
        }
        // Deterministic, content-dependent vector so distinct chunks differ.
        return texts.map { text in
            let seed = Float(stableTestHash(text) % 1000) / 1000.0
            return (0 ..< dimension).map { Float($0) * 0.01 + seed }
        }
    }
}

// MARK: - Tests

@Suite("IncrementalIndexer Tests")
struct IncrementalIndexerTests {
    let dimension = 4

    // MARK: - Regression: file hashes must be recorded (B3)

    @Test("Indexing a file records its content hash")
    func indexFileRecordsFileHash() async throws {
        let harness = try await Harness(dimension: dimension)
        defer { harness.cleanup() }
        let path = try harness.writeFile(
            name: "Sample.swift",
            content: """
            struct Greeter {
                func hello() -> String { "hello" }
            }
            """
        )

        try await harness.indexer.indexFile(at: path, isNew: true)

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let expected = FileHasher.hash(content)
        let stored = try await harness.indexManager.chunkStore.getFileHash(forPath: path)

        #expect(stored == expected)
    }

    @Test("Re-indexing a modified file updates the stored hash")
    func modifiedFileUpdatesStoredHash() async throws {
        let harness = try await Harness(dimension: dimension)
        defer { harness.cleanup() }
        let path = try harness.writeFile(
            name: "Sample.swift",
            content: """
            struct Greeter {
                func hello() -> String { "hello" }
            }
            """
        )
        try await harness.indexer.indexFile(at: path, isNew: true)
        let firstHash = try await harness.indexManager.chunkStore.getFileHash(forPath: path)

        try harness.writeFile(
            name: "Sample.swift",
            content: """
            struct Greeter {
                func hello() -> String { "hello, world" }
            }
            """
        )
        try await harness.indexer.indexFile(at: path)

        let newContent = try String(contentsOfFile: path, encoding: .utf8)
        let expected = FileHasher.hash(newContent)
        let stored = try await harness.indexManager.chunkStore.getFileHash(forPath: path)

        #expect(stored == expected)
        #expect(stored != firstHash)

        // The whole point of recording the hash: the file is now seen as clean.
        let needsIndexing = try await harness.indexManager.needsIndexing(
            path: path,
            fileHash: expected
        )
        #expect(needsIndexing == false)
    }

    // MARK: - Regression: per-chunk embedding reuse (B4)

    @Test("Editing one function re-embeds only the changed chunk")
    func partialEditReusesUnchangedChunkEmbeddings() async throws {
        let harness = try await Harness(dimension: dimension)
        defer { harness.cleanup() }
        let path = try harness.writeFile(
            name: "Multi.swift",
            content: """
            func alpha() -> Int {
                return 1
            }

            func beta() -> Int {
                return 2
            }

            func gamma() -> Int {
                return 3
            }
            """
        )

        try await harness.indexer.indexFile(at: path, isNew: true)
        let initialEmbedded = await harness.recorder.totalEmbedded
        #expect(initialEmbedded >= 3, "expected each function to be embedded on first index")

        // Change exactly one function body.
        try harness.writeFile(
            name: "Multi.swift",
            content: """
            func alpha() -> Int {
                return 1
            }

            func beta() -> Int {
                return 22222
            }

            func gamma() -> Int {
                return 3
            }
            """
        )

        let beforeEdit = await harness.recorder.totalEmbedded
        try await harness.indexer.indexFile(at: path)
        let afterEdit = await harness.recorder.totalEmbedded

        let reEmbedded = afterEdit - beforeEdit
        #expect(
            reEmbedded == 1,
            "expected exactly the edited chunk to be re-embedded, got \(reEmbedded)"
        )

        let stats = await harness.indexer.getStats()
        #expect(stats.chunksReused >= 2)
    }

    @Test("Re-indexing an unchanged file embeds nothing")
    func unchangedFileEmbedsNothing() async throws {
        let harness = try await Harness(dimension: dimension)
        defer { harness.cleanup() }
        let path = try harness.writeFile(
            name: "Stable.swift",
            content: """
            func stable() -> Int {
                return 42
            }
            """
        )

        try await harness.indexer.indexFile(at: path, isNew: true)
        let afterFirst = await harness.recorder.totalEmbedded

        try await harness.indexer.indexFile(at: path)
        let afterSecond = await harness.recorder.totalEmbedded

        #expect(afterSecond == afterFirst, "unchanged content must not be re-embedded")
    }

    // MARK: - Deletion

    @Test("Removing a file drops its chunks, snippets, hash and vectors")
    func removeFileCleansUpFully() async throws {
        let harness = try await Harness(dimension: dimension)
        defer { harness.cleanup() }
        let path = try harness.writeFile(
            name: "Doomed.swift",
            content: """
            func doomed() -> Int {
                return 7
            }
            """
        )

        try await harness.indexer.indexFile(at: path, isNew: true)
        let chunksBefore = try await harness.indexManager.chunkStore.getByPath(path)
        #expect(!chunksBefore.isEmpty)

        try await harness.indexer.removeFile(at: path)

        let chunksAfter = try await harness.indexManager.chunkStore.getByPath(path)
        let hashAfter = try await harness.indexManager.chunkStore.getFileHash(forPath: path)
        #expect(chunksAfter.isEmpty)
        #expect(hashAfter == nil)

        for chunk in chunksBefore {
            let stillThere = try await harness.indexManager.vectorStore.contains(id: chunk.id)
            #expect(stillThere == false, "vector for \(chunk.id) should have been deleted")
        }
    }

    @Test("A file that loses all chunks has its stale chunks removed")
    func fileEmptiedDropsStaleChunks() async throws {
        let harness = try await Harness(dimension: dimension)
        defer { harness.cleanup() }
        let path = try harness.writeFile(
            name: "Vanishing.swift",
            content: """
            func willDisappear() -> Int {
                return 1
            }
            """
        )

        try await harness.indexer.indexFile(at: path, isNew: true)
        let before = try await harness.indexManager.chunkStore.getByPath(path)
        #expect(!before.isEmpty)

        // Replace the body with something that yields no chunks at all.
        try harness.writeFile(name: "Vanishing.swift", content: "// only a comment\n")
        try await harness.indexer.indexFile(at: path)

        let after = try await harness.indexManager.chunkStore.getByPath(path)
        #expect(after.isEmpty, "stale chunks must not survive an emptied file")

        for chunk in before {
            let stillThere = try await harness.indexManager.vectorStore.contains(id: chunk.id)
            #expect(stillThere == false, "vector for \(chunk.id) should have been deleted")
        }
    }

    // MARK: - Durability (B5)

    @Test("Pending vector-index save is flushed on stop")
    func flushPendingSaveOnStop() async throws {
        let harness = try await Harness(
            dimension: dimension,
            saveDebounceMs: 60000,
            persistent: true
        )
        defer { harness.cleanup() }
        let path = try harness.writeFile(
            name: "Persisted.swift",
            content: """
            func persisted() -> Int {
                return 5
            }
            """
        )

        try await harness.indexer.indexFile(at: path, isNew: true)

        // With a 60s debounce the coalesced save has definitely not fired yet.
        let vectorFile = harness.directory.appendingPathComponent("vectors.usearch").path
        #expect(
            FileManager.default.fileExists(atPath: vectorFile) == false,
            "save should not have fired before stop()"
        )

        // stop() must persist rather than dropping the vectors.
        await harness.indexer.stop()

        #expect(FileManager.default.fileExists(atPath: vectorFile))
        let stats = await harness.indexer.getStats()
        #expect(stats.errors == 0)
    }

    @Test("Coalesced saves do not lose the final edit")
    func coalescingKeepsFinalState() async throws {
        let harness = try await Harness(
            dimension: dimension,
            saveDebounceMs: 50,
            persistent: true
        )
        defer { harness.cleanup() }
        let path = try harness.writeFile(
            name: "Churn.swift",
            content: "func churn() -> Int { return 0 }"
        )

        // A burst of edits should collapse into a coalesced save without losing
        // the last one.
        for value in 1 ... 5 {
            try harness.writeFile(
                name: "Churn.swift",
                content: "func churn() -> Int { return \(value) }"
            )
            try await harness.indexer.indexFile(at: path)
        }

        await harness.indexer.stop()

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let finalHash = FileHasher.hash(content)
        let stored = try await harness.indexManager.chunkStore.getFileHash(forPath: path)
        #expect(stored == finalHash, "index must reflect the last edit of the burst")

        let vectorFile = harness.directory.appendingPathComponent("vectors.usearch").path
        #expect(FileManager.default.fileExists(atPath: vectorFile))

        let stats = await harness.indexer.getStats()
        #expect(stats.errors == 0)
    }

    @Test("Indexing failures propagate to the caller")
    func indexingFailurePropagates() async throws {
        let harness = try await Harness(dimension: dimension, failEmbeddings: true)
        defer { harness.cleanup() }
        let path = try harness.writeFile(
            name: "Broken.swift",
            content: "func broken() -> Int { return 1 }"
        )

        await #expect(throws: (any Error).self) {
            try await harness.indexer.indexFile(at: path, isNew: true)
        }
    }

    @Test("Unreadable file is skipped without throwing")
    func missingFileIsSkipped() async throws {
        let harness = try await Harness(dimension: dimension)
        defer { harness.cleanup() }
        let missing = harness.directory.appendingPathComponent("DoesNotExist.swift").path

        // A file can vanish between the watch event and the read; that is not an error.
        try await harness.indexer.indexFile(at: missing, isNew: true)

        let stats = await harness.indexer.getStats()
        #expect(stats.errors == 0)
    }

    @Test("Emptying a file removes its chunks, snippets and vectors")
    func emptiedFileIsClearedFromIndex() async throws {
        let harness = try await Harness(dimension: dimension)
        defer { harness.cleanup() }
        let path = try harness.writeFile(
            name: "Emptied.swift",
            content: """
            /// Documented helper.
            func soonGone() -> Int {
                return 1
            }
            """
        )

        try await harness.indexer.indexFile(at: path, isNew: true)
        let before = try await harness.indexManager.chunkStore.getByPath(path)
        #expect(!before.isEmpty)

        // Truly empty content makes the parser return .failure(.emptyContent).
        try harness.writeFile(name: "Emptied.swift", content: "")
        try await harness.indexer.indexFile(at: path)

        let after = try await harness.indexManager.chunkStore.getByPath(path)
        #expect(after.isEmpty, "deleted code must not stay searchable")

        for chunk in before {
            let stillThere = try await harness.indexManager.vectorStore.contains(id: chunk.id)
            #expect(stillThere == false)
        }
    }

    @Test("A syntax error does not wipe previously indexed chunks")
    func syntaxErrorPreservesExistingChunks() async throws {
        let harness = try await Harness(dimension: dimension)
        defer { harness.cleanup() }
        let path = try harness.writeFile(
            name: "MidEdit.swift",
            content: """
            func stable() -> Int {
                return 1
            }
            """
        )

        try await harness.indexer.indexFile(at: path, isNew: true)
        let before = try await harness.indexManager.chunkStore.getByPath(path)
        #expect(!before.isEmpty)

        // Half-typed code should not blank the file out of search results.
        try harness.writeFile(name: "MidEdit.swift", content: "func stable( -> Int {")
        try await harness.indexer.indexFile(at: path)

        let after = try await harness.indexManager.chunkStore.getByPath(path)
        #expect(!after.isEmpty, "a transient parse error must not clear the index")
    }

    @Test("Concurrent flushes both wait for the write to finish")
    func concurrentFlushesAreSerialized() async throws {
        let harness = try await Harness(
            dimension: dimension,
            saveDebounceMs: 60000,
            persistent: true
        )
        defer { harness.cleanup() }
        let path = try harness.writeFile(
            name: "Concurrent.swift",
            content: "func concurrent() -> Int { return 1 }"
        )
        try await harness.indexer.indexFile(at: path, isNew: true)

        // WatchCommand issues two overlapping stop() calls; neither may return
        // while the vector index is still being written.
        async let first: Void = harness.indexer.stop()
        async let second: Void = harness.indexer.stop()
        _ = await (first, second)

        let vectorFile = harness.directory.appendingPathComponent("vectors.usearch").path
        #expect(FileManager.default.fileExists(atPath: vectorFile))

        let stats = await harness.indexer.getStats()
        #expect(stats.errors == 0)
    }

    @Test("No save is armed after stop")
    func noSaveArmedAfterStop() async throws {
        let harness = try await Harness(
            dimension: dimension,
            saveDebounceMs: 50,
            persistent: true
        )
        defer { harness.cleanup() }
        let path = try harness.writeFile(
            name: "AfterStop.swift",
            content: "func afterStop() -> Int { return 1 }"
        )
        try await harness.indexer.indexFile(at: path, isNew: true)
        await harness.indexer.stop()

        let vectorFile = harness.directory.appendingPathComponent("vectors.usearch").path
        let attributes = try FileManager.default.attributesOfItem(atPath: vectorFile)
        let savedAt = attributes[.modificationDate] as? Date

        // Indexing after stop must not arm a timer that fires post-shutdown.
        try harness.writeFile(
            name: "AfterStop.swift",
            content: "func afterStop() -> Int { return 2 }"
        )
        try await harness.indexer.indexFile(at: path)
        try await Task.sleep(nanoseconds: 200_000_000)

        let after = try FileManager.default.attributesOfItem(atPath: vectorFile)
        let stillAt = after[.modificationDate] as? Date
        #expect(stillAt == savedAt, "a stray save fired after stop()")
    }

    // MARK: - Harness

    private struct Harness {
        let indexManager: IndexManager
        let indexer: IncrementalIndexer
        let recorder: EmbedRecorder
        let directory: URL

        init(
            dimension: Int,
            saveDebounceMs: Int = 0,
            persistent: Bool = false,
            failEmbeddings: Bool = false
        ) async throws {
            directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("swiftindex-incremental-\(UUID().uuidString)")
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let chunkStore = try GRDBChunkStore()
            let vectorPath = persistent
                ? directory.appendingPathComponent("vectors.usearch").path
                : nil
            let vectorStore = try USearchVectorStore(dimension: dimension, path: vectorPath)
            indexManager = IndexManager(chunkStore: chunkStore, vectorStore: vectorStore)

            recorder = EmbedRecorder()
            let chain = EmbeddingProviderChain(
                providers: [
                    CountingEmbeddingProvider(
                        dimension: dimension,
                        recorder: recorder,
                        shouldFail: failEmbeddings
                    ),
                ],
                id: "counting-chain",
                name: "Counting Chain"
            )

            indexer = IncrementalIndexer(
                indexManager: indexManager,
                parser: HybridParser(),
                embeddingProvider: chain,
                config: Config(),
                saveDebounceMs: saveDebounceMs
            )
        }

        /// Removes the harness's temporary directory.
        func cleanup() {
            try? FileManager.default.removeItem(at: directory)
        }

        @discardableResult
        func writeFile(name: String, content: String) throws -> String {
            let url = directory.appendingPathComponent(name)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url.path
        }
    }
}
