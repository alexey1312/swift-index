// MARK: - InfoSnippet Model

import Foundation

/// A snippet of documentation extracted from a source file.
///
/// InfoSnippets store standalone documentation content that can be searched
/// independently from code. This includes:
/// - File-level documentation comments
/// - Standalone Markdown sections
/// - Header documentation blocks
///
/// Unlike `CodeChunk`, which represents code constructs, `InfoSnippet` represents
/// pure documentation content that provides context and explanation.
public struct InfoSnippet: Sendable, Equatable, Identifiable, Codable {
    /// Unique identifier for this snippet.
    public let id: String

    /// Path to the source file.
    public let path: String

    /// The documentation content.
    public let content: String

    /// Starting line number (1-indexed).
    public let startLine: Int

    /// Ending line number (1-indexed).
    public let endLine: Int

    /// Hierarchy path showing context (e.g., "README > Installation > macOS").
    public let breadcrumb: String?

    /// Approximate token count for context window estimation (content.count / 4).
    public let tokenCount: Int

    /// Programming language or document type.
    public let language: String

    /// Optional reference to the parent CodeChunk this snippet documents.
    /// Nil for file-level or standalone documentation.
    public let chunkId: String?

    /// The type of documentation snippet.
    public let kind: InfoSnippetKind

    /// Hash of the source file content (for incremental indexing).
    public let fileHash: String

    /// Timestamp when this snippet was created.
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        path: String,
        content: String,
        startLine: Int,
        endLine: Int,
        breadcrumb: String? = nil,
        tokenCount: Int? = nil,
        language: String? = nil,
        chunkId: String? = nil,
        kind: InfoSnippetKind = .documentation,
        fileHash: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.content = content
        self.startLine = startLine
        self.endLine = endLine
        self.breadcrumb = breadcrumb
        self.tokenCount = tokenCount ?? (content.count / 4)
        self.language = language ?? InfoSnippet.detectLanguage(from: path)
        self.chunkId = chunkId
        self.kind = kind
        self.fileHash = fileHash
        self.createdAt = createdAt
    }

    /// Detect document language from file extension.
    private static func detectLanguage(from path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "markdown": return "markdown"
        case "rst": return "restructuredtext"
        case "txt": return "text"
        case "swift": return "swift"
        case "m", "mm": return "objective-c"
        case "h": return "c-header"
        default: return "unknown"
        }
    }
}

// MARK: - Hashable

extension InfoSnippet: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - CustomStringConvertible

extension InfoSnippet: CustomStringConvertible {
    public var description: String {
        let context = breadcrumb ?? "root"
        return "InfoSnippet(\(kind.rawValue): \(path):\(startLine)-\(endLine), context: \(context))"
    }
}

// MARK: - InfoSnippetKind

/// The type of documentation snippet.
public enum InfoSnippetKind: String, Sendable, Codable, CaseIterable {
    /// General documentation (file-level comments, standalone docs)
    case documentation

    /// Markdown section (header-delimited content)
    case markdownSection

    /// API documentation (extracted from code comments)
    case apiDocumentation

    /// Example or code sample with explanation
    case example

    /// TODO, FIXME, or other annotation
    case annotation
}
