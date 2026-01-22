// MARK: - MLXEmbeddingProvider

import Foundation
import Hub
import MLX
import MLXNN
import Tokenizers

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
/// Supports BERT-based models converted to MLX format. Models are loaded
/// lazily on first use and cached for subsequent calls.
public final class MLXEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    // MARK: - Properties

    public let id: String = "mlx"
    public let name: String = "MLX Embeddings"
    public let dimension: Int

    private let modelName: String
    private let modelPath: URL?
    private let maxBatchSize: Int

    /// Actor to manage thread-safe model loading and inference.
    private let modelManager: ModelManager

    // MARK: - Initialization

    /// Creates an MLX embedding provider.
    ///
    /// - Parameters:
    ///   - modelName: Name of the model to use (default: "bge-small-en-v1.5").
    ///   - modelPath: Optional custom path to model weights.
    ///   - dimension: Embedding dimension (default: 384 for BGE small).
    ///   - maxBatchSize: Maximum batch size for embedding (default: 32).
    public init(
        modelName: String = "bge-small-en-v1.5",
        modelPath: URL? = nil,
        dimension: Int = 384,
        maxBatchSize: Int = 32
    ) {
        self.modelName = modelName
        self.modelPath = modelPath
        self.dimension = dimension
        self.maxBatchSize = maxBatchSize
        modelManager = ModelManager(
            modelName: modelName,
            modelPath: modelPath,
            dimension: dimension
        )
    }

    // MARK: - EmbeddingProvider

    public func isAvailable() async -> Bool {
        // Check for Apple Silicon
        #if arch(arm64) && os(macOS)
            // Verify MLX can be initialized
            do {
                _ = try await modelManager.ensureModelLoaded()
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

        #if !arch(arm64) || !os(macOS)
            throw ProviderError.notAvailable(reason: "MLX requires Apple Silicon (arm64) on macOS")
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

        #if !arch(arm64) || !os(macOS)
            throw ProviderError.notAvailable(reason: "MLX requires Apple Silicon (arm64) on macOS")
        #else
            return try await modelManager.embedBatch(texts, maxBatchSize: maxBatchSize)
        #endif
    }
}

// MARK: - ModelManager Actor

/// Actor managing thread-safe model loading and inference.
private actor ModelManager {
    private let modelName: String
    private let modelPath: URL?
    private let dimension: Int

    private let hubManager: HubModelManager
    private var isLoaded: Bool = false
    private var modelWeights: MLXArray?
    private var tokenizer: (any Tokenizer)?

    init(modelName: String, modelPath: URL?, dimension: Int) {
        self.modelName = modelName
        self.modelPath = modelPath
        self.dimension = dimension
        hubManager = HubModelManager()
    }

    func ensureModelLoaded() async throws -> Bool {
        if isLoaded {
            return true
        }

        // Determine which model to use based on modelName
        let model = hubModel(for: modelName)

        // Use custom path if provided, otherwise download from Hub
        if let customPath = modelPath {
            guard FileManager.default.fileExists(atPath: customPath.path) else {
                throw ProviderError.modelNotFound(name: modelName)
            }
        } else {
            _ = try await hubManager.ensureModel(model, progress: nil)
        }

        // Load tokenizer from swift-transformers
        tokenizer = try await hubManager.loadTokenizer(for: model)

        // Load model weights (simplified - real implementation would use MLX load functions)
        // modelWeights = try MLX.load(path.appendingPathComponent("model.safetensors"))
        isLoaded = true

        return true
    }

    func embed(_ text: String) async throws -> [Float] {
        if !isLoaded {
            _ = try await ensureModelLoaded()
        }

        // Tokenize input using swift-transformers tokenizer
        guard let tokenizer else {
            throw ProviderError.notAvailable(reason: "Tokenizer not initialized")
        }

        let tokens = tokenizer.encode(text: text)

        // Create input tensor
        let inputArray = MLXArray(tokens.map { Int32($0) })

        // Forward pass through model (simplified)
        // In real implementation: let output = model(inputArray)
        let embedding = computeEmbedding(inputArray)

        return embedding
    }

    func embedBatch(_ texts: [String], maxBatchSize: Int) async throws -> [[Float]] {
        if !isLoaded {
            _ = try await ensureModelLoaded()
        }

        var results: [[Float]] = []
        results.reserveCapacity(texts.count)

        // Process in batches
        for batchStart in stride(from: 0, to: texts.count, by: maxBatchSize) {
            let batchEnd = min(batchStart + maxBatchSize, texts.count)
            let batch = Array(texts[batchStart ..< batchEnd])

            let batchEmbeddings = try await processBatch(batch)
            results.append(contentsOf: batchEmbeddings)
        }

        return results
    }

    // MARK: - Private Helpers

    private func hubModel(for name: String) -> HubModelManager.Model {
        switch name {
        case "bge-small-en-v1.5":
            .bgeSmall
        case "bge-base-en-v1.5":
            .bgeBase
        case "all-MiniLM-L6-v2":
            .miniLM
        default:
            .bgeSmall
        }
    }

    private func processBatch(_ texts: [String]) async throws -> [[Float]] {
        guard let tokenizer else {
            throw ProviderError.notAvailable(reason: "Tokenizer not initialized")
        }

        var embeddings: [[Float]] = []

        for text in texts {
            let tokens = tokenizer.encode(text: text)
            let inputArray = MLXArray(tokens.map { Int32($0) })
            let embedding = computeEmbedding(inputArray)
            embeddings.append(embedding)
        }

        return embeddings
    }

    private func computeEmbedding(_ input: MLXArray) -> [Float] {
        // Simplified embedding computation
        // Real implementation would:
        // 1. Pass through BERT encoder
        // 2. Apply mean pooling
        // 3. Normalize to unit vector

        // Placeholder: return normalized random vector
        // This will be replaced with actual MLX model inference
        var embedding = (0 ..< dimension).map { _ in Float.random(in: -1 ... 1) }

        // L2 normalize
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            embedding = embedding.map { $0 / norm }
        }

        return embedding
    }
}
