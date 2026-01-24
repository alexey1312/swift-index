// MARK: - GeminiEmbeddingProvider

import Foundation

/// An embedding provider that uses Google's Gemini API.
///
/// Requires an API key from Google AI Studio: https://aistudio.google.com/
///
/// ## Usage
///
/// ```swift
/// let provider = GeminiEmbeddingProvider(apiKey: "your-api-key")
/// if await provider.isAvailable() {
///     let embedding = try await provider.embed("func hello() { print(\"Hi\") }")
/// }
/// ```
public struct GeminiEmbeddingProvider: EmbeddingProvider, Sendable {
    // MARK: - Properties

    public let id: String
    public let name: String
    public let dimension: Int

    /// The API key for Gemini.
    private let apiKey: String

    /// The model to use for embeddings.
    public let modelName: String

    /// Maximum texts per batch request.
    public let maxBatchSize: Int

    /// URL session for making requests.
    private let session: URLSession

    /// Base URL for Gemini API.
    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    // MARK: - Initialization

    /// Creates a Gemini embedding provider.
    ///
    /// - Parameters:
    ///   - apiKey: Your Gemini API key.
    ///   - modelName: Name of the embedding model. Default is `text-embedding-004`.
    ///   - dimension: Embedding dimension for the model. Default is 768.
    ///   - maxBatchSize: Maximum texts per request. Default is 100.
    public init(
        apiKey: String,
        modelName: String = "text-embedding-004",
        dimension: Int = 768,
        maxBatchSize: Int = 100
    ) {
        id = "gemini"
        name = "Gemini Provider"
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
        let endpoint = "\(Self.baseURL)/models/\(modelName):batchEmbedContents?key=\(apiKey)"
        guard let url = URL(string: endpoint) else {
            throw ProviderError.invalidInput("Invalid Gemini API URL")
        }

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requests = texts.map { text in
            GeminiEmbedRequest(model: "models/\(modelName)", content: GeminiContent(parts: [GeminiPart(text: text)]))
        }
        let payload = GeminiBatchRequest(requests: requests)
        request.httpBody = try JSONCodec.makeEncoder().encode(payload)

        // Make request
        let (data, response) = try await session.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response type")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw ProviderError.networkError("Gemini API error: \(errorMessage)")
        }

        // Parse response
        let embeddingResponse = try JSONCodec.makeDecoder().decode(GeminiBatchResponse.self, from: data)
        return embeddingResponse.embeddings.map(\.values)
    }
}

// MARK: - Request/Response Types

private struct GeminiBatchRequest: Encodable {
    let requests: [GeminiEmbedRequest]
}

private struct GeminiEmbedRequest: Encodable {
    let model: String
    let content: GeminiContent
}

private struct GeminiContent: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Encodable {
    let text: String
}

private struct GeminiBatchResponse: Decodable {
    let embeddings: [GeminiEmbedding]
}

private struct GeminiEmbedding: Decodable {
    let values: [Float]
}
