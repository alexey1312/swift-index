// MARK: - GRDBChunkStore

import Foundation
import GRDB

/// SQLite-based chunk storage using GRDB with FTS5 full-text search.
///
/// GRDBChunkStore provides persistent storage for `CodeChunk` objects with:
/// - Type-safe SQLite operations via GRDB
/// - FTS5 full-text search with BM25 ranking
/// - File hash tracking for incremental indexing
/// - Batch operations for efficient bulk inserts
public actor GRDBChunkStore: ChunkStore {
    // MARK: - Properties

    /// The database writer (can be DatabasePool or DatabaseQueue).
    private let dbWriter: any DatabaseWriter

    /// The path to the database file.
    public let databasePath: String

    // MARK: - Initialization

    /// Create a new chunk store at the specified path.
    ///
    /// - Parameter path: Path to the SQLite database file.
    /// - Throws: If database creation or migration fails.
    public init(path: String) throws {
        self.databasePath = path

        // Ensure directory exists
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        // Create database pool with recommended settings
        var config = Configuration()
        config.prepareDatabase { db in
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            // WAL mode for better concurrent read/write performance
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }

        self.dbWriter = try DatabasePool(path: path, configuration: config)
        try migrate()
    }

    /// Create an in-memory chunk store for testing.
    ///
    /// - Throws: If database creation fails.
    public init() throws {
        self.databasePath = ":memory:"
        // Use DatabaseQueue for in-memory databases (WAL not supported)
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        self.dbWriter = try DatabaseQueue(configuration: config)
        try migrate()
    }

    // MARK: - Migration

    private nonisolated func migrate() throws {
        var migrator = DatabaseMigrator()

        // Version 1: Initial schema
        migrator.registerMigration("v1_initial") { db in
            // Main chunks table
            try db.create(table: "chunks") { table in
                table.primaryKey("id", .text)
                table.column("path", .text).notNull().indexed()
                table.column("content", .text).notNull()
                table.column("start_line", .integer).notNull()
                table.column("end_line", .integer).notNull()
                table.column("kind", .text).notNull()
                table.column("symbols", .text).notNull() // JSON array
                table.column("references", .text).notNull() // JSON array
                table.column("file_hash", .text).notNull().indexed()
                table.column("created_at", .datetime).notNull()
            }

            // FTS5 virtual table for full-text search
            try db.execute(sql: """
                CREATE VIRTUAL TABLE chunks_fts USING fts5(
                    id UNINDEXED,
                    content,
                    symbols,
                    path UNINDEXED,
                    content='chunks',
                    content_rowid='rowid',
                    tokenize='porter unicode61'
                )
            """)

            // Triggers to keep FTS in sync
            try db.execute(sql: """
                CREATE TRIGGER chunks_ai AFTER INSERT ON chunks BEGIN
                    INSERT INTO chunks_fts(rowid, id, content, symbols, path)
                    VALUES (NEW.rowid, NEW.id, NEW.content, NEW.symbols, NEW.path);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER chunks_ad AFTER DELETE ON chunks BEGIN
                    INSERT INTO chunks_fts(chunks_fts, rowid, id, content, symbols, path)
                    VALUES ('delete', OLD.rowid, OLD.id, OLD.content, OLD.symbols, OLD.path);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER chunks_au AFTER UPDATE ON chunks BEGIN
                    INSERT INTO chunks_fts(chunks_fts, rowid, id, content, symbols, path)
                    VALUES ('delete', OLD.rowid, OLD.id, OLD.content, OLD.symbols, OLD.path);
                    INSERT INTO chunks_fts(rowid, id, content, symbols, path)
                    VALUES (NEW.rowid, NEW.id, NEW.content, NEW.symbols, NEW.path);
                END
            """)

            // File hashes table for incremental indexing
            try db.create(table: "file_hashes") { table in
                table.primaryKey("hash", .text)
                table.column("path", .text).notNull()
                table.column("indexed_at", .datetime).notNull()
            }
        }

        try migrator.migrate(dbWriter)
    }

    // MARK: - ChunkStore Protocol

    public func insert(_ chunk: CodeChunk) async throws {
        try await dbWriter.write { db in
            try ChunkRecord(chunk: chunk).insert(db)
        }
    }

    public func insertBatch(_ chunks: [CodeChunk]) async throws {
        guard !chunks.isEmpty else { return }

        try await dbWriter.write { db in
            for chunk in chunks {
                try ChunkRecord(chunk: chunk).insert(db)
            }
        }
    }

    public func get(id: String) async throws -> CodeChunk? {
        try await dbWriter.read { db in
            try ChunkRecord
                .filter(Column("id") == id)
                .fetchOne(db)?
                .toCodeChunk()
        }
    }

    public func getByPath(_ path: String) async throws -> [CodeChunk] {
        try await dbWriter.read { db in
            try ChunkRecord
                .filter(Column("path") == path)
                .order(Column("start_line"))
                .fetchAll(db)
                .map { try $0.toCodeChunk() }
        }
    }

    public func update(_ chunk: CodeChunk) async throws {
        try await dbWriter.write { db in
            try ChunkRecord(chunk: chunk).update(db)
        }
    }

    public func delete(id: String) async throws {
        _ = try await dbWriter.write { db in
            try ChunkRecord.deleteOne(db, key: id)
        }
    }

    public func deleteByPath(_ path: String) async throws {
        _ = try await dbWriter.write { db in
            try ChunkRecord
                .filter(Column("path") == path)
                .deleteAll(db)
        }
    }

    public func searchFTS(
        query: String,
        limit: Int
    ) async throws -> [(chunk: CodeChunk, score: Double)] {
        guard !query.isEmpty else { return [] }

        // Escape special FTS5 characters and prepare query
        let sanitizedQuery = sanitizeFTSQuery(query)

        return try await dbWriter.read { db in
            let sql = """
                SELECT chunks.*, bm25(chunks_fts) AS score
                FROM chunks_fts
                JOIN chunks ON chunks.id = chunks_fts.id
                WHERE chunks_fts MATCH ?
                ORDER BY score
                LIMIT ?
            """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [sanitizedQuery, limit])

            return try rows.map { row in
                let record = ChunkRecord(row: row)
                let chunk = try record.toCodeChunk()
                // BM25 returns negative scores (more negative = better match)
                // Convert to positive scores where higher is better
                let score = -(row["score"] as Double? ?? 0.0)
                return (chunk: chunk, score: score)
            }
        }
    }

    public func allIDs() async throws -> [String] {
        try await dbWriter.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM chunks")
        }
    }

    public func count() async throws -> Int {
        try await dbWriter.read { db in
            try ChunkRecord.fetchCount(db)
        }
    }

    public func hasFileHash(_ hash: String) async throws -> Bool {
        try await dbWriter.read { db in
            try FileHashRecord.exists(db, key: hash)
        }
    }

    public func recordFileHash(_ hash: String, path: String) async throws {
        try await dbWriter.write { db in
            try FileHashRecord(hash: hash, path: path, indexedAt: Date()).insert(db)
        }
    }

    public func clear() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM chunks")
            try db.execute(sql: "DELETE FROM file_hashes")
        }
    }

    // MARK: - Additional Methods

    /// Delete file hash records for a path (for reindexing).
    ///
    /// - Parameter path: The file path.
    public func deleteFileHash(path: String) async throws {
        _ = try await dbWriter.write { db in
            try FileHashRecord
                .filter(Column("path") == path)
                .deleteAll(db)
        }
    }

    /// Get all unique file paths that have been indexed.
    ///
    /// - Returns: Array of file paths.
    public func allPaths() async throws -> [String] {
        try await dbWriter.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT path FROM chunks")
        }
    }

    /// Get chunks by their IDs.
    ///
    /// - Parameter ids: The chunk IDs to fetch.
    /// - Returns: Array of chunks (may be fewer than requested if some IDs not found).
    public func getByIDs(_ ids: [String]) async throws -> [CodeChunk] {
        guard !ids.isEmpty else { return [] }

        return try await dbWriter.read { db in
            try ChunkRecord
                .filter(ids.contains(Column("id")))
                .fetchAll(db)
                .map { try $0.toCodeChunk() }
        }
    }

    // MARK: - Private Helpers

    private nonisolated func sanitizeFTSQuery(_ query: String) -> String {
        // Remove FTS5 special characters that could cause syntax errors
        let specialChars = CharacterSet(charactersIn: "\"*():-^")
        let words = query
            .components(separatedBy: specialChars)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Join with OR for broader matching, wrap in quotes for phrase matching
        if words.count == 1 {
            return "\(words[0])*"
        }
        return words.map { "\($0)*" }.joined(separator: " OR ")
    }
}

// MARK: - ChunkRecord

/// GRDB record for CodeChunk persistence.
private struct ChunkRecord: Codable, PersistableRecord, FetchableRecord {
    static let databaseTableName = "chunks"

    let id: String
    let path: String
    let content: String
    let startLine: Int
    let endLine: Int
    let kind: String
    let symbols: String // JSON array
    let references: String // JSON array
    let fileHash: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case content
        case startLine = "start_line"
        case endLine = "end_line"
        case kind
        case symbols
        case references
        case fileHash = "file_hash"
        case createdAt = "created_at"
    }

    init(chunk: CodeChunk) {
        self.id = chunk.id
        self.path = chunk.path
        self.content = chunk.content
        self.startLine = chunk.startLine
        self.endLine = chunk.endLine
        self.kind = chunk.kind.rawValue
        self.symbols = (try? JSONEncoder().encode(chunk.symbols))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.references = (try? JSONEncoder().encode(chunk.references))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.fileHash = chunk.fileHash
        self.createdAt = chunk.createdAt
    }

    init(row: Row) {
        id = row["id"]
        path = row["path"]
        content = row["content"]
        startLine = row["start_line"]
        endLine = row["end_line"]
        kind = row["kind"]
        symbols = row["symbols"]
        references = row["references"]
        fileHash = row["file_hash"]
        createdAt = row["created_at"]
    }

    func toCodeChunk() throws -> CodeChunk {
        guard let chunkKind = ChunkKind(rawValue: kind) else {
            throw ChunkStoreError.invalidKind(kind)
        }

        let symbolsArray: [String] = (try? JSONDecoder().decode(
            [String].self,
            from: Data(symbols.utf8)
        )) ?? []

        let referencesArray: [String] = (try? JSONDecoder().decode(
            [String].self,
            from: Data(references.utf8)
        )) ?? []

        return CodeChunk(
            id: id,
            path: path,
            content: content,
            startLine: startLine,
            endLine: endLine,
            kind: chunkKind,
            symbols: symbolsArray,
            references: referencesArray,
            fileHash: fileHash,
            createdAt: createdAt
        )
    }
}

// MARK: - FileHashRecord

/// GRDB record for file hash tracking.
private struct FileHashRecord: Codable, PersistableRecord, FetchableRecord {
    static let databaseTableName = "file_hashes"

    let hash: String
    let path: String
    let indexedAt: Date

    enum CodingKeys: String, CodingKey {
        case hash
        case path
        case indexedAt = "indexed_at"
    }
}

// MARK: - ChunkStoreError

/// Errors specific to chunk store operations.
public enum ChunkStoreError: Error, Sendable {
    case invalidKind(String)
    case databaseError(String)
    case migrationFailed(String)
}

extension ChunkStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidKind(let kind):
            return "Invalid chunk kind: \(kind)"
        case .databaseError(let message):
            return "Database error: \(message)"
        case .migrationFailed(let message):
            return "Migration failed: \(message)"
        }
    }
}
