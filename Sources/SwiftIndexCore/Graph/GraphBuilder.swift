// MARK: - GraphBuilder

import Foundation
import Logging

/// Builds and maintains the symbol graph.
///
/// Split into two phases so the existing per-file, parallel indexing pipeline needs no
/// structural change: phase A records each file's symbols and unresolved edges inside
/// the same pass that produces chunks, and phase B resolves names once, when the whole
/// symbol table is known.
public actor GraphBuilder {
    private let chunkStore: GRDBChunkStore
    private let config: GraphConfig
    private let logger: Logger

    /// Local variable types per symbol, needed by the resolver's receiver typing and
    /// only available at parse time.
    private var localTypes: [String: [String: String]] = [:]

    public init(
        chunkStore: GRDBChunkStore,
        config: GraphConfig = GraphConfig(),
        logger: Logger = Logger(label: "GraphBuilder")
    ) {
        self.chunkStore = chunkStore
        self.config = config
        self.logger = logger
    }

    /// Records one file's contribution to the graph.
    ///
    /// Edges are written unresolved; resolution happens once at the end so a file can
    /// reference symbols that have not been parsed yet.
    public func record(
        facts: FileGraphFacts,
        chunks: [CodeChunk]
    ) async throws {
        guard config.enabled else { return }

        // Note which symbols this file used to define, so edges pointing at ones it no
        // longer defines can be unresolved rather than left dangling. Read by path so
        // the `idx_symbols_path` index applies: a full-table scan per file would make
        // indexing O(files x symbols).
        let previousIDs = try await Set(chunkStore.symbolIDs(forPath: facts.path))
        let currentIDs = Set(facts.symbols.map(\.id))
        let removed = previousIDs.subtracting(currentIDs)

        var chunkIDsByLine: [Int: String] = [:]
        for chunk in chunks {
            chunkIDsByLine[chunk.startLine] = chunk.id
        }

        try await chunkStore.replaceGraphFacts(facts, chunkIDsByLine: chunkIDsByLine)

        if !removed.isEmpty {
            try await chunkStore.invalidateEdges(targeting: Array(removed))
        }

        // A newly added symbol can change how *other* files' references resolve, but
        // only for rules that depend on how many symbols share a name. File-local
        // rules are unaffected, which is what keeps incremental resolution
        // proportional to the change rather than to the whole graph.
        let added = currentIDs.subtracting(previousIDs)
        if !added.isEmpty {
            let addedNames = facts.symbols.filter { added.contains($0.id) }.map(\.name)
            try await chunkStore.invalidateCardinalitySensitiveEdges(named: Array(Set(addedNames)))
        }

        try await chunkStore.insertEdges(Self.collapse(facts.references, path: facts.path))

        for (symbolID, types) in facts.localTypes {
            localTypes[symbolID] = types
        }
    }

    /// Whether a file has no symbols recorded yet.
    ///
    /// Used to backfill the graph for files whose chunks are already up to date, so
    /// enabling the graph on an existing index does not require a forced reindex.
    public func needsBackfill(path: String) async -> Bool {
        guard config.enabled else { return false }
        let existing = try? await chunkStore.symbolIDs(forPath: path)
        return (existing ?? []).isEmpty
    }

    /// Resolves every pending edge.
    ///
    /// - Returns: Number of edges resolved.
    @discardableResult
    public func resolve() async throws -> Int {
        guard config.enabled else { return 0 }

        // Marked dirty first so an interrupted pass is detectable and can be redone.
        try await chunkStore.setGraphMetaValue("dirty", "1")

        let resolver = SymbolResolver(config: config, logger: logger)
        let resolved = try await resolver.resolveAll(
            chunkStore: chunkStore,
            localTypesBySymbol: localTypes
        )

        let stats = try await chunkStore.graphStatistics()
        try await chunkStore.setGraphMetaValue("symbol_count", String(stats.symbols))
        try await chunkStore.setGraphMetaValue("edge_count", String(stats.edges))
        try await chunkStore.setGraphMetaValue("resolved_count", String(stats.resolved))
        try await chunkStore.setGraphMetaValue("dirty", "0")

        logger.info("Symbol graph resolved", metadata: [
            "symbols": "\(stats.symbols)",
            "edges": "\(stats.edges)",
            "resolved": "\(stats.resolved)",
        ])

        return resolved
    }

    /// Collapses repeated references into one edge with an occurrence count.
    ///
    /// Necessary, not merely an optimization: unresolved edges carry a NULL target,
    /// and SQLite's UNIQUE index treats NULLs as distinct, so the insert's ON CONFLICT
    /// never fires for them. Every repeated call would become its own row and they
    /// would then all resolve to the same target, colliding on the unique key. It also
    /// keeps the edge table roughly a third of the size it would otherwise be.
    static func collapse(_ references: [RawReference], path: String) -> [GraphEdge] {
        struct Key: Hashable {
            let source: String
            let name: String
            let kind: EdgeKind
        }

        var byKey: [Key: GraphEdge] = [:]
        var order: [Key] = []

        for reference in references {
            let key = Key(
                source: reference.enclosingSymbolID,
                name: reference.name,
                kind: reference.kind
            )
            if var existing = byKey[key] {
                existing.occurrences += 1
                byKey[key] = existing
            } else {
                order.append(key)
                byKey[key] = GraphEdge(
                    sourceID: reference.enclosingSymbolID,
                    targetName: reference.name,
                    kind: reference.kind,
                    provenance: .syntactic,
                    confidence: 0,
                    // Keep the first receiver seen: resolution only needs one example
                    // of how the symbol is reached.
                    occurrences: 1,
                    firstLine: reference.line,
                    receiver: reference.receiver,
                    sourcePath: path
                )
            }
        }

        return order.compactMap { byKey[$0] }
    }

    /// Infers a module name from a file path, without parsing Package.swift.
    ///
    /// `Sources/<Target>/...` covers essentially every SwiftPM layout and most Xcode
    /// ones, which is enough to scope resolution without adding a build-system
    /// dependency.
    public static func inferModule(path: String, projectRoot: String) -> String? {
        let relative = FileCollector.relativePath(
            of: URL(fileURLWithPath: path),
            from: FileCollector.canonicalPath(projectRoot)
        )
        let components = relative.split(separator: "/").map(String.init)
        guard components.count > 1 else { return nil }

        let roots = ["Sources", "Source", "Tests", "src"]

        for (index, component) in components.enumerated() where roots.contains(component) {
            let next = index + 1
            // Require a directory *after* the target name, otherwise `Sources/A.swift`
            // would report the module as "Sources".
            if next < components.count - 1 {
                return components[next]
            }
            return nil
        }

        // A leading root directory is a layout marker, not a module name.
        guard let first = components.first, !roots.contains(first) else { return nil }
        return first
    }
}
