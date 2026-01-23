// MARK: - USearchVectorStore

import Foundation
import USearch

/// HNSW-based vector storage using USearch for approximate nearest neighbor search.
///
/// USearchVectorStore provides efficient similarity search with:
/// - HNSW (Hierarchical Navigable Small World) index
/// - Configurable distance metrics (cosine, L2, inner product)
/// - Disk persistence for index state
/// - Thread-safe operations via actor isolation
public actor USearchVectorStore: VectorStore {
    // MARK: - Properties

    /// The HNSW index.
    private var index: USearchIndex

    /// Mapping from chunk ID to internal index key.
    private var idToKey: [String: USearchKey]

    /// Mapping from internal index key to chunk ID.
    private var keyToId: [USearchKey: String]

    /// Counter for generating unique internal keys.
    private var nextKey: USearchKey

    /// The vector dimension.
    public let dimension: Int

    /// Path for persisting the index.
    private let indexPath: String?

    /// Path for persisting the ID mappings.
    private let mappingPath: String?

    // MARK: - Initialization

    /// Create a new vector store with the specified dimension.
    ///
    /// - Parameters:
    ///   - dimension: The dimension of embedding vectors.
    ///   - path: Optional path for persisting the index. If nil, index is in-memory only.
    ///   - metric: Distance metric to use (default: cosine similarity).
    /// - Throws: If index creation fails.
    public init(
        dimension: Int,
        path: String? = nil,
        metric: USearchMetric = .cos
    ) throws {
        self.dimension = dimension
        idToKey = [:]
        keyToId = [:]
        nextKey = 0

        if let path {
            indexPath = path
            mappingPath = path + ".mapping"

            // Ensure directory exists
            let directory = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
        } else {
            indexPath = nil
            mappingPath = nil
        }

        // Create HNSW index with optimized parameters
        index = try USearchIndex.make(
            metric: metric,
            dimensions: UInt32(dimension),
            connectivity: 16, // M parameter - edges per node
            quantization: .f32 // Full precision
        )

        // Reserve initial capacity
        try index.reserve(10000)
    }

    // MARK: - VectorStore Protocol

    public func add(id: String, vector: [Float]) async throws {
        guard vector.count == dimension else {
            throw VectorStoreError.dimensionMismatch(
                expected: dimension,
                actual: vector.count
            )
        }

        // Remove existing vector if present
        if let existingKey = idToKey[id] {
            _ = try index.remove(key: existingKey)
            keyToId.removeValue(forKey: existingKey)
        }

        let key = nextKey
        nextKey += 1

        do {
            try index.add(key: key, vector: vector)
        } catch {
            // USearch error 15 typically indicates dimension mismatch with existing index
            let errorString = String(describing: error)
            if errorString.contains("error 15") {
                throw VectorStoreError.indexDimensionMismatch(
                    indexDimension: dimension,
                    message: """
                    The existing index was created with a different vector dimension.
                    This usually happens when you change the embedding provider or model.

                    To fix this, delete the index and reindex:
                      rm -rf .swiftindex
                      swiftindex index .
                    """
                )
            }
            throw error
        }
        idToKey[id] = key
        keyToId[key] = id
    }

    public func addBatch(_ items: [(id: String, vector: [Float])]) async throws {
        for (id, vector) in items {
            try await add(id: id, vector: vector)
        }
    }

    public func search(
        vector: [Float],
        limit: Int
    ) async throws -> [(id: String, similarity: Float)] {
        guard vector.count == dimension else {
            throw VectorStoreError.dimensionMismatch(
                expected: dimension,
                actual: vector.count
            )
        }

        guard !idToKey.isEmpty else {
            return []
        }

        let (keys, distances) = try index.search(vector: vector, count: limit)

        var results: [(id: String, similarity: Float)] = []
        for (idx, key) in keys.enumerated() {
            guard let id = keyToId[key] else { continue }
            // Convert distance to similarity (for cosine: similarity = 1 - distance)
            let similarity = 1.0 - distances[idx]
            results.append((id: id, similarity: similarity))
        }
        return results
    }

    public func delete(id: String) async throws {
        guard let key = idToKey[id] else { return }

        _ = try index.remove(key: key)
        idToKey.removeValue(forKey: id)
        keyToId.removeValue(forKey: key)
    }

    public func contains(id: String) async throws -> Bool {
        idToKey[id] != nil
    }

    public func get(id: String) async throws -> [Float]? {
        try await getVector(id: id)
    }

    public func count() async throws -> Int {
        idToKey.count
    }

    public func save() async throws {
        guard let indexPath, let mappingPath else {
            throw VectorStoreError.noPersistencePath
        }

        // Save the HNSW index
        try index.save(path: indexPath)

        // Save ID mappings
        let mapping = VectorStoreMapping(
            idToKey: idToKey,
            keyToId: keyToId.reduce(into: [:]) { $0[String($1.key)] = $1.value },
            nextKey: nextKey
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(mapping)
        try data.write(to: URL(fileURLWithPath: mappingPath))
    }

    public func load() async throws {
        guard let indexPath, let mappingPath else {
            throw VectorStoreError.noPersistencePath
        }

        // Check if files exist
        guard FileManager.default.fileExists(atPath: indexPath),
              FileManager.default.fileExists(atPath: mappingPath)
        else {
            throw VectorStoreError.indexNotFound(indexPath)
        }

        // Load the HNSW index
        try index.load(path: indexPath)

        // Load ID mappings
        let data = try Data(contentsOf: URL(fileURLWithPath: mappingPath))
        let mapping = try JSONDecoder().decode(VectorStoreMapping.self, from: data)

        idToKey = mapping.idToKey
        keyToId = mapping.keyToId.reduce(into: [:]) {
            if let key = USearchKey($1.key) {
                $0[key] = $1.value
            }
        }
        nextKey = mapping.nextKey
    }

    public func clear() async throws {
        try index.clear()
        idToKey.removeAll()
        keyToId.removeAll()
        nextKey = 0
    }

    // MARK: - Additional Methods

    /// Get the vector for a chunk ID.
    ///
    /// - Parameter id: The chunk ID.
    /// - Returns: The vector if found.
    public func getVector(id: String) async throws -> [Float]? {
        guard let key = idToKey[id] else { return nil }

        let vectors: [[Float]]? = try index.get(key: key, count: 1)
        return vectors?.first
    }

    /// Check if an index file exists at the configured path.
    ///
    /// - Returns: True if the index file exists.
    public nonisolated func indexFileExists() -> Bool {
        guard let indexPath else { return false }
        return FileManager.default.fileExists(atPath: indexPath)
    }

    /// Get all chunk IDs in the store.
    ///
    /// - Returns: Array of chunk IDs.
    public func allIDs() async throws -> [String] {
        Array(idToKey.keys)
    }

    /// Search for similar vectors with a minimum similarity threshold.
    ///
    /// - Parameters:
    ///   - vector: The query vector.
    ///   - limit: Maximum results to return.
    ///   - minSimilarity: Minimum similarity threshold (0-1).
    /// - Returns: Filtered results above the threshold.
    public func search(
        vector: [Float],
        limit: Int,
        minSimilarity: Float
    ) async throws -> [(id: String, similarity: Float)] {
        let results = try await search(vector: vector, limit: limit)
        return results.filter { $0.similarity >= minSimilarity }
    }
}

// MARK: - VectorStoreMapping

/// Serializable mapping for index persistence.
private struct VectorStoreMapping: Codable {
    let idToKey: [String: USearchKey]
    let keyToId: [String: String] // String key for JSON compatibility
    let nextKey: USearchKey
}

// MARK: - VectorStoreError

/// Errors specific to vector store operations.
public enum VectorStoreError: Error, Sendable {
    case dimensionMismatch(expected: Int, actual: Int)
    case indexDimensionMismatch(indexDimension: Int, message: String)
    case indexNotFound(String)
    case noPersistencePath
    case saveFailed(String)
    case loadFailed(String)
}

extension VectorStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .dimensionMismatch(expected, actual):
            "Vector dimension mismatch: expected \(expected), got \(actual)"
        case let .indexDimensionMismatch(_, message):
            message
        case let .indexNotFound(path):
            "Vector index not found at: \(path)"
        case .noPersistencePath:
            "No persistence path configured for vector store"
        case let .saveFailed(message):
            "Failed to save vector index: \(message)"
        case let .loadFailed(message):
            "Failed to load vector index: \(message)"
        }
    }
}
