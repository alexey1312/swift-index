// MARK: - CodeChunk Model

import Foundation

/// A chunk of code extracted from a source file.
///
/// CodeChunks are the fundamental units of indexing and search.
/// Each chunk represents a logical unit of code (function, class, etc.)
/// with its metadata and content.
public struct CodeChunk: Sendable, Equatable, Identifiable, Codable {
    /// Unique identifier for this chunk.
    public let id: String

    /// Path to the source file.
    public let path: String

    /// The actual code content.
    public let content: String

    /// Starting line number (1-indexed).
    public let startLine: Int

    /// Ending line number (1-indexed).
    public let endLine: Int

    /// The type of code construct this chunk represents.
    public let kind: ChunkKind

    /// Symbols defined in this chunk (function names, type names, etc.).
    public let symbols: [String]

    /// Symbols referenced by this chunk.
    public let references: [String]

    /// Hash of the source file content (for incremental indexing).
    public let fileHash: String

    /// Timestamp when this chunk was created.
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        path: String,
        content: String,
        startLine: Int,
        endLine: Int,
        kind: ChunkKind,
        symbols: [String] = [],
        references: [String] = [],
        fileHash: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.content = content
        self.startLine = startLine
        self.endLine = endLine
        self.kind = kind
        self.symbols = symbols
        self.references = references
        self.fileHash = fileHash
        self.createdAt = createdAt
    }
}

// MARK: - Hashable

extension CodeChunk: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - CustomStringConvertible

extension CodeChunk: CustomStringConvertible {
    public var description: String {
        let symbolList = symbols.isEmpty ? "none" : symbols.joined(separator: ", ")
        return "CodeChunk(\(kind.rawValue): \(path):\(startLine)-\(endLine), symbols: [\(symbolList)])"
    }
}
