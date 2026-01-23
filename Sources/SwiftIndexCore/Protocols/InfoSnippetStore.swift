// MARK: - InfoSnippetStore Protocol

import Foundation

/// A store for persisting and retrieving info snippets (documentation).
///
/// InfoSnippetStore handles standalone documentation content that can be
/// searched independently from code chunks. It provides FTS5 full-text
/// search capabilities for documentation discovery.
///
/// Note: Method names use "snippet" prefix/suffix to distinguish from
/// ChunkStore methods when both protocols are implemented by the same type.
public protocol InfoSnippetStore: Sendable {
    /// Insert a new snippet into the store.
    ///
    /// - Parameter snippet: The snippet to insert.
    /// - Throws: If the insertion fails.
    func insertSnippet(_ snippet: InfoSnippet) async throws

    /// Insert multiple snippets in a batch operation.
    ///
    /// - Parameter snippets: The snippets to insert.
    /// - Throws: If the insertion fails.
    func insertSnippetBatch(_ snippets: [InfoSnippet]) async throws

    /// Get a snippet by its ID.
    ///
    /// - Parameter id: The snippet ID.
    /// - Returns: The snippet if found, nil otherwise.
    func getSnippet(id: String) async throws -> InfoSnippet?

    /// Get all snippets for a file path.
    ///
    /// - Parameter path: The file path.
    /// - Returns: All snippets from the file.
    func getSnippetsByPath(_ path: String) async throws -> [InfoSnippet]

    /// Get all snippets associated with a code chunk.
    ///
    /// - Parameter chunkId: The parent chunk ID.
    /// - Returns: All snippets linked to the chunk.
    func getSnippetsByChunkId(_ chunkId: String) async throws -> [InfoSnippet]

    /// Delete a snippet by its ID.
    ///
    /// - Parameter id: The snippet ID to delete.
    /// - Throws: If the deletion fails.
    func deleteSnippet(id: String) async throws

    /// Delete all snippets for a file path.
    ///
    /// - Parameter path: The file path.
    /// - Throws: If the deletion fails.
    func deleteSnippetsByPath(_ path: String) async throws

    /// Delete all snippets associated with a code chunk.
    ///
    /// - Parameter chunkId: The parent chunk ID.
    /// - Throws: If the deletion fails.
    func deleteSnippetsByChunkId(_ chunkId: String) async throws

    /// Perform BM25 full-text search on documentation.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - limit: Maximum results to return.
    /// - Returns: Snippets matching the query with BM25 scores.
    func searchSnippetsFTS(query: String, limit: Int) async throws -> [(snippet: InfoSnippet, score: Double)]

    /// Get the total count of snippets.
    ///
    /// - Returns: Number of snippets in the store.
    func snippetCount() async throws -> Int

    /// Clear all snippet data from the store.
    func clearSnippets() async throws
}
