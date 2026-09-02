// MARK: - Graph Models

import Crypto
import Foundation

/// What kind of declaration a symbol is.
public enum SymbolKind: String, Sendable, Codable, CaseIterable {
    case function
    case method
    case initializer
    case property
    case type
    case protocolDecl = "protocol"
    case enumCase
    case subscriptDecl = "subscript"
    case operatorDecl = "operator"
    case typealiasDecl = "typealias"
}

/// The relationship an edge represents.
public enum EdgeKind: String, Sendable, Codable, CaseIterable {
    case calls
    case references
    case inherits
    case conforms
    case overrides
    case imports
    case initializes
}

/// How much to trust an edge.
///
/// Recorded explicitly rather than hidden, following codegraph's practice of tagging
/// synthesized relationships. An agent reasons far better about "this hop is a guess
/// covering three conformers" than about a confident-looking wrong answer.
public enum EdgeProvenance: String, Sendable, Codable {
    /// Resolved directly from syntax.
    case syntactic
    /// Inferred by a rule such as protocol-witness fanout.
    case heuristic
    /// Reserved: exact, from a compiler index store.
    case indexstore
}

/// A declaration site, identified by name rather than position.
///
/// Deliberately *not* the same thing as a `CodeChunk`. Chunk ids hash `startLine`, so
/// inserting a line at the top of a file changes every id in it — edges pointing at
/// chunks would be invalidated by pure formatting. One logical symbol also spans
/// several chunks (a type declaration, the whole type, each method, extensions in
/// other files), and an edge's target may have no chunk at all (a stdlib call, a
/// protocol requirement, an unresolved name).
public struct SymbolNode: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let qualifiedName: String
    public let container: String?
    public let module: String?
    public let kind: SymbolKind
    /// Argument labels joined by ":", used to discriminate overloads.
    public let argumentLabels: String?
    public let arity: Int
    public let isStatic: Bool
    /// Declared inside a protocol body, so calls to it fan out to conformers.
    public let isRequirement: Bool
    public let isOverride: Bool
    public let access: String?
    public let path: String
    public let startLine: Int
    public let endLine: Int
    public let chunkID: String?
    /// Confidence-weighted incoming call count, filled in by the resolver.
    public var inDegree: Int
    public let fileHash: String

    public init(
        id: String,
        name: String,
        qualifiedName: String,
        container: String?,
        module: String?,
        kind: SymbolKind,
        argumentLabels: String?,
        arity: Int,
        isStatic: Bool,
        isRequirement: Bool,
        isOverride: Bool,
        access: String?,
        path: String,
        startLine: Int,
        endLine: Int,
        chunkID: String?,
        inDegree: Int = 0,
        fileHash: String
    ) {
        self.id = id
        self.name = name
        self.qualifiedName = qualifiedName
        self.container = container
        self.module = module
        self.kind = kind
        self.argumentLabels = argumentLabels
        self.arity = arity
        self.isStatic = isStatic
        self.isRequirement = isRequirement
        self.isOverride = isOverride
        self.access = access
        self.path = path
        self.startLine = startLine
        self.endLine = endLine
        self.chunkID = chunkID
        self.inDegree = inDegree
        self.fileHash = fileHash
    }

    /// Builds a position-independent identity.
    ///
    /// Line numbers are excluded on purpose: a symbol must keep the same id across
    /// reformatting, or every edge into a file would break on a whitespace change.
    public struct Identity: Sendable {
        public let path: String
        public let container: String?
        public let name: String
        public let kind: SymbolKind
        public let argumentLabels: String?
        public let isStatic: Bool

        public init(
            path: String,
            container: String?,
            name: String,
            kind: SymbolKind,
            argumentLabels: String?,
            isStatic: Bool
        ) {
            self.path = path
            self.container = container
            self.name = name
            self.kind = kind
            self.argumentLabels = argumentLabels
            self.isStatic = isStatic
        }
    }

    public static func makeID(_ identity: Identity) -> String {
        let material = [
            identity.path,
            identity.container ?? "",
            identity.name,
            identity.kind.rawValue,
            identity.argumentLabels ?? "",
            identity.isStatic ? "static" : "instance",
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}

/// A relationship between two symbols.
public struct GraphEdge: Sendable, Equatable, Codable {
    public let sourceID: String
    /// Resolved target, or nil when the name could not be pinned down.
    public var targetID: String?
    /// Always populated, even when resolved.
    ///
    /// Keeps the graph queryable by name before resolution runs, makes re-resolution a
    /// pure UPDATE rather than a re-parse, and keeps unresolved third-party calls
    /// visible as named leaves instead of vanishing.
    public let targetName: String
    public let kind: EdgeKind
    public var provenance: EdgeProvenance
    public var confidence: Double
    /// Number of candidates considered when resolving.
    public var ambiguity: Int
    /// Name of the rule that produced this edge.
    public var synthesizedBy: String?
    /// Collapsed call sites, so repeated calls cost one row.
    public var occurrences: Int
    public let firstLine: Int?
    /// Receiver expression text, truncated.
    public let receiver: String?
    /// Denormalized for O(1) invalidation when a file changes.
    public let sourcePath: String

    public init(
        sourceID: String,
        targetID: String? = nil,
        targetName: String,
        kind: EdgeKind,
        provenance: EdgeProvenance = .syntactic,
        confidence: Double = 0,
        ambiguity: Int = 1,
        synthesizedBy: String? = nil,
        occurrences: Int = 1,
        firstLine: Int? = nil,
        receiver: String? = nil,
        sourcePath: String
    ) {
        self.sourceID = sourceID
        self.targetID = targetID
        self.targetName = targetName
        self.kind = kind
        self.provenance = provenance
        self.confidence = confidence
        self.ambiguity = ambiguity
        self.synthesizedBy = synthesizedBy
        self.occurrences = occurrences
        self.firstLine = firstLine
        self.receiver = receiver
        self.sourcePath = sourcePath
    }
}

/// A resolved target to write back onto an edge.
public struct EdgeResolution: Sendable {
    public let sourceID: String
    public let targetName: String
    public let kind: EdgeKind
    public let targetID: String?
    public let provenance: EdgeProvenance
    public let confidence: Double
    public let ambiguity: Int
    public let synthesizedBy: String?

    public init(
        sourceID: String,
        targetName: String,
        kind: EdgeKind,
        targetID: String?,
        provenance: EdgeProvenance,
        confidence: Double,
        ambiguity: Int,
        synthesizedBy: String?
    ) {
        self.sourceID = sourceID
        self.targetName = targetName
        self.kind = kind
        self.targetID = targetID
        self.provenance = provenance
        self.confidence = confidence
        self.ambiguity = ambiguity
        self.synthesizedBy = synthesizedBy
    }
}

/// A reference captured from syntax, before any name resolution.
public struct RawReference: Sendable, Equatable {
    public let name: String
    public let kind: EdgeKind
    /// Text of the receiver expression, e.g. "self" or "chunkStore".
    public let receiver: String?
    public let argumentLabels: String?
    public let arity: Int
    public let line: Int
    /// Symbol the reference appears inside.
    public let enclosingSymbolID: String

    public init(
        name: String,
        kind: EdgeKind,
        receiver: String?,
        argumentLabels: String?,
        arity: Int,
        line: Int,
        enclosingSymbolID: String
    ) {
        self.name = name
        self.kind = kind
        self.receiver = receiver
        self.argumentLabels = argumentLabels
        self.arity = arity
        self.line = line
        self.enclosingSymbolID = enclosingSymbolID
    }
}

/// Everything one file contributes to the graph.
public struct FileGraphFacts: Sendable, Equatable {
    public let path: String
    public let fileHash: String
    public let symbols: [SymbolNode]
    public let references: [RawReference]
    public let imports: [String]
    /// Declared types of local bindings and properties, keyed by enclosing symbol id
    /// then variable name. Powers receiver typing during resolution.
    public let localTypes: [String: [String: String]]

    public init(
        path: String,
        fileHash: String,
        symbols: [SymbolNode],
        references: [RawReference],
        imports: [String],
        localTypes: [String: [String: String]] = [:]
    ) {
        self.path = path
        self.fileHash = fileHash
        self.symbols = symbols
        self.references = references
        self.imports = imports
        self.localTypes = localTypes
    }
}
