// MARK: - VoyageProvider

import Foundation

/// An embedding provider that uses Voyage AI's API.
///
/// Voyage AI provides high-quality embeddings optimized for code understanding.
/// Requires an API key from https://www.voyageai.com/
///
/// ## Usage
///
/// ```swift
/// let provider = VoyageProvider(apiKey: "your-api-key")
/// if await provider.isAvailable() {
///     let embedding = try await provider.embed("func hello() { print(\"Hi\") }")
/// }
/// ```
///
/// ## Models
///
/// - `voyage-code-2` - Optimized for code (default)
/// - `voyage-large-2` - General purpose, highest quality
/// - `voyage-2` - General purpose, balanced
public struct VoyageProvider: EmbeddingProvider, Sendable {
    // MARK: - Properties

    public let id: String
    public let name: String
    public let dimension: Int

    /// The API key for Voyage AI.
    private let apiKey: String

    /// The model to use for embeddings.
    public let modelName: String

    /// Maximum texts per batch request.
    public let maxBatchSize: Int

    /// URL session for making requests.
    private let session: URLSession

    /// Base URL for Voyage API.
    private static let baseURL = URL(string: "https://api.voyageai.com/v1")!

    // MARK: - Initialization

    /// Creates a Voyage AI embedding provider.
    ///
    /// - Parameters:
    ///   - apiKey: Your Voyage AI API key.
    ///   - modelName: Name of the embedding model. Default is `voyage-code-2`.
    ///   - dimension: Embedding dimension for the model. Default is 1024.
    ///   - maxBatchSize: Maximum texts per request. Default is 128.
    public init(
        apiKey: String,
        modelName: String = "voyage-code-2",
        dimension: Int = 1024,
        maxBatchSize: Int = 128
    ) {
        id = "voyage"
        name = "Voyage AI Provider"
        self.dimension = dimension
        self.apiKey = apiKey
        self.modelName = modelName
        self.maxBatchSize = maxBatchSize

        // Configure session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
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

        let payload = VoyageRequest(model: modelName, input: texts, inputType: "document")
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
        let embeddingResponse = try JSONDecoder().decode(VoyageResponse.self, from: data)
        return embeddingResponse.data.map { $0.embedding.map { Float($0) } }
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

private struct VoyageRequest: Encodable {
    let model: String
    let input: [String]
    let inputType: String

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case inputType = "input_type"
    }
}

private struct VoyageResponse: Decodable {
    let data: [EmbeddingData]

    struct EmbeddingData: Decodable {
        let embedding: [Double]
    }
}

// MARK: - Array Extension

extension Array {
    /// Splits array into chunks of specified size.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
