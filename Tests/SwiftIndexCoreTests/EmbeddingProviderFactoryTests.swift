import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("EmbeddingProviderFactory Tests")
struct EmbeddingProviderFactoryTests {
    private func config(
        provider: String,
        model: String = "all-MiniLM-L6-v2",
        dimension: Int = 384,
        openAIKey: String? = nil,
        voyageKey: String? = nil,
        geminiKey: String? = nil
    ) -> Config {
        Config(
            embeddingProvider: provider,
            embeddingModel: model,
            embeddingDimension: dimension,
            voyageAPIKey: voyageKey,
            openAIAPIKey: openAIKey,
            geminiAPIKey: geminiKey
        )
    }

    // MARK: - Dimension correctness (regression for the zero-config blocker)

    @Test("Resolved dimension comes from the selected provider, not the chain head")
    func dimensionMatchesSelectedProvider() throws {
        let resolved = try EmbeddingProviderFactory.make(
            provider: "swift-embeddings",
            config: config(provider: "swift-embeddings")
        )

        #expect(resolved.providerID == "swift-embeddings")
        #expect(resolved.dimension == resolved.chain.dimension)
        // The whole defect: a chain reporting a dimension no provider will produce.
        #expect(resolved.dimension == 384)
    }

    @Test("Chains are pinned to a single provider so dimensions cannot drift")
    func chainIsPinnedToOneProvider() throws {
        for provider in ["mlx", "swift-embeddings", "ollama", "mock"] {
            let resolved = try EmbeddingProviderFactory.make(
                provider: provider,
                config: config(provider: provider)
            )
            // A fallback of a different dimension would silently corrupt the index.
            #expect(
                resolved.chain.dimension == resolved.dimension,
                "\(provider) chain dimension must match the resolved dimension"
            )
        }
    }

    // MARK: - Provider coverage

    @Test("Gemini is reachable and requires a key")
    func geminiReachable() throws {
        // Gemini existed as a provider class and in the init wizard, but four of the
        // five duplicated switches had no case for it, so it silently became MLX.
        let resolved = try EmbeddingProviderFactory.make(
            provider: "gemini",
            config: config(provider: "gemini", geminiKey: "test-key")
        )
        #expect(resolved.providerID == "gemini")

        #expect(throws: (any Error).self) {
            try EmbeddingProviderFactory.make(
                provider: "gemini",
                config: config(provider: "gemini")
            )
        }
    }

    @Test("API providers without a key throw rather than silently degrading")
    func missingAPIKeysThrow() throws {
        for provider in ["openai", "voyage", "gemini"] {
            #expect(throws: (any Error).self, "\(provider) should require a key") {
                try EmbeddingProviderFactory.make(
                    provider: provider,
                    config: config(provider: provider)
                )
            }
        }
    }

    @Test("Provider names are case-insensitive")
    func caseInsensitive() throws {
        for spelling in ["MLX", "mlx", "Mlx"] {
            let resolved = try EmbeddingProviderFactory.make(
                provider: spelling,
                config: config(provider: spelling)
            )
            #expect(resolved.providerID == "mlx")
        }
    }

    @Test("Unknown provider throws instead of silently substituting a default")
    func unknownProviderThrows() throws {
        // A typo used to produce an index built with a different provider entirely.
        #expect(throws: (any Error).self) {
            try EmbeddingProviderFactory.make(
                provider: "gemeni",
                config: config(provider: "gemeni")
            )
        }
    }

    @Test("Aliases resolve to swift-embeddings")
    func swiftEmbeddingsAliases() throws {
        for alias in ["swift", "swiftembeddings", "swift-embeddings"] {
            let resolved = try EmbeddingProviderFactory.make(
                provider: alias,
                config: config(provider: alias)
            )
            #expect(resolved.providerID == "swift-embeddings")
        }
    }

    // MARK: - auto

    @Test("auto never resolves to a provider/dimension mismatch")
    func autoIsSelfConsistent() async throws {
        let resolved = try await EmbeddingProviderFactory.resolve(config: config(provider: "auto"))

        // Whichever provider auto picks, the dimension it reports must be the one it
        // will actually produce. Previously auto reported MLX's 1024 while embedding
        // through a 384-dimensional fallback, failing on every vector insert.
        #expect(resolved.chain.dimension == resolved.dimension)
        #expect(["mlx", "swift-embeddings"].contains(resolved.providerID))
    }
}
