// MARK: - OpenAIProvider

import Foundation

/// An embedding provider that uses OpenAI's API.
///
/// OpenAI provides high-quality embeddings through their text-embedding models.
/// Requires an API key from https://platform.openai.com/
///
/// ## Usage
///
/// ```swift
/// let provider = OpenAIProvider(apiKey: "sk-...")
/// if await provider.isAvailable() {
///     let embedding = try await provider.embed("Hello, world!")
/// }
/// ```
///
/// ## Models
///
/// - `text-embedding-3-small` - Fast and affordable (default)
/// - `text-embedding-3-large` - Higher quality, more dimensions
/// - `text-embedding-ada-002` - Legacy model
public struct OpenAIProvider: EmbeddingProvider, Sendable {
    // MARK: - Properties

    public let id: String
    public let name: String
    public let dimension: Int

    /// The API key for OpenAI.
    private let apiKey: String

    /// The model to use for embeddings.
    public let modelName: String

    /// Maximum texts per batch request.
    public let maxBatchSize: Int

    /// URL session for making requests.
    private let session: URLSession

    /// Base URL for OpenAI API.
    private static let baseURL = URL(string: "https://api.openai.com/v1")!

    // MARK: - Model Configurations

    /// Supported OpenAI embedding models.
    public enum Model: String, Sendable {
        case textEmbedding3Small = "text-embedding-3-small"
        case textEmbedding3Large = "text-embedding-3-large"
        case textEmbeddingAda002 = "text-embedding-ada-002"

        /// Default dimension for this model.
        public var defaultDimension: Int {
            switch self {
            case .textEmbedding3Small: 1536
            case .textEmbedding3Large: 3072
            case .textEmbeddingAda002: 1536
            }
        }

        /// Maximum tokens per input.
        public var maxTokens: Int {
            switch self {
            case .textEmbedding3Small, .textEmbedding3Large: 8191
            case .textEmbeddingAda002: 8191
            }
        }
    }

    // MARK: - Initialization

    /// Creates an OpenAI embedding provider.
    ///
    /// - Parameters:
    ///   - apiKey: Your OpenAI API key.
    ///   - model: The embedding model to use. Default is `.textEmbedding3Small`.
    ///   - dimension: Optional dimension override (for models that support it).
    ///   - maxBatchSize: Maximum texts per request. Default is 2048.
    public init(
        apiKey: String,
        model: Model = .textEmbedding3Small,
        dimension: Int? = nil,
        maxBatchSize: Int = 2048
    ) {
        self.id = "openai"
        self.name = "OpenAI Embedding Provider"
        self.dimension = dimension ?? model.defaultDimension
        self.apiKey = apiKey
        self.modelName = model.rawValue
        self.maxBatchSize = maxBatchSize

        // Configure session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    /// Creates an OpenAI embedding provider with a custom model name.
    ///
    /// - Parameters:
    ///   - apiKey: Your OpenAI API key.
    ///   - modelName: Custom model name.
    ///   - dimension: Embedding dimension.
    ///   - maxBatchSize: Maximum texts per request. Default is 2048.
    public init(
        apiKey: String,
        modelName: String,
        dimension: Int,
        maxBatchSize: Int = 2048
    ) {
        self.id = "openai"
        self.name = "OpenAI Embedding Provider"
        self.dimension = dimension
        self.apiKey = apiKey
        self.modelName = modelName
        self.maxBatchSize = maxBatchSize

        // Configure session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - EmbeddingProvider

    public func isAvailable() async -> Bool {
        // Provider is available if API key is configured
        !apiKey.isEmpty
    }

    public func embed(_ text: String) async throws -> [Float] {
        let embeddings = try await embed([text])
        guard let first = embeddings.first else {
            throw ProviderError.embeddingFailed("No embedding returned")
        }
        return first
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else {
            return []
        }

        // Process in batches
        var results: [[Float]] = []

        for batch in texts.chunked(into: maxBatchSize) {
            let batchResults = try await generateEmbeddings(for: batch)
            results.append(contentsOf: batchResults)
        }

        return results
    }

    // MARK: - Private Methods

    private func generateEmbeddings(for texts: [String]) async throws -> [[Float]] {
        let embeddingsURL = Self.baseURL.appendingPathComponent("embeddings")

        // Build request
        var request = URLRequest(url: embeddingsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = OpenAIRequest(model: modelName, input: texts, dimensions: dimension)
        request.httpBody = try JSONEncoder().encode(payload)

        // Make request
        let (data, response) = try await session.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response type")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = parseErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            throw ProviderError.networkError(errorMessage)
        }

        // Parse response
        let embeddingResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)

        // Sort by index to maintain input order
        let sorted = embeddingResponse.data.sorted { $0.index < $1.index }
        return sorted.map { $0.embedding.map { Float($0) } }
    }

    private func parseErrorMessage(from data: Data) -> String? {
        struct ErrorResponse: Decodable {
            let error: ErrorDetail?
            struct ErrorDetail: Decodable {
                let message: String?
            }
        }

        if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            return errorResponse.error?.message
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Request/Response Types

private struct OpenAIRequest: Encodable {
    let model: String
    let input: [String]
    let dimensions: Int?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(input, forKey: .input)
        // Only encode dimensions if it's not the default (for dimension-aware models)
        if let dimensions, model.contains("text-embedding-3") {
            try container.encode(dimensions, forKey: .dimensions)
        }
    }

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case dimensions
    }
}

private struct OpenAIResponse: Decodable {
    let data: [EmbeddingData]
    let model: String
    let usage: Usage

    struct EmbeddingData: Decodable {
        let embedding: [Double]
        let index: Int
    }

    struct Usage: Decodable {
        let promptTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case totalTokens = "total_tokens"
        }
    }
}
