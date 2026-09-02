// MARK: - GRDBChunkStore + File Stats

import Foundation
import GRDB

/// Stat data recorded for an indexed file.
///
/// Size and modification time act as a prefilter for working-tree reconciliation:
/// a file whose size *and* mtime are unchanged is treated as clean without being
/// read, which turns a full-tree check from thousands of file reads plus SHA-256
/// into a single directory walk.
public struct FileStatRecord: Sendable, Equatable {
    public let path: String
    public let hash: String
    public let size: Int64?
    public let modifiedNanoseconds: Int64?

    public init(path: String, hash: String, size: Int64?, modifiedNanoseconds: Int64?) {
        self.path = path
        self.hash = hash
        self.size = size
        self.modifiedNanoseconds = modifiedNanoseconds
    }
}

public extension GRDBChunkStore {
    /// Reads stat data for every indexed file in one query.
    func allFileStats() async throws -> [String: FileStatRecord] {
        try await dbWriter.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT path, hash, size, mtime_ns FROM file_hashes"
            )
            var result: [String: FileStatRecord] = [:]
            result.reserveCapacity(rows.count)
            for row in rows {
                let path: String = row["path"]
                result[path] = FileStatRecord(
                    path: path,
                    hash: row["hash"],
                    size: row["size"],
                    modifiedNanoseconds: row["mtime_ns"]
                )
            }
            return result
        }
    }

    /// Records a file's hash together with its stat data.
    func setFileStat(
        _ hash: String,
        size: Int64?,
        modifiedNanoseconds: Int64?,
        forPath path: String
    ) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: """
                INSERT INTO file_hashes (path, hash, indexed_at, size, mtime_ns)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET
                    hash = excluded.hash,
                    indexed_at = excluded.indexed_at,
                    size = excluded.size,
                    mtime_ns = excluded.mtime_ns
                """,
                arguments: [path, hash, Date(), size, modifiedNanoseconds]
            )
        }
    }

    /// Updates stat data for files whose content is unchanged.
    ///
    /// Used when a file's mtime moved but its hash did not — common after a
    /// `git checkout` that rewrites unchanged files. Refreshing the stat data stops
    /// those files being re-hashed on every subsequent reconciliation.
    func refreshFileStats(_ records: [FileStatRecord]) async throws {
        guard !records.isEmpty else { return }
        try await dbWriter.write { db in
            for record in records {
                try db.execute(
                    sql: "UPDATE file_hashes SET size = ?, mtime_ns = ? WHERE path = ?",
                    arguments: [record.size, record.modifiedNanoseconds, record.path]
                )
            }
        }
    }
}
