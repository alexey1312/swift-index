// MARK: - GRDBChunkStore

import Foundation
import GRDB

/// SQLite-based chunk storage using GRDB with FTS5 full-text search.
///
/// GRDBChunkStore provides persistent storage for `CodeChunk` and `InfoSnippet` objects with:
/// - Type-safe SQLite operations via GRDB
/// - FTS5 full-text search with BM25 ranking
/// - File hash tracking for incremental indexing
/// - Batch operations for efficient bulk inserts
public actor GRDBChunkStore: ChunkStore, InfoSnippetStore {
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
        databasePath = path

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

        dbWriter = try DatabasePool(path: path, configuration: config)
        try migrate()
    }

    /// Create an in-memory chunk store for testing.
    ///
    /// - Throws: If database creation fails.
    public init() throws {
        databasePath = ":memory:"
        // Use DatabaseQueue for in-memory databases (WAL not supported)
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        dbWriter = try DatabaseQueue(configuration: config)
        try migrate()
    }

    // MARK: - Migration

    private nonisolated func migrate() throws {
        var migrator = DatabaseMigrator()

        registerInitialMigration(&migrator)
        registerRichMetadataMigration(&migrator)
        registerInfoSnippetsMigration(&migrator)
        registerContentHashMigration(&migrator)
        registerGeneratedDescriptionMigration(&migrator)

        try migrator.migrate(dbWriter)
    }

    private nonisolated func registerInitialMigration(
        _ migrator: inout DatabaseMigrator
    ) {
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
    }

    private nonisolated func registerRichMetadataMigration(
        _ migrator: inout DatabaseMigrator
    ) {
        // Version 2: Rich metadata fields
        migrator.registerMigration("v2_rich_metadata") { db in
            // Add new metadata columns to chunks table
            try db.alter(table: "chunks") { table in
                table.add(column: "doc_comment", .text)
                table.add(column: "signature", .text)
                table.add(column: "breadcrumb", .text)
                table.add(column: "token_count", .integer).notNull().defaults(to: 0)
                table.add(column: "language", .text).notNull().defaults(to: "unknown")
            }

            // Drop old FTS table and triggers
            try db.execute(sql: "DROP TRIGGER IF EXISTS chunks_ai")
            try db.execute(sql: "DROP TRIGGER IF EXISTS chunks_ad")
            try db.execute(sql: "DROP TRIGGER IF EXISTS chunks_au")
            try db.execute(sql: "DROP TABLE IF EXISTS chunks_fts")

            // Create new FTS5 table with doc_comment column for search
            try db.execute(sql: """
                CREATE VIRTUAL TABLE chunks_fts USING fts5(
                    id UNINDEXED,
                    content,
                    symbols,
                    doc_comment,
                    path UNINDEXED,
                    content='chunks',
                    content_rowid='rowid',
                    tokenize='porter unicode61'
                )
            """)

            // New triggers including doc_comment
            try db.execute(sql: """
                CREATE TRIGGER chunks_ai AFTER INSERT ON chunks BEGIN
                    INSERT INTO chunks_fts(rowid, id, content, symbols, doc_comment, path)
                    VALUES (NEW.rowid, NEW.id, NEW.content, NEW.symbols, COALESCE(NEW.doc_comment, ''), NEW.path);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER chunks_ad AFTER DELETE ON chunks BEGIN
                    INSERT INTO chunks_fts(chunks_fts, rowid, id, content, symbols, doc_comment, path)
                    VALUES ('delete', OLD.rowid, OLD.id, OLD.content, OLD.symbols,
                            COALESCE(OLD.doc_comment, ''), OLD.path);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER chunks_au AFTER UPDATE ON chunks BEGIN
                    INSERT INTO chunks_fts(chunks_fts, rowid, id, content, symbols, doc_comment, path)
                    VALUES ('delete', OLD.rowid, OLD.id, OLD.content, OLD.symbols,
                            COALESCE(OLD.doc_comment, ''), OLD.path);
                    INSERT INTO chunks_fts(rowid, id, content, symbols, doc_comment, path)
                    VALUES (NEW.rowid, NEW.id, NEW.content, NEW.symbols,
                            COALESCE(NEW.doc_comment, ''), NEW.path);
                END
            """)

            // Rebuild FTS index with existing data
            try db.execute(sql: """
                INSERT INTO chunks_fts(rowid, id, content, symbols, doc_comment, path)
                SELECT rowid, id, content, symbols, COALESCE(doc_comment, ''), path FROM chunks
            """)
        }
    }

    private nonisolated func registerInfoSnippetsMigration(
        _ migrator: inout DatabaseMigrator
    ) {
        // Version 3: Info snippets for standalone documentation
        migrator.registerMigration("v3_info_snippets") { db in
            // Info snippets table for standalone documentation
            try db.create(table: "info_snippets") { table in
                table.primaryKey("id", .text)
                table.column("path", .text).notNull().indexed()
                table.column("content", .text).notNull()
                table.column("start_line", .integer).notNull()
                table.column("end_line", .integer).notNull()
                table.column("breadcrumb", .text)
                table.column("token_count", .integer).notNull().defaults(to: 0)
                table.column("language", .text).notNull().defaults(to: "unknown")
                table.column("chunk_id", .text).indexed() // Optional FK to chunks
                table.column("kind", .text).notNull().defaults(to: "documentation")
                table.column("file_hash", .text).notNull().indexed()
                table.column("created_at", .datetime).notNull()
            }

            // FTS5 virtual table for info snippet search
            try db.execute(sql: """
                CREATE VIRTUAL TABLE info_snippets_fts USING fts5(
                    id UNINDEXED,
                    content,
                    breadcrumb,
                    path UNINDEXED,
                    content='info_snippets',
                    content_rowid='rowid',
                    tokenize='porter unicode61'
                )
            """)

            // Triggers to keep FTS in sync
            try db.execute(sql: """
                CREATE TRIGGER info_snippets_ai AFTER INSERT ON info_snippets BEGIN
                    INSERT INTO info_snippets_fts(rowid, id, content, breadcrumb, path)
                    VALUES (NEW.rowid, NEW.id, NEW.content, COALESCE(NEW.breadcrumb, ''), NEW.path);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER info_snippets_ad AFTER DELETE ON info_snippets BEGIN
                    INSERT INTO info_snippets_fts(info_snippets_fts, rowid, id, content, breadcrumb, path)
                    VALUES ('delete', OLD.rowid, OLD.id, OLD.content, COALESCE(OLD.breadcrumb, ''), OLD.path);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER info_snippets_au AFTER UPDATE ON info_snippets BEGIN
                    INSERT INTO info_snippets_fts(info_snippets_fts, rowid, id, content, breadcrumb, path)
                    VALUES ('delete', OLD.rowid, OLD.id, OLD.content, COALESCE(OLD.breadcrumb, ''), OLD.path);
                    INSERT INTO info_snippets_fts(rowid, id, content, breadcrumb, path)
                    VALUES (NEW.rowid, NEW.id, NEW.content, COALESCE(NEW.breadcrumb, ''), NEW.path);
                END
            """)
        }
    }

    private nonisolated func registerContentHashMigration(
        _ migrator: inout DatabaseMigrator
    ) {
        // Version 4: Content hash for chunk-level change detection
        migrator.registerMigration("v4_content_hash") { db in
            // Add content_hash column to chunks table
            // Nullable initially, will be populated on next index
            try db.alter(table: "chunks") { table in
                table.add(column: "content_hash", .text)
            }

            // Create index for content hash lookups
            try db.create(index: "chunks_content_hash_idx", on: "chunks", columns: ["content_hash"])
        }
    }

    private nonisolated func registerGeneratedDescriptionMigration(
        _ migrator: inout DatabaseMigrator
    ) {
        // Version 5: LLM-generated descriptions for code chunks
        migrator.registerMigration("v5_generated_description") { db in
            // Add generated_description column to chunks table
            // Nullable - only populated when --generate-descriptions flag is used
            try db.alter(table: "chunks") { table in
                table.add(column: "generated_description", .text)
            }
        }
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

    public func getByContentHashes(_ hashes: Set<String>) async throws -> [String: CodeChunk] {
        guard !hashes.isEmpty else { return [:] }

        return try await dbWriter.read { db in
            var result: [String: CodeChunk] = [:]

            // Query in batches to avoid SQLite variable limit
            let hashArray = Array(hashes)
            for batch in stride(from: 0, to: hashArray.count, by: 500) {
                let batchHashes = Array(hashArray[batch ..< min(batch + 500, hashArray.count)])
                let placeholders = batchHashes.map { _ in "?" }.joined(separator: ", ")
                let sql = "SELECT * FROM chunks WHERE content_hash IN (\(placeholders))"

                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(batchHashes))
                for row in rows {
                    let record = ChunkRecord(row: row)
                    if let contentHash = record.contentHash {
                        result[contentHash] = try record.toCodeChunk()
                    }
                }
            }

            return result
        }
    }

    public func clear() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM chunks")
            try db.execute(sql: "DELETE FROM info_snippets")
            try db.execute(sql: "DELETE FROM file_hashes")
        }
    }

    // MARK: - InfoSnippetStore Protocol

    public func insertSnippet(_ snippet: InfoSnippet) async throws {
        try await dbWriter.write { db in
            try InfoSnippetRecord(snippet: snippet).insert(db)
        }
    }

    public func insertSnippetBatch(_ snippets: [InfoSnippet]) async throws {
        guard !snippets.isEmpty else { return }

        try await dbWriter.write { db in
            for snippet in snippets {
                try InfoSnippetRecord(snippet: snippet).insert(db)
            }
        }
    }

    public func getSnippet(id: String) async throws -> InfoSnippet? {
        try await dbWriter.read { db in
            try InfoSnippetRecord
                .filter(Column("id") == id)
                .fetchOne(db)?
                .toInfoSnippet()
        }
    }

    public func getSnippetsByPath(_ path: String) async throws -> [InfoSnippet] {
        try await dbWriter.read { db in
            try InfoSnippetRecord
                .filter(Column("path") == path)
                .order(Column("start_line"))
                .fetchAll(db)
                .map { try $0.toInfoSnippet() }
        }
    }

    public func getSnippetsByChunkId(_ chunkId: String) async throws -> [InfoSnippet] {
        try await dbWriter.read { db in
            try InfoSnippetRecord
                .filter(Column("chunk_id") == chunkId)
                .order(Column("start_line"))
                .fetchAll(db)
                .map { try $0.toInfoSnippet() }
        }
    }

    public func deleteSnippet(id: String) async throws {
        _ = try await dbWriter.write { db in
            try InfoSnippetRecord.deleteOne(db, key: id)
        }
    }

    public func deleteSnippetsByPath(_ path: String) async throws {
        _ = try await dbWriter.write { db in
            try InfoSnippetRecord
                .filter(Column("path") == path)
                .deleteAll(db)
        }
    }

    public func deleteSnippetsByChunkId(_ chunkId: String) async throws {
        _ = try await dbWriter.write { db in
            try InfoSnippetRecord
                .filter(Column("chunk_id") == chunkId)
                .deleteAll(db)
        }
    }

    public func searchSnippetsFTS(
        query: String,
        limit: Int
    ) async throws -> [(snippet: InfoSnippet, score: Double)] {
        guard !query.isEmpty else { return [] }

        let sanitizedQuery = sanitizeFTSQuery(query)

        return try await dbWriter.read { db in
            let sql = """
                SELECT info_snippets.*, bm25(info_snippets_fts) AS score
                FROM info_snippets_fts
                JOIN info_snippets ON info_snippets.id = info_snippets_fts.id
                WHERE info_snippets_fts MATCH ?
                ORDER BY score
                LIMIT ?
            """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [sanitizedQuery, limit])

            return try rows.map { row in
                let record = InfoSnippetRecord(row: row)
                let snippet = try record.toInfoSnippet()
                // BM25 returns negative scores (more negative = better match)
                let score = -(row["score"] as Double? ?? 0.0)
                return (snippet: snippet, score: score)
            }
        }
    }

    public func snippetCount() async throws -> Int {
        try await dbWriter.read { db in
            try InfoSnippetRecord.fetchCount(db)
        }
    }

    public func clearSnippets() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM info_snippets")
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
    let docComment: String?
    let signature: String?
    let breadcrumb: String?
    let tokenCount: Int
    let language: String
    let contentHash: String?
    let generatedDescription: String?

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
        case docComment = "doc_comment"
        case signature
        case breadcrumb
        case tokenCount = "token_count"
        case language
        case contentHash = "content_hash"
        case generatedDescription = "generated_description"
    }

    init(chunk: CodeChunk) {
        id = chunk.id
        path = chunk.path
        content = chunk.content
        startLine = chunk.startLine
        endLine = chunk.endLine
        kind = chunk.kind.rawValue
        symbols = (try? JSONCodec.makeEncoder().encode(chunk.symbols))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        references = (try? JSONCodec.makeEncoder().encode(chunk.references))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        fileHash = chunk.fileHash
        createdAt = chunk.createdAt
        docComment = chunk.docComment
        signature = chunk.signature
        breadcrumb = chunk.breadcrumb
        tokenCount = chunk.tokenCount
        language = chunk.language
        contentHash = chunk.contentHash
        generatedDescription = chunk.generatedDescription
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
        docComment = row["doc_comment"]
        signature = row["signature"]
        breadcrumb = row["breadcrumb"]
        tokenCount = row["token_count"] ?? 0
        language = row["language"] ?? "unknown"
        contentHash = row["content_hash"]
        generatedDescription = row["generated_description"]
    }

    func toCodeChunk() throws -> CodeChunk {
        guard let chunkKind = ChunkKind(rawValue: kind) else {
            throw ChunkStoreError.invalidKind(kind)
        }

        let symbolsArray: [String] = (try? JSONCodec.makeDecoder().decode(
            [String].self,
            from: Data(symbols.utf8)
        )) ?? []

        let referencesArray: [String] = (try? JSONCodec.makeDecoder().decode(
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
            createdAt: createdAt,
            docComment: docComment,
            signature: signature,
            breadcrumb: breadcrumb,
            tokenCount: tokenCount,
            language: language,
            contentHash: contentHash,
            generatedDescription: generatedDescription
        )
    }
}

// MARK: - InfoSnippetRecord

/// GRDB record for InfoSnippet persistence.
private struct InfoSnippetRecord: Codable, PersistableRecord, FetchableRecord {
    static let databaseTableName = "info_snippets"

    let id: String
    let path: String
    let content: String
    let startLine: Int
    let endLine: Int
    let breadcrumb: String?
    let tokenCount: Int
    let language: String
    let chunkId: String?
    let kind: String
    let fileHash: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case content
        case startLine = "start_line"
        case endLine = "end_line"
        case breadcrumb
        case tokenCount = "token_count"
        case language
        case chunkId = "chunk_id"
        case kind
        case fileHash = "file_hash"
        case createdAt = "created_at"
    }

    init(snippet: InfoSnippet) {
        id = snippet.id
        path = snippet.path
        content = snippet.content
        startLine = snippet.startLine
        endLine = snippet.endLine
        breadcrumb = snippet.breadcrumb
        tokenCount = snippet.tokenCount
        language = snippet.language
        chunkId = snippet.chunkId
        kind = snippet.kind.rawValue
        fileHash = snippet.fileHash
        createdAt = snippet.createdAt
    }

    init(row: Row) {
        id = row["id"]
        path = row["path"]
        content = row["content"]
        startLine = row["start_line"]
        endLine = row["end_line"]
        breadcrumb = row["breadcrumb"]
        tokenCount = row["token_count"] ?? 0
        language = row["language"] ?? "unknown"
        chunkId = row["chunk_id"]
        kind = row["kind"] ?? "documentation"
        fileHash = row["file_hash"]
        createdAt = row["created_at"]
    }

    func toInfoSnippet() throws -> InfoSnippet {
        guard let snippetKind = InfoSnippetKind(rawValue: kind) else {
            throw ChunkStoreError.invalidKind(kind)
        }

        return InfoSnippet(
            id: id,
            path: path,
            content: content,
            startLine: startLine,
            endLine: endLine,
            breadcrumb: breadcrumb,
            tokenCount: tokenCount,
            language: language,
            chunkId: chunkId,
            kind: snippetKind,
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
        case let .invalidKind(kind):
            "Invalid chunk kind: \(kind)"
        case let .databaseError(message):
            "Database error: \(message)"
        case let .migrationFailed(message):
            "Migration failed: \(message)"
        }
    }
}
