// MARK: - GRDBChunkStore + Symbol Graph

import Foundation
import GRDB

/// Storage for the symbol graph.
///
/// Implemented as an extension on the existing store rather than a second store, so
/// there is exactly one `DatabasePool` and one WAL over `chunks.db`.
public extension GRDBChunkStore {
    // MARK: - Writing per-file facts

    /// Replaces everything a file contributes to the graph.
    ///
    /// Outgoing edges are invalidated wholesale by `src_path` — the entire
    /// invalidation story for a changed file's own references.
    func replaceGraphFacts(_ facts: FileGraphFacts, chunkIDsByLine: [Int: String]) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM edges WHERE src_path = ?", arguments: [facts.path])
            try db.execute(sql: "DELETE FROM symbols WHERE path = ?", arguments: [facts.path])

            for symbol in facts.symbols {
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO symbols
                    (id, name, qualified_name, container, module, kind, arg_labels, arity,
                     is_static, is_requirement, is_override, access, path, start_line,
                     end_line, chunk_id, in_degree, file_hash)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        symbol.id, symbol.name, symbol.qualifiedName, symbol.container,
                        symbol.module, symbol.kind.rawValue, symbol.argumentLabels, symbol.arity,
                        symbol.isStatic, symbol.isRequirement, symbol.isOverride, symbol.access,
                        symbol.path, symbol.startLine, symbol.endLine,
                        chunkIDsByLine[symbol.startLine], symbol.inDegree, symbol.fileHash,
                    ]
                )
            }
        }
    }

    /// Inserts edges, collapsing duplicates into an occurrence count.
    func insertEdges(_ edges: [GraphEdge]) async throws {
        guard !edges.isEmpty else { return }
        try await dbWriter.write { db in
            for edge in edges {
                try db.execute(
                    sql: """
                    INSERT INTO edges
                    (src_symbol_id, dst_symbol_id, dst_name, kind, provenance, confidence,
                     ambiguity, synthesized_by, occurrences, first_line, receiver, src_path)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(src_symbol_id, dst_symbol_id, dst_name, kind)
                    DO UPDATE SET occurrences = occurrences + excluded.occurrences
                    """,
                    arguments: [
                        edge.sourceID, edge.targetID, edge.targetName, edge.kind.rawValue,
                        edge.provenance.rawValue, edge.confidence, edge.ambiguity,
                        edge.synthesizedBy, edge.occurrences, edge.firstLine,
                        edge.receiver, edge.sourcePath,
                    ]
                )
            }
        }
    }

    // MARK: - Reading

    /// Every symbol, in the reduced form the resolver needs.
    func allSymbols() async throws -> [SymbolNode] {
        try await dbWriter.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM symbols").compactMap(Self.symbol(from:))
        }
    }

    /// Ids of symbols declared in a file.
    func symbolIDs(forPath path: String) async throws -> [String] {
        try await dbWriter.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM symbols WHERE path = ?", arguments: [path])
        }
    }

    /// Symbols matching a name or qualified name.
    func findSymbols(matching query: String, limit: Int) async throws -> [SymbolNode] {
        // An empty query would become `LIKE '%'` and match the entire table.
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return try await dbWriter.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM symbols
                WHERE name = ? OR qualified_name = ? OR qualified_name LIKE ?
                ORDER BY (name = ?) DESC, in_degree DESC
                LIMIT ?
                """,
                arguments: [trimmed, trimmed, "%.\(trimmed)", trimmed, limit]
            ).compactMap(Self.symbol(from:))
        }
    }

    /// A single symbol by id.
    func symbol(id: String) async throws -> SymbolNode? {
        try await dbWriter.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM symbols WHERE id = ?", arguments: [id])
                .flatMap(Self.symbol(from:))
        }
    }

    /// Edges the resolver has not attempted yet.
    ///
    /// Filtering on `synthesized_by IS NULL` rather than just a null target is what
    /// terminates the pass: an edge whose name genuinely cannot be resolved stays
    /// null-targeted forever, so re-fetching by target alone would loop.
    func unattemptedEdges(limit: Int) async throws -> [GraphEdge] {
        try await dbWriter.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM edges
                WHERE dst_symbol_id IS NULL AND synthesized_by IS NULL
                LIMIT ?
                """,
                arguments: [limit]
            ).compactMap(Self.edge(from:))
        }
    }

    /// Conformance relationships by name, used for protocol-witness fanout.
    ///
    /// Read by `dst_name` because these are needed *during* resolution, before the
    /// conformance edges themselves have targets.
    func conformancePairs() async throws -> [(type: String, protocolName: String)] {
        try await dbWriter.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT s.name AS type_name, e.dst_name AS protocol_name
                FROM edges e
                JOIN symbols s ON s.id = e.src_symbol_id
                WHERE e.kind = 'conforms'
                """
            ).map { (type: $0["type_name"], protocolName: $0["protocol_name"]) }
        }
    }

    /// Neighbours of a set of symbols in one direction.
    ///
    /// - Parameters:
    ///   - ids: Symbols to expand from.
    ///   - incoming: True for callers, false for callees.
    ///   - kinds: Edge kinds to traverse.
    ///   - minConfidence: Minimum edge confidence.
    func neighbours(
        of ids: [String],
        incoming: Bool,
        kinds: [EdgeKind],
        minConfidence: Double
    ) async throws -> [GraphEdge] {
        guard !ids.isEmpty, !kinds.isEmpty else { return [] }

        let matchColumn = incoming ? "dst_symbol_id" : "src_symbol_id"
        let idPlaceholders = ids.map { _ in "?" }.joined(separator: ", ")
        let kindPlaceholders = kinds.map { _ in "?" }.joined(separator: ", ")
        let sql = """
        SELECT * FROM edges
        WHERE \(matchColumn) IN (\(idPlaceholders))
          AND kind IN (\(kindPlaceholders))
          AND confidence >= ?
          AND dst_symbol_id IS NOT NULL
        """
        // Built as DatabaseValue so minConfidence stays numeric: passing it as text
        // would make SQLite compare a string against a REAL column and silently
        // filter out every edge.
        let values: [DatabaseValue] =
            ids.map(\.databaseValue)
                + kinds.map(\.rawValue.databaseValue)
                + [minConfidence.databaseValue]
        let statementArguments = StatementArguments(values)

        return try await dbWriter.read { db in
            try Row.fetchAll(db, sql: sql, arguments: statementArguments)
                .compactMap(Self.edge(from:))
        }
    }

    /// How many edges leaving a set of symbols have no resolved target.
    ///
    /// Reported separately because `neighbours` filters them out: without this the
    /// "traversal is incomplete" signal would always read zero and quietly imply the
    /// graph had reached a genuine boundary.
    func unresolvedNeighbourCount(of ids: [String], kinds: [EdgeKind]) async throws -> Int {
        guard !ids.isEmpty, !kinds.isEmpty else { return 0 }
        let idPlaceholders = ids.map { _ in "?" }.joined(separator: ", ")
        let kindPlaceholders = kinds.map { _ in "?" }.joined(separator: ", ")
        let sql = """
        SELECT COUNT(*) FROM edges
        WHERE src_symbol_id IN (\(idPlaceholders))
          AND kind IN (\(kindPlaceholders))
          AND dst_symbol_id IS NULL
        """
        let values: [DatabaseValue] = ids.map(\.databaseValue) + kinds.map(\.rawValue.databaseValue)
        return try await dbWriter.read { db in
            try Int.fetchOne(db, sql: sql, arguments: StatementArguments(values)) ?? 0
        }
    }

    /// Edges leaving a symbol, including unresolved ones.
    ///
    /// Unresolved edges are what make third-party calls visible rather than absent.
    func outgoingEdges(from id: String, minConfidence: Double) async throws -> [GraphEdge] {
        try await dbWriter.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM edges WHERE src_symbol_id = ? AND confidence >= ?",
                arguments: [id, minConfidence]
            ).compactMap(Self.edge(from:))
        }
    }

    // MARK: - Resolution support

    /// Applies a resolved target to an edge.
    ///
    /// `OR IGNORE` so that if two edges would collapse onto the same target the
    /// duplicate is left unresolved rather than aborting the entire resolution pass.
    func updateEdgeResolution(_ update: EdgeResolution) async throws {
        let sourceID = update.sourceID
        let targetName = update.targetName
        let kind = update.kind
        let targetID = update.targetID
        let provenance = update.provenance
        let confidence = update.confidence
        let ambiguity = update.ambiguity
        let synthesizedBy = update.synthesizedBy

        try await dbWriter.write { db in
            try db.execute(
                sql: """
                UPDATE OR IGNORE edges
                SET dst_symbol_id = ?, provenance = ?, confidence = ?,
                    ambiguity = ?, synthesized_by = ?
                WHERE src_symbol_id = ? AND dst_name = ? AND kind = ? AND dst_symbol_id IS NULL
                """,
                arguments: [
                    targetID, provenance.rawValue, confidence, ambiguity, synthesizedBy,
                    sourceID, targetName, kind.rawValue,
                ]
            )
        }
    }

    /// Unresolves edges whose target no longer exists.
    ///
    /// `synthesized_by` is cleared as well as the target: the resolver selects work
    /// by `synthesized_by IS NULL`, so leaving a marker behind would strand the edge
    /// as permanently unresolved instead of re-attempting it.
    ///
    /// Called when a file's symbols are removed or renamed, so incoming edges do not
    /// keep pointing at ids that are gone.
    func invalidateEdges(targeting removedIDs: [String]) async throws {
        guard !removedIDs.isEmpty else { return }
        try await dbWriter.write { db in
            for batch in stride(from: 0, to: removedIDs.count, by: 500) {
                let slice = Array(removedIDs[batch ..< min(batch + 500, removedIDs.count)])
                let placeholders = slice.map { _ in "?" }.joined(separator: ", ")
                try db.execute(
                    sql: """
                    UPDATE edges
                    SET dst_symbol_id = NULL, confidence = 0, synthesized_by = NULL
                    WHERE dst_symbol_id IN (\(placeholders))
                    """,
                    arguments: StatementArguments(slice)
                )
            }
        }
    }

    /// Unresolves edges whose resolution depended on how many symbols shared a name.
    ///
    /// Adding a symbol elsewhere can change these verdicts, but never the file-local
    /// ones — which is what keeps incremental resolution proportional to the change
    /// rather than to the whole graph.
    func invalidateCardinalitySensitiveEdges(named names: [String]) async throws {
        guard !names.isEmpty else { return }
        let sensitive = ["global-unique", "global-name-fanout", "module-scope", "too-ambiguous"]
        try await dbWriter.write { db in
            for name in names {
                var arguments: [any DatabaseValueConvertible] = [name]
                arguments.append(contentsOf: sensitive)
                try db.execute(
                    sql: """
                    UPDATE edges
                    SET dst_symbol_id = NULL, confidence = 0, synthesized_by = NULL
                    WHERE dst_name = ?
                      AND synthesized_by IN (?, ?, ?, ?)
                    """,
                    arguments: StatementArguments(arguments)
                )
            }
        }
    }

    /// Recomputes confidence-weighted incoming call counts.
    func recomputeInDegrees() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "UPDATE symbols SET in_degree = 0")
            try db.execute(
                sql: """
                UPDATE symbols SET in_degree = (
                    SELECT COALESCE(SUM(occurrences), 0) FROM edges
                    WHERE edges.dst_symbol_id = symbols.id
                      AND edges.kind IN ('calls', 'initializes')
                      AND edges.confidence >= 0.5
                )
                """
            )
        }
    }

    // MARK: - Metadata

    func graphMetaValue(_ key: String) async throws -> String? {
        try await dbWriter.read { db in
            try String.fetchOne(db, sql: "SELECT v FROM graph_meta WHERE k = ?", arguments: [key])
        }
    }

    func setGraphMetaValue(_ key: String, _ value: String) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: "INSERT INTO graph_meta (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v",
                arguments: [key, value]
            )
        }
    }

    /// Counts for diagnostics.
    func graphStatistics() async throws -> (symbols: Int, edges: Int, resolved: Int) {
        try await dbWriter.read { db in
            let symbols = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM symbols") ?? 0
            let edges = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM edges") ?? 0
            let resolved = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM edges WHERE dst_symbol_id IS NOT NULL"
            ) ?? 0
            return (symbols, edges, resolved)
        }
    }

    // MARK: - Row mapping

    private static func symbol(from row: Row) -> SymbolNode? {
        guard let kind = SymbolKind(rawValue: row["kind"]) else { return nil }
        return SymbolNode(
            id: row["id"],
            name: row["name"],
            qualifiedName: row["qualified_name"],
            container: row["container"],
            module: row["module"],
            kind: kind,
            argumentLabels: row["arg_labels"],
            arity: row["arity"] ?? -1,
            isStatic: row["is_static"] ?? false,
            isRequirement: row["is_requirement"] ?? false,
            isOverride: row["is_override"] ?? false,
            access: row["access"],
            path: row["path"],
            startLine: row["start_line"],
            endLine: row["end_line"],
            chunkID: row["chunk_id"],
            inDegree: row["in_degree"] ?? 0,
            fileHash: row["file_hash"]
        )
    }

    private static func edge(from row: Row) -> GraphEdge? {
        guard let kind = EdgeKind(rawValue: row["kind"]),
              let provenance = EdgeProvenance(rawValue: row["provenance"])
        else {
            return nil
        }
        return GraphEdge(
            sourceID: row["src_symbol_id"],
            targetID: row["dst_symbol_id"],
            targetName: row["dst_name"],
            kind: kind,
            provenance: provenance,
            confidence: row["confidence"] ?? 0,
            ambiguity: row["ambiguity"] ?? 1,
            synthesizedBy: row["synthesized_by"],
            occurrences: row["occurrences"] ?? 1,
            firstLine: row["first_line"],
            receiver: row["receiver"],
            sourcePath: row["src_path"]
        )
    }
}
