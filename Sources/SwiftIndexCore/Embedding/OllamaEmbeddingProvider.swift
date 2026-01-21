// MARK: - OllamaEmbeddingProvider

import Foundation

/// An embedding provider that uses a local Ollama server.
///
/// Ollama provides a simple way to run LLMs and embedding models locally.
/// This provider connects to the Ollama API to generate embeddings.
///
/// ## Prerequisites
///
/// 1. Install Ollama: `brew install ollama`
/// 2. Start Ollama: `ollama serve`
/// 3. Pull an embedding model: `ollama pull nomic-embed-text`
///
/// ## Usage
///
/// ```swift
/// let provider = OllamaEmbeddingProvider()
/// if await provider.isAvailable() {
///     let embedding = try await provider.embed("Hello, world!")
/// }
/// ```
public struct OllamaEmbeddingProvider: EmbeddingProvider, Sendable {
    // MARK: - Properties

    public let id: String
    public let name: String
    public let dimension: Int

    /// The base URL of the Ollama server.
    public let baseURL: URL

    /// The model to use for embeddings.
    public let modelName: String

    /// URL session for making requests.
    private let session: URLSession

    // MARK: - Initialization

    /// Creates an Ollama embedding provider.
    ///
    /// - Parameters:
    ///   - baseURL: Base URL of the Ollama server. Default is `http://localhost:11434`.
    ///   - modelName: Name of the embedding model. Default is `nomic-embed-text`.
    ///   - dimension: Embedding dimension for the model. Default is 768.
    public init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        modelName: String = "nomic-embed-text",
        dimension: Int = 768
    ) {
        self.id = "ollama"
        self.name = "Ollama Embedding Provider"
        self.dimension = dimension
        self.baseURL = baseURL
        self.modelName = modelName

        // Configure session with reasonable timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - EmbeddingProvider

    public func isAvailable() async -> Bool {
        // Check if Ollama server is running by hitting the API endpoint
        let versionURL = baseURL.appendingPathComponent("api/version")

        do {
            var request = URLRequest(url: versionURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 5

            let (_, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
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

        var results: [[Float]] = []

        // Ollama API processes one text at a time
        for text in texts {
            let embedding = try await generateEmbedding(for: text)
            results.append(embedding)
        }

        return results
    }

    // MARK: - Private Methods

    private func generateEmbedding(for text: String) async throws -> [Float] {
        let embeddingsURL = baseURL.appendingPathComponent("api/embeddings")

        // Build request
        var request = URLRequest(url: embeddingsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = EmbeddingRequest(model: modelName, prompt: text)
        request.httpBody = try JSONEncoder().encode(payload)

        // Make request
        let (data, response) = try await session.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response type")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ProviderError.networkError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        // Parse response
        let embeddingResponse = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
        return embeddingResponse.embedding.map { Float($0) }
    }
}

// MARK: - Request/Response Types

private struct EmbeddingRequest: Encodable {
    let model: String
    let prompt: String
}

private struct EmbeddingResponse: Decodable {
    let embedding: [Double]
}
