// MARK: - GRDBChunkStore + Graph Migrations

import Foundation
import GRDB

extension GRDBChunkStore {
    /// Creates the symbol graph tables.
    ///
    /// Modelled on the existing `conformance_index` table, which is the precedent for
    /// a normalized relation alongside `chunks`. Unlike that table this one cannot be
    /// maintained by triggers: `conformance_index` is a pure function of one row's
    /// JSON, whereas edges are cross-file and must be written explicitly.
    nonisolated func registerSymbolGraphMigration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v11_symbol_graph") { db in
            try db.create(table: "symbols") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("qualified_name", .text).notNull()
                table.column("container", .text)
                table.column("module", .text)
                table.column("kind", .text).notNull()
                table.column("arg_labels", .text)
                table.column("arity", .integer)
                table.column("is_static", .boolean).notNull().defaults(to: false)
                table.column("is_requirement", .boolean).notNull().defaults(to: false)
                table.column("is_override", .boolean).notNull().defaults(to: false)
                table.column("access", .text)
                table.column("path", .text).notNull()
                table.column("start_line", .integer).notNull()
                table.column("end_line", .integer).notNull()
                // SET NULL rather than CASCADE: reindexing a file deletes and reinserts
                // its chunks every time, and cascading would destroy the file's symbols
                // (and every edge into them) on each touch.
                table.column("chunk_id", .text)
                    .references("chunks", onDelete: .setNull)
                // Reserved for exact identities from a compiler index store.
                table.column("usr", .text)
                table.column("in_degree", .integer).notNull().defaults(to: 0)
                table.column("file_hash", .text).notNull()
            }

            try db.create(index: "idx_symbols_name", on: "symbols", columns: ["name"])
            try db.create(index: "idx_symbols_qname", on: "symbols", columns: ["qualified_name"])
            try db.create(index: "idx_symbols_path", on: "symbols", columns: ["path"])
            try db.create(index: "idx_symbols_container", on: "symbols", columns: ["container", "name"])
            try db.create(index: "idx_symbols_module", on: "symbols", columns: ["module", "name"])

            try db.create(table: "edges") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("src_symbol_id", .text).notNull()
                table.column("dst_symbol_id", .text)
                // Kept even for resolved edges: it makes the graph queryable by name
                // before resolution runs, turns re-resolution into a pure UPDATE, and
                // keeps unresolved third-party calls visible as named leaves.
                table.column("dst_name", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("provenance", .text).notNull()
                table.column("confidence", .double).notNull().defaults(to: 0)
                table.column("ambiguity", .integer).notNull().defaults(to: 1)
                table.column("synthesized_by", .text)
                table.column("occurrences", .integer).notNull().defaults(to: 1)
                table.column("first_line", .integer)
                table.column("receiver", .text)
                table.column("src_path", .text).notNull()
                table.uniqueKey(["src_symbol_id", "dst_symbol_id", "dst_name", "kind"])
            }

            // Indexed in both directions: callees walk from the source, callers from
            // the target, and both must be fast.
            try db.create(index: "idx_edges_src", on: "edges", columns: ["src_symbol_id", "kind"])
            try db.create(index: "idx_edges_dst", on: "edges", columns: ["dst_symbol_id", "kind"])
            try db.create(index: "idx_edges_src_path", on: "edges", columns: ["src_path"])
            try db.create(index: "idx_edges_dst_name", on: "edges", columns: ["dst_name"])

            try db.create(table: "graph_meta") { table in
                table.column("k", .text).primaryKey()
                table.column("v", .text).notNull()
            }
        }
    }
}
