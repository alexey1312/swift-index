import Foundation
@testable import SwiftIndexCore
import Testing

/// Counts how many files the reconciler had to open, to prove the stat prefilter works.
private actor HashCounter {
    private(set) var count = 0
    func record() {
        count += 1
    }
}

@Suite("IndexReconciler Tests")
struct IndexReconcilerTests {
    private struct Harness {
        let root: URL
        let indexManager: IndexManager
        let config: Config

        init() async throws {
            root = URL(fileURLWithPath: NSTemporaryDirectory())
                .resolvingSymlinksInPath()
                .appendingPathComponent("swiftindex-reconcile-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            indexManager = try IndexManager(
                chunkStore: GRDBChunkStore(),
                vectorStore: USearchVectorStore(dimension: 4)
            )
            config = Config()
        }

        @discardableResult
        func write(_ name: String, _ contents: String) throws -> String {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url.path
        }

        /// Indexes a file the way the real pipeline does, recording stat data.
        func index(_ path: String) async throws {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            let hash = FileHasher.hash(contents)
            let result = HybridParser().parse(content: contents, path: path, fileHash: hash)
            _ = try await indexManager.indexFile(
                path: path,
                fileHash: hash,
                parseResult: result,
                embedder: { chunks in chunks.map { _ in [Float](repeating: 0.1, count: 4) } }
            )
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test("A clean tree reports no changes and reads no files")
    func cleanTreeNeedsNoHashing() async throws {
        let harness = try await Harness()
        defer { harness.cleanup() }

        let path = try harness.write("Sources/App.swift", "func app() -> Int { 1 }")
        try await harness.index(path)

        let report = try await IndexReconciler().reconcile(
            path: harness.root.path,
            config: harness.config,
            chunkStore: harness.indexManager.chunkStore
        )

        #expect(report.isClean)
        #expect(report.scanned == 1)
        // The whole point of the size+mtime prefilter: an unchanged file is never read.
        #expect(report.hashed == 0)
    }

    @Test("A new file is reported as added")
    func addedFile() async throws {
        let harness = try await Harness()
        defer { harness.cleanup() }

        let indexed = try harness.write("Sources/App.swift", "func app() -> Int { 1 }")
        try await harness.index(indexed)
        try harness.write("Sources/New.swift", "func new() -> Int { 2 }")

        let report = try await IndexReconciler().reconcile(
            path: harness.root.path,
            config: harness.config,
            chunkStore: harness.indexManager.chunkStore
        )

        #expect(report.added.count == 1)
        #expect(report.added.first?.path.hasSuffix("New.swift") == true)
        #expect(!report.isClean)
    }

    @Test("Edited content is reported as modified")
    func modifiedFile() async throws {
        let harness = try await Harness()
        defer { harness.cleanup() }

        let path = try harness.write("Sources/App.swift", "func app() -> Int { 1 }")
        try await harness.index(path)
        try harness.write("Sources/App.swift", "func app() -> Int { 999 }")

        let report = try await IndexReconciler().reconcile(
            path: harness.root.path,
            config: harness.config,
            chunkStore: harness.indexManager.chunkStore
        )

        #expect(report.modified.count == 1)
        #expect(report.hashed == 1)
    }

    @Test("A touched-but-identical file is not treated as modified")
    func touchedFile() async throws {
        let harness = try await Harness()
        defer { harness.cleanup() }

        let path = try harness.write("Sources/App.swift", "func app() -> Int { 1 }")
        try await harness.index(path)

        // Rewrite identical content, as `git checkout` does for unchanged files.
        try harness.write("Sources/App.swift", "func app() -> Int { 1 }")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: path
        )

        let report = try await IndexReconciler().reconcile(
            path: harness.root.path,
            config: harness.config,
            chunkStore: harness.indexManager.chunkStore
        )

        #expect(report.modified.isEmpty)
        #expect(report.touched.count == 1)
        #expect(report.isClean, "an mtime-only change must not require re-embedding")
    }

    @Test("A removed file is reported and cleaned up")
    func deletedFile() async throws {
        let harness = try await Harness()
        defer { harness.cleanup() }

        let path = try harness.write("Sources/Gone.swift", "func gone() -> Int { 1 }")
        try await harness.index(path)
        try FileManager.default.removeItem(atPath: path)

        let reconciler = IndexReconciler()
        let report = try await reconciler.reconcile(
            path: harness.root.path,
            config: harness.config,
            chunkStore: harness.indexManager.chunkStore
        )

        #expect(report.deleted == [path])

        try await reconciler.applyDeletionsAndTouches(report, indexManager: harness.indexManager)

        let remaining = try await harness.indexManager.chunkStore.getByPath(path)
        let hash = try await harness.indexManager.chunkStore.getFileHash(forPath: path)
        #expect(remaining.isEmpty)
        #expect(hash == nil)
    }

    @Test("Rows predating the stat columns are hashed once, then skipped")
    func nullStatsBackfill() async throws {
        let harness = try await Harness()
        defer { harness.cleanup() }

        let path = try harness.write("Sources/App.swift", "func app() -> Int { 1 }")
        try await harness.index(path)

        // Simulate a pre-migration row: hash present, stat data absent.
        try await harness.indexManager.chunkStore.setFileStat(
            FileHasher.hash(String(contentsOfFile: path, encoding: .utf8)),
            size: nil,
            modifiedNanoseconds: nil,
            forPath: path
        )

        let reconciler = IndexReconciler()
        let first = try await reconciler.reconcile(
            path: harness.root.path,
            config: harness.config,
            chunkStore: harness.indexManager.chunkStore
        )
        // NULL stats mean "must hash", but the content matches so nothing changed.
        #expect(first.hashed == 1)
        #expect(first.isClean)

        try await reconciler.applyDeletionsAndTouches(first, indexManager: harness.indexManager)

        let second = try await reconciler.reconcile(
            path: harness.root.path,
            config: harness.config,
            chunkStore: harness.indexManager.chunkStore
        )
        // Backfilled by the first pass, so the prefilter now short-circuits.
        #expect(second.hashed == 0)
    }
}
