// MARK: - MockEmbeddingProvider

import Foundation

/// Deterministic embedding provider for tests and local tooling.
public final class MockEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    public let id: String = "mock"
    public let name: String = "Mock Embeddings"
    public let dimension: Int

    public init(dimension: Int = 384) {
        self.dimension = dimension
    }

    public func isAvailable() async -> Bool {
        true
    }

    public func embed(_ text: String) async throws -> [Float] {
        guard !text.isEmpty else {
            throw ProviderError.invalidInput("Text cannot be empty")
        }

        var generator = SeededRNG(seed: UInt64(bitPattern: Int64(text.hashValue)))
        var embedding = (0 ..< dimension).map { _ in Float.random(in: -1 ... 1, using: &generator) }

        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            embedding = embedding.map { $0 / norm }
        }

        return embedding
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else {
            return []
        }

        var results: [[Float]] = []
        results.reserveCapacity(texts.count)

        for (index, text) in texts.enumerated() {
            guard !text.isEmpty else {
                throw ProviderError.invalidInput("Text at index \(index) cannot be empty")
            }
            try await results.append(embed(text))
        }

        return results
    }
}

/// Seeded random number generator for deterministic embeddings.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
