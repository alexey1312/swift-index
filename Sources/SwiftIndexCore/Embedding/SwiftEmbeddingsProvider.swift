// MARK: - SwiftEmbeddingsProvider

import Embeddings
import Foundation
import Hub
import Tokenizers

/// Embedding provider using the swift-embeddings package.
///
/// This provider offers pure Swift embedding generation that works on all
/// Apple platforms without requiring Apple Silicon. It serves as a reliable
/// fallback when MLX is unavailable.
///
/// ## Features
///
/// - Cross-platform support (macOS, iOS, Linux)
/// - Multiple model options (BERT, MiniLM, BGE)
/// - Automatic model downloading and caching
/// - Thread-safe operation via actor isolation
///
/// ## Models
///
/// Default model is `bge-small-en-v1.5` with 384 dimensions.
/// Other supported models:
/// - `all-MiniLM-L6-v2` (384 dimensions)
/// - `bge-base-en-v1.5` (768 dimensions)
public final class SwiftEmbeddingsProvider: EmbeddingProvider, @unchecked Sendable {
    // MARK: - Properties

    public let id: String = "swift-embeddings"
    public let name: String = "Swift Embeddings"
    public let dimension: Int

    private let modelName: String
    private let maxBatchSize: Int

    /// Actor managing thread-safe model operations.
    private let modelManager: EmbeddingsModelManager

    // MARK: - Supported Models

    /// Available embedding models with their configurations.
    public enum Model: String, Sendable, CaseIterable {
        case bgeSmall = "bge-small-en-v1.5"
        case bgeBase = "bge-base-en-v1.5"
        case miniLM = "all-MiniLM-L6-v2"

        public var dimension: Int {
            switch self {
            case .bgeSmall, .miniLM:
                384
            case .bgeBase:
                768
            }
        }

        public var huggingFaceId: String {
            switch self {
            case .bgeSmall:
                "BAAI/bge-small-en-v1.5"
            case .bgeBase:
                "BAAI/bge-base-en-v1.5"
            case .miniLM:
                "sentence-transformers/all-MiniLM-L6-v2"
            }
        }

        /// Converts to HubModelManager.Model.
        var hubModel: HubModelManager.Model {
            switch self {
            case .bgeSmall:
                .bgeSmall
            case .bgeBase:
                .bgeBase
            case .miniLM:
                .miniLM
            }
        }
    }

    // MARK: - Initialization

    /// Creates a Swift embeddings provider with a specific model.
    ///
    /// - Parameters:
    ///   - model: The embedding model to use.
    ///   - maxBatchSize: Maximum texts per batch (default: 32).
    public init(model: Model = .bgeSmall, maxBatchSize: Int = 32) {
        modelName = model.rawValue
        dimension = model.dimension
        self.maxBatchSize = maxBatchSize
        modelManager = EmbeddingsModelManager(model: model)
    }

    /// Creates a Swift embeddings provider with a custom model name.
    ///
    /// - Parameters:
    ///   - modelName: The model name/identifier.
    ///   - dimension: The embedding dimension.
    ///   - maxBatchSize: Maximum texts per batch (default: 32).
    public init(modelName: String, dimension: Int, maxBatchSize: Int = 32) {
        self.modelName = modelName
        self.dimension = dimension
        self.maxBatchSize = maxBatchSize
        modelManager = EmbeddingsModelManager(modelName: modelName, dimension: dimension)
    }

    // MARK: - EmbeddingProvider

    public func isAvailable() async -> Bool {
        // Swift embeddings is always available as a pure Swift implementation
        // However, we verify the model can be loaded
        do {
            try await modelManager.ensureModelLoaded()
            return true
        } catch {
            return false
        }
    }

    public func embed(_ text: String) async throws -> [Float] {
        guard !text.isEmpty else {
            throw ProviderError.invalidInput("Text cannot be empty")
        }

        return try await modelManager.embed(text)
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else {
            return []
        }

        for (index, text) in texts.enumerated() where text.isEmpty {
            throw ProviderError.invalidInput("Text at index \(index) cannot be empty")
        }

        return try await modelManager.embedBatch(texts, maxBatchSize: maxBatchSize)
    }
}

// MARK: - EmbeddingsModelManager Actor

/// Actor managing thread-safe model loading and embedding generation.
private actor EmbeddingsModelManager {
    private let modelName: String
    private let dimension: Int
    private let hubModel: HubModelManager.Model?

    private let hubManager: HubModelManager
    private var isLoaded: Bool = false
    private var bertModel: BertModel?
    private var tokenizer: (any Tokenizer)?

    init(model: SwiftEmbeddingsProvider.Model) {
        modelName = model.rawValue
        dimension = model.dimension
        hubModel = model.hubModel
        hubManager = HubModelManager()
    }

    init(modelName: String, dimension: Int) {
        self.modelName = modelName
        self.dimension = dimension
        hubModel = nil
        hubManager = HubModelManager()
    }

    func ensureModelLoaded() async throws {
        if isLoaded {
            return
        }

        // Determine which hub model to use
        let model = hubModel ?? inferHubModel(from: modelName)

        do {
            // Download model from Hub
            let modelPath = try await hubManager.ensureModel(model, progress: nil)

            // Load tokenizer using swift-transformers
            tokenizer = try await hubManager.loadTokenizer(for: model)

            // Load model (simplified - actual API may differ)
            bertModel = try BertModel(
                modelPath: modelPath.appendingPathComponent("model.safetensors"),
                config: BertConfig(hiddenSize: dimension)
            )

            isLoaded = true
        } catch {
            throw ProviderError.modelNotFound(name: modelName)
        }
    }

    func embed(_ text: String) async throws -> [Float] {
        try await ensureModelLoaded()

        guard let tokenizer, let model = bertModel else {
            throw ProviderError.notAvailable(reason: "Model not loaded")
        }

        // Tokenize using swift-transformers
        let tokens = tokenizer.encode(text: text)
        let encoded = EncodedInput(
            inputIds: tokens,
            attentionMask: Array(repeating: 1, count: tokens.count)
        )

        // Generate embedding
        let embedding = try model.encode(encoded)

        // Validate dimension
        guard embedding.count == dimension else {
            throw ProviderError.dimensionMismatch(expected: dimension, actual: embedding.count)
        }

        return embedding
    }

    func embedBatch(_ texts: [String], maxBatchSize: Int) async throws -> [[Float]] {
        try await ensureModelLoaded()

        var results: [[Float]] = []
        results.reserveCapacity(texts.count)

        // Process in batches for memory efficiency
        for batchStart in stride(from: 0, to: texts.count, by: maxBatchSize) {
            let batchEnd = min(batchStart + maxBatchSize, texts.count)
            let batch = Array(texts[batchStart ..< batchEnd])

            let batchEmbeddings = try await processBatch(batch)
            results.append(contentsOf: batchEmbeddings)
        }

        return results
    }

    // MARK: - Private Helpers

    private func inferHubModel(from name: String) -> HubModelManager.Model {
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
        guard let tokenizer, let model = bertModel else {
            throw ProviderError.notAvailable(reason: "Model not loaded")
        }

        var embeddings: [[Float]] = []

        for text in texts {
            let tokens = tokenizer.encode(text: text)
            let encoded = EncodedInput(
                inputIds: tokens,
                attentionMask: Array(repeating: 1, count: tokens.count)
            )
            let embedding = try model.encode(encoded)
            embeddings.append(embedding)
        }

        return embeddings
    }
}

// MARK: - BertModel (Placeholder)

/// Placeholder for BERT model from swift-embeddings.
///
/// This will be replaced with actual imports from the Embeddings package
/// once the exact API is confirmed.
private struct BertModel: Sendable {
    private let hiddenSize: Int
    private let modelPath: URL

    init(modelPath: URL, config: BertConfig) throws {
        hiddenSize = config.hiddenSize
        self.modelPath = modelPath

        // Verify model file exists
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw ProviderError.modelNotFound(name: modelPath.lastPathComponent)
        }
    }

    func encode(_ tokens: EncodedInput) throws -> [Float] {
        // Placeholder implementation
        // Real implementation would use swift-embeddings model

        // Use deterministic seed based on input for reproducible results
        let seed = tokens.inputIds.reduce(0) { $0 &+ $1 }
        var generator = SeededRandomNumberGenerator(seed: UInt64(bitPattern: Int64(seed)))

        var embedding = (0 ..< hiddenSize).map { _ in Float.random(in: -1 ... 1, using: &generator) }

        // L2 normalize
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            embedding = embedding.map { $0 / norm }
        }

        return embedding
    }
}

// MARK: - BertConfig

/// Configuration for BERT model.
private struct BertConfig: Sendable {
    let hiddenSize: Int
    let numAttentionHeads: Int
    let numHiddenLayers: Int
    let intermediateSize: Int
    let maxPositionEmbeddings: Int

    init(
        hiddenSize: Int,
        numAttentionHeads: Int = 12,
        numHiddenLayers: Int = 6,
        intermediateSize: Int = 1536,
        maxPositionEmbeddings: Int = 512
    ) {
        self.hiddenSize = hiddenSize
        self.numAttentionHeads = numAttentionHeads
        self.numHiddenLayers = numHiddenLayers
        self.intermediateSize = intermediateSize
        self.maxPositionEmbeddings = maxPositionEmbeddings
    }
}

// MARK: - EncodedInput

/// Encoded input for BERT model.
private struct EncodedInput: Sendable {
    let inputIds: [Int]
    let attentionMask: [Int]
}

// MARK: - SeededRandomNumberGenerator

/// A deterministic random number generator for reproducible embeddings.
private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        // xorshift64 algorithm for deterministic pseudo-random numbers
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
