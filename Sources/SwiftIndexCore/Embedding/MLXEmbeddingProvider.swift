// MARK: - MLXEmbeddingProvider

import Foundation

#if canImport(MLX) && canImport(MLXEmbedders)
    import MLX
    import MLXEmbedders
    import Tokenizers
#endif

/// Embedding provider using Apple MLX for native Apple Silicon acceleration.
///
/// This provider leverages MLX's efficient Metal-based computation for
/// generating embeddings directly on Apple Silicon hardware. It provides
/// the fastest local embedding generation when available.
///
/// ## Availability
///
/// MLX requires Apple Silicon (M1 or later). The provider checks for
/// hardware compatibility before attempting to load models.
///
/// ## Models
///
/// Uses MLXEmbedders from mlx-swift-lm package. Supported models:
/// - `nomic-ai/nomic-embed-text-v1.5` (768 dim, default)
/// - `BAAI/bge-small-en-v1.5` (384 dim)
/// - `BAAI/bge-base-en-v1.5` (768 dim)
public final class MLXEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    // MARK: - Properties

    public let id: String = "mlx"
    public let name: String = "MLX Embeddings"
    public let dimension: Int

    private let modelId: String
    private let maxBatchSize: Int

    #if canImport(MLX) && canImport(MLXEmbedders)
        /// Actor to manage thread-safe model loading and inference.
        private let modelManager: MLXModelManager
    #endif

    // MARK: - Supported Models

    /// Available MLX embedding models.
    public enum Model: String, Sendable, CaseIterable {
        case nomicEmbedText = "nomic-embed-text-v1.5"
        case bgeSmall = "bge-small-en-v1.5"
        case bgeBase = "bge-base-en-v1.5"

        public var dimension: Int {
            switch self {
            case .nomicEmbedText, .bgeBase:
                768
            case .bgeSmall:
                384
            }
        }

        public var huggingFaceId: String {
            switch self {
            case .nomicEmbedText:
                "nomic-ai/nomic-embed-text-v1.5"
            case .bgeSmall:
                "BAAI/bge-small-en-v1.5"
            case .bgeBase:
                "BAAI/bge-base-en-v1.5"
            }
        }
    }

    // MARK: - Initialization

    /// Creates an MLX embedding provider with a specific model.
    ///
    /// - Parameters:
    ///   - model: The embedding model to use (default: nomicEmbedText).
    ///   - maxBatchSize: Maximum batch size for embedding (default: 32).
    public init(model: Model = .nomicEmbedText, maxBatchSize: Int = 32) {
        modelId = model.huggingFaceId
        dimension = model.dimension
        self.maxBatchSize = maxBatchSize
        #if canImport(MLX) && canImport(MLXEmbedders)
            modelManager = MLXModelManager(modelId: model.huggingFaceId, dimension: model.dimension)
        #endif
    }

    /// Creates an MLX embedding provider with a custom HuggingFace model ID.
    ///
    /// - Parameters:
    ///   - huggingFaceId: The HuggingFace model ID.
    ///   - dimension: Embedding dimension (default: 768).
    ///   - maxBatchSize: Maximum batch size for embedding (default: 32).
    public init(huggingFaceId: String, dimension: Int = 768, maxBatchSize: Int = 32) {
        modelId = huggingFaceId
        self.dimension = dimension
        self.maxBatchSize = maxBatchSize
        #if canImport(MLX) && canImport(MLXEmbedders)
            modelManager = MLXModelManager(modelId: huggingFaceId, dimension: dimension)
        #endif
    }

    // MARK: - EmbeddingProvider

    public func isAvailable() async -> Bool {
        // Check for Apple Silicon
        #if arch(arm64) && os(macOS) && canImport(MLX) && canImport(MLXEmbedders)
            // Verify MLX can be initialized
            do {
                try await modelManager.ensureModelLoaded()
                return true
            } catch {
                return false
            }
        #else
            return false
        #endif
    }

    public func embed(_ text: String) async throws -> [Float] {
        guard !text.isEmpty else {
            throw ProviderError.invalidInput("Text cannot be empty")
        }

        #if !arch(arm64) || !os(macOS) || !canImport(MLX) || !canImport(MLXEmbedders)
            throw ProviderError.notAvailable(reason: "MLX requires Apple Silicon (arm64) on macOS with mlx-swift-lm")
        #else
            return try await modelManager.embed(text)
        #endif
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else {
            return []
        }

        for (index, text) in texts.enumerated() where text.isEmpty {
            throw ProviderError.invalidInput("Text at index \(index) cannot be empty")
        }

        #if !arch(arm64) || !os(macOS) || !canImport(MLX) || !canImport(MLXEmbedders)
            throw ProviderError.notAvailable(reason: "MLX requires Apple Silicon (arm64) on macOS with mlx-swift-lm")
        #else
            return try await modelManager.embedBatch(texts, maxBatchSize: maxBatchSize)
        #endif
    }
}

// MARK: - MLXModelManager Actor

#if canImport(MLX) && canImport(MLXEmbedders)

    /// Actor managing thread-safe MLX model loading and inference using MLXEmbedders.
    private actor MLXModelManager {
        private let modelId: String
        private let expectedDimension: Int

        private var isLoaded: Bool = false
        private var modelContainer: ModelContainer?

        init(modelId: String, dimension: Int) {
            self.modelId = modelId
            expectedDimension = dimension
        }

        func ensureModelLoaded() async throws {
            if isLoaded, modelContainer != nil {
                return
            }

            do {
                // Load embedding model using MLXEmbedders
                let configuration = ModelConfiguration(id: modelId)
                modelContainer = try await MLXEmbedders.loadModelContainer(configuration: configuration)
                isLoaded = true
            } catch {
                throw ProviderError.modelNotFound(name: modelId)
            }
        }

        func embed(_ text: String) async throws -> [Float] {
            try await ensureModelLoaded()

            guard let container = modelContainer else {
                throw ProviderError.notAvailable(reason: "Model not loaded")
            }

            let embedding = await container.perform { model, tokenizer, pooler -> [Float] in
                // Tokenize input
                let tokens = tokenizer.encode(text: text, addSpecialTokens: true)

                // Create input tensor
                let inputArray = MLXArray(tokens)
                let padded = inputArray.reshaped([1, tokens.count])
                let mask = MLXArray.ones([1, tokens.count])
                let tokenTypes = MLXArray.zeros([1, tokens.count])

                // Forward pass through model
                let output = model(padded, positionIds: nil, tokenTypeIds: tokenTypes, attentionMask: mask)

                // Apply pooling and normalization
                let pooled = pooler(output, mask: mask, normalize: true, applyLayerNorm: true)
                eval(pooled)

                return pooled[0].asArray(Float.self)
            }

            // Validate dimension
            guard embedding.count == expectedDimension else {
                throw ProviderError.dimensionMismatch(expected: expectedDimension, actual: embedding.count)
            }

            return embedding
        }

        func embedBatch(_ texts: [String], maxBatchSize: Int) async throws -> [[Float]] {
            try await ensureModelLoaded()

            guard let container = modelContainer else {
                throw ProviderError.notAvailable(reason: "Model not loaded")
            }

            var results: [[Float]] = []
            results.reserveCapacity(texts.count)

            // Process in batches
            for batchStart in stride(from: 0, to: texts.count, by: maxBatchSize) {
                let batchEnd = min(batchStart + maxBatchSize, texts.count)
                let batch = Array(texts[batchStart ..< batchEnd])

                let batchEmbeddings = await container.perform { model, tokenizer, pooler -> [[Float]] in
                    // Tokenize all inputs
                    let tokenizedInputs = batch.map {
                        tokenizer.encode(text: $0, addSpecialTokens: true)
                    }

                    // Pad to longest sequence
                    let maxLength = tokenizedInputs.reduce(into: 16) { acc, elem in
                        acc = max(acc, elem.count)
                    }

                    let padToken = tokenizer.eosTokenId ?? 0

                    let padded = stacked(
                        tokenizedInputs.map { tokens in
                            MLXArray(
                                tokens + Array(repeating: padToken, count: maxLength - tokens.count)
                            )
                        }
                    )

                    let mask = (padded .!= padToken)
                    let tokenTypes = MLXArray.zeros(like: padded)

                    // Forward pass through model
                    let output = model(padded, positionIds: nil, tokenTypeIds: tokenTypes, attentionMask: mask)

                    // Apply pooling and normalization
                    let pooled = pooler(output, mask: mask, normalize: true, applyLayerNorm: true)
                    eval(pooled)

                    // Extract individual embeddings from batch result
                    let batchSize = pooled.shape[0]
                    var embeddings: [[Float]] = []
                    for i in 0 ..< batchSize {
                        embeddings.append(pooled[i].asArray(Float.self))
                    }
                    return embeddings
                }

                results.append(contentsOf: batchEmbeddings)
            }

            return results
        }
    }

#endif
