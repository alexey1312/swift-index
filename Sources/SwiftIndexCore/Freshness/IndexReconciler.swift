// MARK: - IndexReconciler

import Foundation
import Logging

/// What a working-tree scan found relative to the index.
public struct ReconcileReport: Sendable, Equatable {
    /// Files present on disk but absent from the index.
    public var added: [FileEntry] = []

    /// Files whose content hash differs from the indexed one.
    public var modified: [FileEntry] = []

    /// Files whose mtime moved but whose content is identical.
    ///
    /// Common after `git checkout` rewrites unchanged files. These need only a stat
    /// refresh, never re-embedding.
    public var touched: [FileEntry] = []

    /// Indexed paths that no longer exist on disk.
    public var deleted: [String] = []

    /// Total files examined.
    public var scanned: Int = 0

    /// Files whose content had to be read and hashed because the stat prefilter
    /// could not rule them out.
    public var hashed: Int = 0

    /// Files needing (re-)indexing.
    public var changed: [FileEntry] {
        added + modified
    }

    /// Whether the index already matches the working tree.
    public var isClean: Bool {
        added.isEmpty && modified.isEmpty && deleted.isEmpty
    }
}

/// Compares the index against the working tree.
///
/// This is what lets an index absorb edits made while nothing was watching — a
/// different editor, a branch switch, or simply a session where no MCP server was
/// running. Without it, such changes are invisible until a full reindex.
public struct IndexReconciler: Sendable {
    private let parser: HybridParser
    private let logger: Logger

    public init(parser: HybridParser = HybridParser(), logger: Logger = Logger(label: "IndexReconciler")) {
        self.parser = parser
        self.logger = logger
    }

    /// Scans `path` and reports how the index differs from disk.
    ///
    /// Cost on a clean tree is one SQL query plus one directory walk: files whose
    /// size and mtime both match are accepted without being opened. Only files that
    /// fail that prefilter are read and hashed.
    ///
    /// - Parameters:
    ///   - path: Project root.
    ///   - config: Effective configuration.
    ///   - chunkStore: Store holding the recorded file stats.
    /// - Returns: The difference between disk and index.
    public func reconcile(
        path: String,
        config: Config,
        chunkStore: GRDBChunkStore
    ) async throws -> ReconcileReport {
        // Canonicalize stored paths before comparing. On macOS /var is a symlink to
        // /private/var, so an index built from one spelling of a project path would
        // otherwise appear entirely deleted and entirely re-added. Indexes written
        // before paths were canonicalized are absorbed here rather than forcing a
        // reindex.
        let rawStored = try await chunkStore.allFileStats()
        var stored: [String: FileStatRecord] = [:]
        var canonicalToStoredKey: [String: String] = [:]
        stored.reserveCapacity(rawStored.count)
        for (path, record) in rawStored {
            let canonical = FileCollector.canonicalPath(path)
            stored[canonical] = record
            canonicalToStoredKey[canonical] = path
        }

        let entries = try FileCollector.collect(
            at: path,
            config: config,
            parser: parser,
            logger: logger
        )

        var report = ReconcileReport()
        report.scanned = entries.count

        var seen = Set<String>()
        seen.reserveCapacity(entries.count)

        for entry in entries {
            seen.insert(entry.path)

            guard let record = stored[entry.path] else {
                report.added.append(entry)
                continue
            }

            // Stat prefilter. A NULL size/mtime means the row predates the prefilter
            // migration, so it falls through to hashing and gets backfilled.
            if let size = record.size,
               let mtime = record.modifiedNanoseconds,
               size == entry.size,
               mtime == entry.modifiedNanoseconds
            {
                continue
            }

            guard let contents = try? String(contentsOfFile: entry.path, encoding: .utf8) else {
                // Unreadable (binary, vanished mid-scan): treat as unchanged rather
                // than churning the index.
                continue
            }

            report.hashed += 1
            if FileHasher.hash(contents) == record.hash {
                report.touched.append(entry)
            } else {
                report.modified.append(entry)
            }
        }

        // Report deletions using the paths actually stored, so callers can remove
        // the right rows.
        report.deleted = stored.keys
            .filter { !seen.contains($0) }
            .compactMap { canonicalToStoredKey[$0] }
            .sorted()
        return report
    }

    /// Applies the cheap parts of a report: deletions and stat refreshes.
    ///
    /// Deletions are always applied in full regardless of volume, because they need
    /// no embeddings and stale results for removed files are the most misleading
    /// failure mode. Re-indexing changed files is left to the caller, which decides
    /// whether to block or catch up in the background.
    ///
    /// - Returns: Number of chunks removed for deleted files.
    @discardableResult
    public func applyDeletionsAndTouches(
        _ report: ReconcileReport,
        indexManager: IndexManager
    ) async throws -> Int {
        var removedChunks = 0

        for path in report.deleted {
            let chunks = try await indexManager.chunkStore.getByPath(path)
            for chunk in chunks {
                try await indexManager.vectorStore.delete(id: chunk.id)
            }
            try await indexManager.chunkStore.deleteByPath(path)
            try await indexManager.chunkStore.deleteSnippetsByPath(path)
            try await indexManager.chunkStore.deleteFileHash(path: path)
            removedChunks += chunks.count
        }

        if !report.touched.isEmpty {
            // Refresh stats so these files are not re-hashed on every future scan.
            let stored = try await indexManager.chunkStore.allFileStats()
            let refreshed = report.touched.compactMap { entry -> FileStatRecord? in
                guard let record = stored[entry.path] else { return nil }
                return FileStatRecord(
                    path: entry.path,
                    hash: record.hash,
                    size: entry.size,
                    modifiedNanoseconds: entry.modifiedNanoseconds
                )
            }
            try await indexManager.chunkStore.refreshFileStats(refreshed)
        }

        return removedChunks
    }
}
