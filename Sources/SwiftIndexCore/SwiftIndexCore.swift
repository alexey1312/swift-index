// MARK: - SwiftIndexCore

/// SwiftIndex Core Library
///
/// Provides semantic code search for Swift codebases with:
/// - Hybrid parsing (SwiftSyntax + tree-sitter)
/// - Local-first embedding providers
/// - Hybrid search (BM25 + semantic + RRF fusion)
///
/// ## Usage
///
/// ```swift
/// import SwiftIndexCore
///
/// // Create indexer with default config
/// let indexer = Indexer(config: .default)
///
/// // Index a directory
/// try await indexer.index(path: "/path/to/project")
///
/// // Search
/// let results = try await indexer.search("authentication flow")
/// ```

// Re-export all public types

// MARK: - Models
@_exported import struct Foundation.Date
@_exported import struct Foundation.URL
