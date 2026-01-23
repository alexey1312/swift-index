// MARK: - CodeChunk Model

import Crypto
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

    // MARK: - Rich Metadata Fields

    /// Documentation comment extracted from the source (/// or /** */).
    public let docComment: String?

    /// Full declaration signature (e.g., "func authenticate(user: String) -> Bool").
    public let signature: String?

    /// Hierarchy path showing nesting context (e.g., "AuthManager > authenticate").
    public let breadcrumb: String?

    /// Approximate token count for context window estimation (content.count / 4).
    public let tokenCount: Int

    /// Programming language based on file extension.
    public let language: String

    /// SHA-256 hash of chunk content for change detection.
    /// Used to skip re-embedding unchanged chunks during re-indexing.
    public let contentHash: String

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
        createdAt: Date = Date(),
        docComment: String? = nil,
        signature: String? = nil,
        breadcrumb: String? = nil,
        tokenCount: Int? = nil,
        language: String? = nil,
        contentHash: String? = nil
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
        self.docComment = docComment
        self.signature = signature
        self.breadcrumb = breadcrumb
        self.tokenCount = tokenCount ?? (content.count / 4)
        self.language = language ?? CodeChunk.detectLanguage(from: path)
        self.contentHash = contentHash ?? CodeChunk.computeContentHash(content)
    }

    /// Compute SHA-256 hash of content for change detection.
    public static func computeContentHash(_ content: String) -> String {
        let data = Data(content.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Detect programming language from file extension.
    private static func detectLanguage(from path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "m", "mm": return "objective-c"
        case "h": return "c-header"
        case "c": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "json": return "json"
        case "yaml", "yml": return "yaml"
        case "md", "markdown": return "markdown"
        default: return "unknown"
        }
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
