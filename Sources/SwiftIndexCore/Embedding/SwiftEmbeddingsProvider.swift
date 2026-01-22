// MARK: - SwiftEmbeddingsProvider

import Embeddings
import Foundation

/// Embedding provider using the swift-embeddings package.
///
/// This provider offers pure Swift embedding generation that works on all
/// Apple platforms without requiring Apple Silicon. It serves as a reliable
/// fallback when MLX is unavailable.
///
/// ## Features
///
/// - Cross-platform support (macOS 15+, iOS 18+)
/// - Multiple model options (BERT, MiniLM, BGE)
/// - Automatic model downloading and caching
/// - Thread-safe operation via actor isolation
///
/// ## Models
///
/// Default model is `all-MiniLM-L6-v2` with 384 dimensions.
/// Other supported models:
/// - `bge-small-en-v1.5` (384 dimensions)
/// - `bge-base-en-v1.5` (768 dimensions)
///
/// ## Availability
///
/// Requires macOS 15.0+ due to MLTensor dependency in swift-embeddings.
public final class SwiftEmbeddingsProvider: EmbeddingProvider, @unchecked Sendable {
    // MARK: - Properties

    public let id: String = "swift-embeddings"
    public let name: String = "Swift Embeddings"
    public let dimension: Int

    private let modelName: String
    private let maxBatchSize: Int
    private let huggingFaceId: String

    // MARK: - Supported Models

    /// Available embedding models with their configurations.
    public enum Model: String, Sendable, CaseIterable {
        case miniLM = "all-MiniLM-L6-v2"
        case bgeSmall = "bge-small-en-v1.5"
        case bgeBase = "bge-base-en-v1.5"

        public var dimension: Int {
            switch self {
            case .miniLM, .bgeSmall:
                384
            case .bgeBase:
                768
            }
        }

        public var huggingFaceId: String {
            switch self {
            case .miniLM:
                "sentence-transformers/all-MiniLM-L6-v2"
            case .bgeSmall:
                "BAAI/bge-small-en-v1.5"
            case .bgeBase:
                "BAAI/bge-base-en-v1.5"
            }
        }
    }

    // MARK: - Initialization

    /// Creates a Swift embeddings provider with a specific model.
    ///
    /// - Parameters:
    ///   - model: The embedding model to use.
    ///   - maxBatchSize: Maximum texts per batch (default: 32).
    public init(model: Model = .miniLM, maxBatchSize: Int = 32) {
        modelName = model.huggingFaceId
        huggingFaceId = model.huggingFaceId
        dimension = model.dimension
        self.maxBatchSize = maxBatchSize
    }

    /// Creates a Swift embeddings provider with a custom HuggingFace model ID.
    ///
    /// - Parameters:
    ///   - huggingFaceId: The HuggingFace model ID (e.g., "sentence-transformers/all-MiniLM-L6-v2").
    ///   - dimension: The embedding dimension.
    ///   - maxBatchSize: Maximum texts per batch (default: 32).
    public init(huggingFaceId: String, dimension: Int, maxBatchSize: Int = 32) {
        modelName = huggingFaceId
        self.huggingFaceId = huggingFaceId
        self.dimension = dimension
        self.maxBatchSize = maxBatchSize
    }

    // MARK: - EmbeddingProvider

    public func isAvailable() async -> Bool {
        // Swift embeddings requires macOS 15.0+ due to MLTensor dependency
        guard #available(macOS 15.0, *) else {
            return false
        }

        // Verify the model can be loaded
        do {
            let manager = SwiftEmbeddingsModelManager(huggingFaceId: huggingFaceId, dimension: dimension)
            try await manager.ensureModelLoaded()
            return true
        } catch {
            return false
        }
    }

    public func embed(_ text: String) async throws -> [Float] {
        guard !text.isEmpty else {
            throw ProviderError.invalidInput("Text cannot be empty")
        }

        guard #available(macOS 15.0, *) else {
            throw ProviderError.notAvailable(reason: "Swift Embeddings requires macOS 15.0 or later")
        }

        let manager = SwiftEmbeddingsModelManager(huggingFaceId: huggingFaceId, dimension: dimension)
        return try await manager.embed(text)
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else {
            return []
        }

        for (index, text) in texts.enumerated() where text.isEmpty {
            throw ProviderError.invalidInput("Text at index \(index) cannot be empty")
        }

        guard #available(macOS 15.0, *) else {
            throw ProviderError.notAvailable(reason: "Swift Embeddings requires macOS 15.0 or later")
        }

        let manager = SwiftEmbeddingsModelManager(huggingFaceId: huggingFaceId, dimension: dimension)
        return try await manager.embedBatch(texts, maxBatchSize: maxBatchSize)
    }
}

// MARK: - SwiftEmbeddingsModelManager Actor

/// Actor managing thread-safe model loading and embedding generation using swift-embeddings.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
private actor SwiftEmbeddingsModelManager {
    private let huggingFaceId: String
    private let expectedDimension: Int

    private var isLoaded: Bool = false
    private var modelBundle: Bert.ModelBundle?

    init(huggingFaceId: String, dimension: Int) {
        self.huggingFaceId = huggingFaceId
        expectedDimension = dimension
    }

    func ensureModelLoaded() async throws {
        if isLoaded, modelBundle != nil {
            return
        }

        do {
            // Load BERT model bundle from HuggingFace using swift-embeddings
            modelBundle = try await Bert.loadModelBundle(from: huggingFaceId)
            isLoaded = true
        } catch {
            throw ProviderError.modelNotFound(name: huggingFaceId)
        }
    }

    func embed(_ text: String) async throws -> [Float] {
        try await ensureModelLoaded()

        guard let bundle = modelBundle else {
            throw ProviderError.notAvailable(reason: "Model not loaded")
        }

        // Use swift-embeddings encode API
        let encoded = try bundle.encode(text)

        // Convert MLTensor result to [Float]
        let embedding = await encoded.cast(to: Float.self).shapedArray(of: Float.self).scalars

        // Validate dimension
        guard embedding.count == expectedDimension else {
            throw ProviderError.dimensionMismatch(expected: expectedDimension, actual: embedding.count)
        }

        return embedding
    }

    func embedBatch(_ texts: [String], maxBatchSize: Int) async throws -> [[Float]] {
        try await ensureModelLoaded()

        guard let bundle = modelBundle else {
            throw ProviderError.notAvailable(reason: "Model not loaded")
        }

        var results: [[Float]] = []
        results.reserveCapacity(texts.count)

        // Process in batches for memory efficiency
        for batchStart in stride(from: 0, to: texts.count, by: maxBatchSize) {
            let batchEnd = min(batchStart + maxBatchSize, texts.count)
            let batch = Array(texts[batchStart ..< batchEnd])

            // Use swift-embeddings batchEncode API
            let encoded = try bundle.batchEncode(batch)

            // Convert MLTensor batch result to [[Float]]
            // The result shape is [batch_size, dimension]
            let batchResult = await encoded.cast(to: Float.self).shapedArray(of: Float.self)
            let shape = batchResult.shape

            // Extract individual embeddings from batch
            if shape.count == 2 {
                let batchSize = shape[0]
                let dim = shape[1]
                let scalars = batchResult.scalars

                for i in 0 ..< batchSize {
                    let start = i * dim
                    let end = start + dim
                    let embedding = Array(scalars[start ..< end])
                    results.append(embedding)
                }
            } else {
                // Fallback: encode one by one
                for text in batch {
                    let single = try bundle.encode(text)
                    let embedding = await single.cast(to: Float.self).shapedArray(of: Float.self).scalars
                    results.append(embedding)
                }
            }
        }

        return results
    }
}
