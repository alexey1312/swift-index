// MARK: - ChunkStore Protocol

import Foundation

/// A store for persisting and retrieving code chunks.
///
/// ChunkStore handles the structured metadata for code chunks,
/// including content, symbols, and file information. It also
/// provides FTS5 full-text search capabilities.
public protocol ChunkStore: Sendable {
    /// Insert a new chunk into the store.
    ///
    /// - Parameter chunk: The chunk to insert.
    /// - Throws: If the insertion fails.
    func insert(_ chunk: CodeChunk) async throws

    /// Insert multiple chunks in a batch operation.
    ///
    /// - Parameter chunks: The chunks to insert.
    /// - Throws: If the insertion fails.
    func insertBatch(_ chunks: [CodeChunk]) async throws

    /// Get a chunk by its ID.
    ///
    /// - Parameter id: The chunk ID.
    /// - Returns: The chunk if found, nil otherwise.
    func get(id: String) async throws -> CodeChunk?

    /// Get chunks by their IDs.
    ///
    /// - Parameter ids: The chunk IDs to fetch.
    /// - Returns: Array of chunks (may be fewer than requested if some IDs not found).
    func getByIDs(_ ids: [String]) async throws -> [CodeChunk]

    /// Get all chunks for a file path.
    ///
    /// - Parameter path: The file path.
    /// - Returns: All chunks from the file.
    func getByPath(_ path: String) async throws -> [CodeChunk]

    /// Update an existing chunk.
    ///
    /// - Parameter chunk: The chunk with updated values.
    /// - Throws: If the update fails.
    func update(_ chunk: CodeChunk) async throws

    /// Delete a chunk by its ID.
    ///
    /// - Parameter id: The chunk ID to delete.
    /// - Throws: If the deletion fails.
    func delete(id: String) async throws

    /// Delete all chunks for a file path.
    ///
    /// - Parameter path: The file path.
    /// - Throws: If the deletion fails.
    func deleteByPath(_ path: String) async throws

    /// Perform BM25 full-text search.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - limit: Maximum results to return.
    /// - Returns: Chunks matching the query with BM25 scores.
    func searchFTS(query: String, limit: Int) async throws -> [(chunk: CodeChunk, score: Double)]

    /// Get all chunk IDs in the store.
    ///
    /// - Returns: Array of chunk IDs.
    func allIDs() async throws -> [String]

    /// Get the total count of chunks.
    ///
    /// - Returns: Number of chunks in the store.
    func count() async throws -> Int

    /// Get the stored file hash for a path.
    ///
    /// - Parameter path: The file path.
    /// - Returns: The stored hash if the file has been indexed, nil otherwise.
    func getFileHash(forPath path: String) async throws -> String?

    /// Set the file hash for a path after indexing.
    ///
    /// - Parameters:
    ///   - hash: The file content hash.
    ///   - path: The file path.
    func setFileHash(_ hash: String, forPath path: String) async throws

    /// Get chunks with the specified content hashes.
    ///
    /// Used for content-based change detection to find unchanged chunks.
    ///
    /// - Parameter hashes: Set of content hashes to look up.
    /// - Returns: Dictionary mapping content hash to existing chunk.
    func getByContentHashes(_ hashes: Set<String>) async throws -> [String: CodeChunk]

    /// Get term frequency for a term (count of chunks containing this term).
    ///
    /// Used for exact symbol boost threshold checking. Terms appearing fewer
    /// than the rare term threshold receive higher boost in search ranking.
    ///
    /// - Parameter term: The term to count occurrences of.
    /// - Returns: Number of chunks containing this term.
    func getTermFrequency(term: String) async throws -> Int

    /// Clear all data from the store.
    func clear() async throws
}

extension ChunkStore {
    /// Default implementation of getByIDs that iteratively calls get(id:).
    /// Conforming types should override this with a more efficient implementation if possible.
    public func getByIDs(_ ids: [String]) async throws -> [CodeChunk] {
        var results: [CodeChunk] = []
        for id in ids {
            if let chunk = try await get(id: id) {
                results.append(chunk)
            }
        }
        return results
    }
}
