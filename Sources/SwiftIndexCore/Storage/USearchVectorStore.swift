// MARK: - USearchVectorStore

import Foundation
import Logging
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

    /// Logger for diagnostics.
    private let logger = Logger(label: "USearchVectorStore")

    /// Growth factor for capacity expansion.
    private static let capacityGrowthFactor: UInt32 = 2

    /// Initial capacity for new indexes.
    private static let initialCapacity: UInt32 = 10000

    /// The HNSW index.
    private var index: USearchIndex

    /// Tracked capacity (since USearch's capacity property is internal).
    private var trackedCapacity: UInt32

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
        trackedCapacity = Self.initialCapacity

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
        try index.reserve(Self.initialCapacity)
    }

    // MARK: - Capacity Management

    /// Expand index capacity when exhausted.
    private func expandCapacity() throws {
        let currentSize = UInt32(idToKey.count)

        let newCapacity = max(
            trackedCapacity * Self.capacityGrowthFactor,
            currentSize + Self.initialCapacity
        )

        logger.info("Expanding vector index capacity", metadata: [
            "currentCapacity": "\(trackedCapacity)",
            "currentSize": "\(currentSize)",
            "newCapacity": "\(newCapacity)",
        ])

        try index.reserve(newCapacity)
        trackedCapacity = newCapacity
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

        // Retry loop for handling burst insertions during capacity expansion
        var retries = 0
        let maxRetries = 3

        while true {
            do {
                try index.add(key: key, vector: vector)
                break // Success - exit retry loop
            } catch let usearchError as USearchError {
                if case .reservationError = usearchError {
                    // Capacity exhausted - expand and retry
                    retries += 1
                    if retries > maxRetries {
                        logger.error("Vector index capacity exhausted after retries", metadata: [
                            "retries": "\(retries)",
                            "id": "\(id)",
                        ])
                        throw VectorStoreError.capacityExhausted(retries: retries)
                    }
                    logger.debug("Expanding capacity (retry \(retries)/\(maxRetries))")
                    try expandCapacity()
                } else {
                    logger.warning("USearch add failed", metadata: [
                        "error": "\(usearchError)",
                        "id": "\(id)",
                    ])
                    throw usearchError
                }
            } catch {
                logger.warning("USearch add failed", metadata: [
                    "error": "\(error)",
                    "id": "\(id)",
                ])
                throw error
            }
        }

        idToKey[id] = key
        keyToId[key] = id
    }

    public func addBatch(_ items: [(id: String, vector: [Float])]) async throws {
        guard !items.isEmpty else { return }

        // Validate all dimensions upfront - fail fast before any mutations
        for (_, vector) in items {
            guard vector.count == dimension else {
                throw VectorStoreError.dimensionMismatch(expected: dimension, actual: vector.count)
            }
        }

        // Remove existing vectors and prepare keys atomically
        var keysAndVectors: [(key: USearchKey, vector: [Float], id: String)] = []
        for (id, vector) in items {
            if let existingKey = idToKey[id] {
                _ = try index.remove(key: existingKey)
                keyToId.removeValue(forKey: existingKey)
                idToKey.removeValue(forKey: id)
            }
            let key = nextKey
            nextKey += 1
            keysAndVectors.append((key: key, vector: vector, id: id))
        }

        // Proactively ensure capacity with buffer - single reserve() call for entire batch
        // This is critical: multiple reserve() calls can corrupt the HNSW graph
        let requiredCapacity = UInt32(idToKey.count) + UInt32(keysAndVectors.count)
        if requiredCapacity > trackedCapacity {
            let newCapacity = max(
                requiredCapacity + Self.initialCapacity / 2, // 50% buffer
                trackedCapacity * Self.capacityGrowthFactor
            )
            logger.info("Pre-allocating vector index capacity for batch", metadata: [
                "batchSize": "\(items.count)",
                "currentCapacity": "\(trackedCapacity)",
                "newCapacity": "\(newCapacity)",
            ])
            try index.reserve(newCapacity)
            trackedCapacity = newCapacity
        }

        // Insert all vectors atomically - NO individual expandCapacity() calls
        // Since capacity is pre-allocated, all insertions will succeed without reserve()
        for (key, vector, id) in keysAndVectors {
            try index.add(key: key, vector: vector)
            idToKey[id] = key
            keyToId[key] = id
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

    public func getBatch(ids: [String]) async throws -> [String: [Float]] {
        var result: [String: [Float]] = [:]
        result.reserveCapacity(ids.count)

        for id in ids {
            if let key = idToKey[id] {
                if let vectors: [[Float]] = try index.get(key: key, count: 1),
                   let vector = vectors.first
                {
                    result[id] = vector
                }
            }
        }

        return result
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

        // Save ID mappings (including dimension for validation on load)
        let mapping = VectorStoreMapping(
            idToKey: idToKey,
            keyToId: keyToId.reduce(into: [:]) { $0[String($1.key)] = $1.value },
            nextKey: nextKey,
            dimension: dimension,
            capacity: trackedCapacity
        )

        let data = try JSONCodec.encodePretty(mapping)
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

        // Load ID mappings first to validate dimension before loading index
        let data = try Data(contentsOf: URL(fileURLWithPath: mappingPath))
        let mapping = try JSONCodec.makeDecoder().decode(VectorStoreMapping.self, from: data)

        // Validate dimension matches if stored in mapping
        if let storedDimension = mapping.dimension, storedDimension != dimension {
            throw VectorStoreError.indexDimensionMismatch(
                indexDimension: storedDimension,
                message: """
                Index has dimension \(storedDimension), expected \(dimension).
                This usually happens when you change the embedding provider or model.

                To fix this, delete the index and reindex:
                  rm -rf .swiftindex
                  swiftindex index .
                """
            )
        }

        // Load the HNSW index
        try index.load(path: indexPath)

        idToKey = mapping.idToKey
        keyToId = mapping.keyToId.reduce(into: [:]) {
            if let key = USearchKey($1.key) {
                $0[key] = $1.value
            }
        }
        nextKey = mapping.nextKey
        trackedCapacity = mapping.capacity ?? max(Self.initialCapacity, UInt32(idToKey.count) * 2)
    }

    public func clear() async throws {
        // Clear in-memory state
        try index.clear()
        idToKey.removeAll()
        keyToId.removeAll()
        nextKey = 0
        trackedCapacity = Self.initialCapacity

        // Re-reserve capacity after clear - USearch resets capacity to 0 on clear()
        try index.reserve(Self.initialCapacity)

        // Delete persistence files to ensure clean slate on next save
        if let indexPath {
            try Self.deleteIndex(at: indexPath)
        }
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

// MARK: - Static Dimension Utilities

public extension USearchVectorStore {
    /// Check the dimension of an existing index at the given path.
    ///
    /// Returns `nil` if no index exists or dimension is not stored.
    ///
    /// - Parameter path: Path to the `.usearch` index file (without `.mapping` extension).
    /// - Returns: The stored dimension, or nil if unavailable.
    static func existingDimension(at path: String) -> Int? {
        let mappingPath = path + ".mapping"
        guard FileManager.default.fileExists(atPath: mappingPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: mappingPath)),
              let info = try? JSONCodec.decode(VectorStoreDimensionInfo.self, from: data)
        else {
            return nil
        }
        return info.dimension
    }

    /// Delete existing index files at the given path.
    ///
    /// Removes both the `.usearch` index file and the `.mapping` file.
    ///
    /// - Parameter path: Path to the `.usearch` index file.
    /// - Throws: If file deletion fails.
    static func deleteIndex(at path: String) throws {
        let mappingPath = path + ".mapping"
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
        if fm.fileExists(atPath: mappingPath) {
            try fm.removeItem(atPath: mappingPath)
        }
    }
}

// MARK: - VectorStoreDimensionInfo

/// Minimal struct for reading dimension from mapping file.
private struct VectorStoreDimensionInfo: Codable {
    let dimension: Int?
}

// MARK: - VectorStoreMapping

/// Serializable mapping for index persistence.
private struct VectorStoreMapping: Codable {
    let idToKey: [String: USearchKey]
    let keyToId: [String: String] // String key for JSON compatibility
    let nextKey: USearchKey
    /// Dimension of vectors (added for validation on load).
    let dimension: Int?
    /// Tracked capacity (added for restoration on load).
    let capacity: UInt32?
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
    case capacityExhausted(retries: Int)
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
        case let .capacityExhausted(retries):
            "Vector index capacity exhausted after \(retries) expansion attempts"
        }
    }
}
