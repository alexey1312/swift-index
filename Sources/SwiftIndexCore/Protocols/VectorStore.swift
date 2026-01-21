// MARK: - VectorStore Protocol

import Foundation

/// A store for persisting and searching vector embeddings.
///
/// VectorStore handles the HNSW index for semantic similarity search.
/// It maps chunk IDs to their embedding vectors and supports efficient
/// approximate nearest neighbor search.
public protocol VectorStore: Sendable {
    /// The dimension of vectors in this store.
    var dimension: Int { get }

    /// Add a vector with its associated chunk ID.
    ///
    /// - Parameters:
    ///   - id: The chunk ID.
    ///   - vector: The embedding vector.
    /// - Throws: If the insertion fails or dimension mismatches.
    func add(id: String, vector: [Float]) async throws

    /// Add multiple vectors in a batch operation.
    ///
    /// - Parameter items: Array of (id, vector) pairs.
    /// - Throws: If the insertion fails.
    func addBatch(_ items: [(id: String, vector: [Float])]) async throws

    /// Search for similar vectors.
    ///
    /// - Parameters:
    ///   - vector: The query vector.
    ///   - limit: Maximum results to return.
    /// - Returns: Array of (chunkID, similarity) pairs, sorted by similarity.
    func search(vector: [Float], limit: Int) async throws -> [(id: String, similarity: Float)]

    /// Delete a vector by its chunk ID.
    ///
    /// - Parameter id: The chunk ID.
    /// - Throws: If the deletion fails.
    func delete(id: String) async throws

    /// Check if a vector exists for the given ID.
    ///
    /// - Parameter id: The chunk ID.
    /// - Returns: True if the vector exists.
    func contains(id: String) async throws -> Bool

    /// Get the total count of vectors.
    ///
    /// - Returns: Number of vectors in the store.
    func count() async throws -> Int

    /// Persist the index to disk.
    ///
    /// - Throws: If saving fails.
    func save() async throws

    /// Load the index from disk.
    ///
    /// - Throws: If loading fails.
    func load() async throws

    /// Clear all vectors from the store.
    func clear() async throws
}
