// MARK: - AST Node Model

import Foundation

/// AST node for visualization. Sendable for cross-actor use.
///
/// Represents a single node in the abstract syntax tree with metadata
/// for displaying code structure in tree format.
public struct ASTNode: Sendable, Codable, Equatable, Hashable {
    /// The kind of syntax node (e.g., "class", "function", "struct").
    public let kind: String

    /// The identifier name (if applicable).
    public let name: String?

    /// Starting line number (1-indexed).
    public let startLine: Int

    /// Ending line number (1-indexed).
    public let endLine: Int

    /// Full declaration signature (e.g., "public func authenticate(user: String) -> Bool").
    public let signature: String?

    /// Child nodes in the AST hierarchy.
    public let children: [ASTNode]

    /// Depth level in the tree (0 for root nodes).
    public let depth: Int

    public init(
        kind: String,
        name: String?,
        startLine: Int,
        endLine: Int,
        signature: String? = nil,
        children: [ASTNode] = [],
        depth: Int = 0
    ) {
        self.kind = kind
        self.name = name
        self.startLine = startLine
        self.endLine = endLine
        self.signature = signature
        self.children = children
        self.depth = depth
    }
}

// MARK: - ParseTreeResult

/// Result of parsing a single file's AST.
public struct ParseTreeResult: Sendable, Codable, Equatable {
    /// Root-level AST nodes.
    public let nodes: [ASTNode]

    /// Total number of nodes in the tree.
    public let totalNodes: Int

    /// Maximum depth of the tree.
    public let maxDepth: Int

    /// Path to the source file.
    public let path: String

    /// Programming language (detected from file extension).
    public let language: String

    public init(
        nodes: [ASTNode],
        totalNodes: Int,
        maxDepth: Int,
        path: String,
        language: String
    ) {
        self.nodes = nodes
        self.totalNodes = totalNodes
        self.maxDepth = maxDepth
        self.path = path
        self.language = language
    }
}

// MARK: - ParseTreeBatchResult

/// Result of parsing multiple files (directory mode).
public struct ParseTreeBatchResult: Sendable, Codable, Equatable {
    /// Results for each parsed file.
    public let files: [ParseTreeResult]

    /// Total number of files processed.
    public let totalFiles: Int

    /// Total number of nodes across all files.
    public let totalNodes: Int

    /// Maximum depth across all files.
    public let maxDepth: Int

    /// Root path that was scanned.
    public let rootPath: String

    public init(
        files: [ParseTreeResult],
        totalFiles: Int,
        totalNodes: Int,
        maxDepth: Int,
        rootPath: String
    ) {
        self.files = files
        self.totalFiles = totalFiles
        self.totalNodes = totalNodes
        self.maxDepth = maxDepth
        self.rootPath = rootPath
    }
}

// MARK: - CustomStringConvertible

extension ASTNode: CustomStringConvertible {
    public var description: String {
        let nameStr = name.map { " '\($0)'" } ?? ""
        let lineRange = startLine == endLine ? "[\(startLine)]" : "[\(startLine)-\(endLine)]"
        return "\(kind)\(nameStr) \(lineRange)"
    }
}

extension ParseTreeResult: CustomStringConvertible {
    public var description: String {
        "ParseTreeResult(\(path): \(totalNodes) nodes, depth \(maxDepth))"
    }
}

extension ParseTreeBatchResult: CustomStringConvertible {
    public var description: String {
        "ParseTreeBatchResult(\(rootPath): \(totalFiles) files, \(totalNodes) nodes)"
    }
}
