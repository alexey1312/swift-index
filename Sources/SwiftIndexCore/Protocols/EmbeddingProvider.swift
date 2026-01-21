// MARK: - EmbeddingProvider Protocol

import Foundation

/// A provider that generates vector embeddings from text.
///
/// Embedding providers convert text into dense vector representations
/// suitable for semantic similarity search. The protocol supports both
/// single text and batch embedding operations.
public protocol EmbeddingProvider: Sendable {
    /// Unique identifier for this provider.
    var id: String { get }

    /// Human-readable name of the provider.
    var name: String { get }

    /// The dimension of vectors produced by this provider.
    var dimension: Int { get }

    /// Whether this provider is currently available.
    ///
    /// Availability may depend on:
    /// - Hardware (e.g., Apple Silicon for MLX)
    /// - Network connectivity (for cloud providers)
    /// - API keys (for commercial providers)
    /// - Model availability
    func isAvailable() async -> Bool

    /// Generate an embedding vector for a single text.
    ///
    /// - Parameter text: The text to embed.
    /// - Returns: A vector of floating-point values.
    /// - Throws: `ProviderError` if embedding fails.
    func embed(_ text: String) async throws -> [Float]

    /// Generate embedding vectors for multiple texts.
    ///
    /// Default implementation calls `embed(_:)` for each text.
    /// Providers may override for batch optimization.
    ///
    /// - Parameter texts: Array of texts to embed.
    /// - Returns: Array of embedding vectors.
    /// - Throws: `ProviderError` if embedding fails.
    func embed(_ texts: [String]) async throws -> [[Float]]
}

// MARK: - Default Implementation

extension EmbeddingProvider {
    public func embed(_ texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)

        for text in texts {
            let vector = try await embed(text)
            results.append(vector)
        }

        return results
    }
}
