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

    /// Whether this provider can be used *right now* without any network I/O.
    ///
    /// `isAvailable()` is allowed to load — and therefore download — a model as a
    /// side effect of answering. That makes it unusable for diagnostics: asking
    /// "which providers work?" must not cost a multi-hundred-megabyte download.
    /// `isReady()` answers the cheaper question: is the hardware/OS supported and
    /// is the model already on disk?
    ///
    /// Defaults to `isAvailable()` for providers with no local model to cache
    /// (API-backed providers, mocks).
    func isReady() async -> Bool

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

public extension EmbeddingProvider {
    /// Providers without a locally cached model are ready whenever they are available.
    func isReady() async -> Bool {
        await isAvailable()
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)

        for text in texts {
            let vector = try await embed(text)
            results.append(vector)
        }

        return results
    }
}
