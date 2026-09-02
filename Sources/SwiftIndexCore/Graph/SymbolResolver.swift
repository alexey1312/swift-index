// MARK: - SymbolResolver

import Foundation
import Logging

/// Resolves bare reference names into graph edges.
///
/// SwiftSyntax gives syntax without types: `foo.bar()` yields the name `bar` with no
/// idea what `foo` is. Rather than requiring a compiler index store — which needs a
/// completed build and so destroys the zero-configuration property — resolution is
/// done by scoping rules, and every edge records which rule produced it and how much
/// to trust it. That honesty is what makes heuristic edges usable.
public actor SymbolResolver {
    /// Ranked resolution rules. The first to produce candidates wins.
    enum Rule: String {
        case selfContainer = "self-container"
        case sameFile = "same-file"
        case receiverType = "receiver-type"
        case receiverVarType = "receiver-var-type"
        case moduleScope = "module-scope"
        case globalUnique = "global-unique"
        case globalFanout = "global-name-fanout"
        case tooAmbiguous = "too-ambiguous"
        case unresolved

        /// Confidence when exactly one candidate matched, and when several did.
        var confidence: (unique: Double, ambiguous: Double) {
            switch self {
            case .selfContainer: (0.95, 0.70)
            case .sameFile: (0.95, 0.70)
            case .receiverType: (0.90, 0.65)
            case .receiverVarType: (0.85, 0.60)
            case .moduleScope: (0.75, 0.50)
            case .globalUnique: (0.80, 0.80)
            case .globalFanout: (0.50, 0.50)
            case .tooAmbiguous: (0.10, 0.10)
            case .unresolved: (0.0, 0.0)
            }
        }
    }

    private let config: GraphConfig
    private let logger: Logger

    /// Lookup tables built once per pass.
    private var byName: [String: [SymbolNode]] = [:]
    private var byContainer: [String: [SymbolNode]] = [:]
    private var byID: [String: SymbolNode] = [:]
    /// Types conforming to each protocol, for witness fanout.
    private var conformersByProtocol: [String: [SymbolNode]] = [:]

    public init(config: GraphConfig = GraphConfig(), logger: Logger = Logger(label: "SymbolResolver")) {
        self.config = config
        self.logger = logger
    }

    /// Resolves every unresolved edge in the store.
    ///
    /// - Returns: How many edges were resolved.
    @discardableResult
    public func resolveAll(
        chunkStore: GRDBChunkStore,
        localTypesBySymbol: [String: [String: String]] = [:]
    ) async throws -> Int {
        let symbols = try await chunkStore.allSymbols()
        buildTables(from: symbols)
        try await loadConformances(chunkStore.conformancePairs(), symbols: symbols)

        var resolvedCount = 0
        var witnessEdges: [GraphEdge] = []

        // Stream in batches: the lookup tables are the only global state, and they are
        // bounded by the symbol count rather than the edge count.
        while true {
            let batch = try await chunkStore.unattemptedEdges(limit: 5000)
            guard !batch.isEmpty else { break }

            for edge in batch {
                let outcome = resolve(
                    edge: edge,
                    localTypes: visibleTypes(for: edge.sourceID, in: localTypesBySymbol)
                )

                try await chunkStore.updateEdgeResolution(EdgeResolution(
                    sourceID: edge.sourceID,
                    targetName: edge.targetName,
                    kind: edge.kind,
                    targetID: outcome.targetID,
                    provenance: outcome.provenance,
                    confidence: outcome.confidence,
                    ambiguity: outcome.ambiguity,
                    synthesizedBy: outcome.rule.rawValue
                ))

                if outcome.targetID != nil {
                    resolvedCount += 1
                }
                witnessEdges.append(contentsOf: witnessFanout(for: edge, outcome: outcome))
            }
        }

        if !witnessEdges.isEmpty {
            try await chunkStore.insertEdges(witnessEdges)
        }
        try await chunkStore.recomputeInDegrees()

        return resolvedCount
    }

    // MARK: - Resolution

    struct Outcome {
        let targetID: String?
        let rule: Rule
        let confidence: Double
        let ambiguity: Int
        let provenance: EdgeProvenance
    }

    func resolve(edge: GraphEdge, localTypes: [String: String]) -> Outcome {
        let source = byID[edge.sourceID]
        let candidatesByRule = candidates(for: edge, source: source, localTypes: localTypes)

        guard let (rule, matches) = candidatesByRule, !matches.isEmpty else {
            return Outcome(
                targetID: nil,
                rule: .unresolved,
                confidence: 0,
                ambiguity: 0,
                provenance: .syntactic
            )
        }

        if matches.count > config.maxFanout {
            return Outcome(
                targetID: nil,
                rule: .tooAmbiguous,
                confidence: Rule.tooAmbiguous.confidence.unique,
                ambiguity: matches.count,
                provenance: .syntactic
            )
        }

        let unique = matches.count == 1
        let confidence = unique ? rule.confidence.unique : rule.confidence.ambiguous / Double(matches.count)

        return Outcome(
            targetID: matches[0].id,
            rule: rule,
            confidence: confidence,
            ambiguity: matches.count,
            provenance: unique ? .syntactic : .heuristic
        )
    }

    /// Walks the scoping cascade and returns the first rule that matched.
    private func candidates(
        for edge: GraphEdge,
        source: SymbolNode?,
        localTypes: [String: String]
    ) -> (Rule, [SymbolNode])? {
        let name = edge.targetName
        let pool = byName[name] ?? []
        guard !pool.isEmpty else { return nil }

        let receiver = edge.receiver

        // 1. self / implicit member inside the enclosing type.
        if let container = source?.container, receiver == nil || receiver == "self" {
            let matches = pool.filter { $0.container == container }
            if !matches.isEmpty {
                return (.selfContainer, matches)
            }
        }

        // Receiver rules come before same-file. A receiver is direct evidence about
        // which type a call lands on, whereas being in the same file is only
        // proximity — ordering proximity first made `beta.handle()` resolve to a
        // same-file `Alpha.handle`.

        // 2. Receiver is a known type name, e.g. `Foo.bar()`.
        if let receiver, byContainer[receiver] != nil {
            let matches = pool.filter { $0.container == receiver }
            if !matches.isEmpty {
                return (.receiverType, matches)
            }
        }

        // 3. Receiver is a variable with a declared type. The highest-yield rule in
        //    Swift: dependencies are habitually stored as annotated properties, so the
        //    receiver's type is available from pure syntax.
        if let receiver, let type = localTypes[receiver] {
            let matches = pool.filter { $0.container == type }
            if !matches.isEmpty {
                return (.receiverVarType, matches)
            }
        }

        // 4. Same file. Only consulted when the receiver told us nothing, and skipped
        //    when there *is* a receiver we could not type — proximity would then be
        //    actively misleading.
        if let path = source?.path, receiver == nil || receiver == "self" {
            let matches = pool.filter { $0.path == path }
            if !matches.isEmpty {
                return (.sameFile, matches)
            }
        }

        // 5. Same module.
        if let module = source?.module {
            let matches = pool.filter { $0.module == module }
            if !matches.isEmpty, matches.count < pool.count {
                return (.moduleScope, matches)
            }
        }

        // 6/7. Global by name.
        if pool.count == 1 {
            return (.globalUnique, pool)
        }
        return (.globalFanout, pool)
    }

    /// Types visible to a symbol: its own locals plus its container's properties.
    ///
    /// A method's receiver is usually a stored property of the enclosing type
    /// (`private let store: any ChunkStore`), not a local. Consulting only the
    /// method's own bindings would miss the single most common — and most
    /// resolvable — shape of a cross-object call in Swift.
    private func visibleTypes(
        for symbolID: String,
        in localTypesBySymbol: [String: [String: String]]
    ) -> [String: String] {
        var types = localTypesBySymbol[symbolID] ?? [:]

        guard let symbol = byID[symbolID], let container = symbol.container else {
            return types
        }

        // The container's own symbol holds its stored-property types.
        let containerSymbols = (byName[container] ?? []).filter { $0.kind == .type }
        for containerSymbol in containerSymbols {
            for (name, type) in localTypesBySymbol[containerSymbol.id] ?? [:] where types[name] == nil {
                types[name] = type
            }
        }
        return types
    }

    // MARK: - Protocol witnesses

    /// Fans a call to a protocol requirement out to its conformers.
    ///
    /// This is the hop grep cannot follow, and the main reason the graph is worth
    /// building: a call to `ChunkStore.searchFTS` should surface the concrete
    /// implementations that will actually run.
    private func witnessFanout(for edge: GraphEdge, outcome: Outcome) -> [GraphEdge] {
        guard config.witnessFanoutEnabled,
              edge.kind == .calls || edge.kind == .initializes,
              let targetID = outcome.targetID,
              let target = byID[targetID],
              target.isRequirement,
              let protocolName = target.container,
              !Self.standardProtocols.contains(protocolName)
        else {
            return []
        }

        let conformers = conformersByProtocol[protocolName] ?? []
        guard !conformers.isEmpty, conformers.count <= config.maxWitnessFanout else {
            return []
        }

        return conformers.compactMap { conformer -> GraphEdge? in
            // Find the conformer's own implementation of the requirement.
            guard let implementation = (byContainer[conformer.name] ?? [])
                .first(where: { $0.name == target.name })
            else {
                return nil
            }

            return GraphEdge(
                sourceID: edge.sourceID,
                targetID: implementation.id,
                targetName: implementation.name,
                kind: edge.kind,
                provenance: .heuristic,
                confidence: 0.60,
                ambiguity: conformers.count,
                synthesizedBy: "protocol-witness",
                occurrences: edge.occurrences,
                firstLine: edge.firstLine,
                receiver: edge.receiver,
                sourcePath: edge.sourcePath
            )
        }
    }

    /// Protocols whose conformers are too numerous and too uninteresting to fan out to.
    ///
    /// A call to `==` must not produce an edge to every Equatable type in the project.
    static let standardProtocols: Set<String> = [
        "Equatable", "Hashable", "Comparable", "Codable", "Encodable", "Decodable",
        "CustomStringConvertible", "Sendable", "Identifiable", "Error", "Sequence",
        "Collection", "IteratorProtocol", "RawRepresentable", "CaseIterable",
        "ExpressibleByStringLiteral", "ExpressibleByIntegerLiteral",
    ]

    // MARK: - Tables

    private func buildTables(from symbols: [SymbolNode]) {
        byName = Dictionary(grouping: symbols, by: \.name)
        byID = Dictionary(symbols.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        byContainer = Dictionary(
            grouping: symbols.compactMap { symbol in symbol.container.map { ($0, symbol) } },
            by: \.0
        ).mapValues { $0.map(\.1) }

        // Types are their own container entry, so `byContainer[TypeName]` yields members.
        conformersByProtocol = [:]
    }

    /// Records which types conform to which protocols, for witness fanout.
    func loadConformances(_ pairs: [(type: String, protocolName: String)], symbols: [SymbolNode]) {
        let typesByName = Dictionary(
            grouping: symbols.filter { $0.kind == .type },
            by: \.name
        )
        for pair in pairs {
            guard let type = typesByName[pair.type]?.first else { continue }
            conformersByProtocol[pair.protocolName, default: []].append(type)
        }
    }
}

// MARK: - GraphConfig

/// Tunables for graph construction.
public struct GraphConfig: Sendable, Equatable, Codable {
    /// Whether the graph is built at all.
    public var enabled: Bool

    /// Maximum same-name candidates before an edge is left unresolved.
    ///
    /// Without a cap, common names produce a combinatorial mess that buries the real
    /// structure.
    public var maxFanout: Int

    /// Maximum conformers a protocol requirement fans out to.
    public var maxWitnessFanout: Int

    /// Whether protocol-witness edges are synthesized.
    public var witnessFanoutEnabled: Bool

    /// Default minimum confidence for queries.
    public var minConfidence: Double

    public init(
        enabled: Bool = true,
        maxFanout: Int = 4,
        maxWitnessFanout: Int = 8,
        witnessFanoutEnabled: Bool = true,
        minConfidence: Double = 0.3
    ) {
        self.enabled = enabled
        self.maxFanout = maxFanout
        self.maxWitnessFanout = maxWitnessFanout
        self.witnessFanoutEnabled = witnessFanoutEnabled
        self.minConfidence = minConfidence
    }
}
