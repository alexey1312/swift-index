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

    @Test("A chain reports readiness without falling back to isAvailable")
    func chainIsReadyDoesNotLoadModels() async {
        // The protocol's default isReady() forwards to isAvailable(), which loads —
        // and therefore downloads — a model. Every readiness check goes through a
        // chain, so without an override on the chain itself the whole "never
        // download to answer a question" guarantee silently evaporates.
        let chain = EmbeddingProviderChain(
            providers: [NeverReadyProvider()],
            id: "test-chain",
            name: "Test Chain"
        )

        let ready = await chain.isReady()
        #expect(ready == false)
        let probed = await NeverReadyProvider.availabilityProbes.wasProbed
        #expect(probed == false, "isReady() must not fall through to isAvailable()")
    }

    @Test("auto never resolves to a provider/dimension mismatch")
    func autoIsSelfConsistent() async throws {
        let resolved = try await EmbeddingProviderFactory.resolve(config: config(provider: "auto"))

        // Whichever provider auto picks, the dimension it reports must be the one it
        // will actually produce. Previously auto reported MLX's 1024 while embedding
        // through a 384-dimensional fallback, failing on every vector insert.
        #expect(resolved.chain.dimension == resolved.dimension)
        #expect(["mlx", "swift-embeddings"].contains(resolved.providerID))
    }

    @Test("auto keeps the provider an existing index was built with")
    func autoPinsToIndexMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("factory-pin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let metadata = IndexMetadata(
            providerID: "swift-embeddings",
            modelID: SwiftEmbeddingsProvider.Model.bgeBase.huggingFaceId,
            dimension: 768,
            swiftindexVersion: "test"
        )
        try metadata.save(toIndexDirectory: directory.path)

        let resolved = try await EmbeddingProviderFactory.resolve(
            config: config(provider: "auto"),
            indexDirectory: directory.path
        )

        #expect(resolved.providerID == "swift-embeddings")
        #expect(resolved.dimension == 768)
    }

    @Test("auto prefers a cloud provider with a key and uses its own default model")
    func autoPrefersCloudWithKey() async throws {
        let openAI = try await EmbeddingProviderFactory.resolve(config: config(provider: "auto", openAIKey: "k"))
        #expect(openAI.providerID == "openai")
        #expect(openAI.dimension == 1536)

        let voyage = try await EmbeddingProviderFactory.resolve(config: config(provider: "auto", voyageKey: "k"))
        #expect(voyage.providerID == "voyage")
        #expect(voyage.modelID == "voyage-code-2")

        #expect(!EmbeddingProviderFactory.autoUsesLocalModel(config: config(provider: "auto", geminiKey: "k")))
        #expect(EmbeddingProviderFactory.autoUsesLocalModel(config: config(provider: "auto")))
    }

    @Test("An existing local index keeps its provider when a cloud key appears")
    func pinnedIndexBeatsCloudKey() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("factory-cloud-pin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try IndexMetadata(
            providerID: "swift-embeddings",
            modelID: SwiftEmbeddingsProvider.Model.miniLM.huggingFaceId,
            dimension: 384,
            swiftindexVersion: "test"
        ).save(toIndexDirectory: directory.path)

        let resolved = try await EmbeddingProviderFactory.resolve(
            config: config(provider: "auto", openAIKey: "k"),
            indexDirectory: directory.path
        )

        #expect(resolved.providerID == "swift-embeddings")
    }

    @Test("auto throws when the cloud provider that built the index has no key")
    func pinnedCloudProviderWithoutKeyThrows() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("factory-cloud-missing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try IndexMetadata(
            providerID: "openai",
            modelID: "text-embedding-3-small",
            dimension: 1536,
            swiftindexVersion: "test"
        ).save(toIndexDirectory: directory.path)

        do {
            _ = try await EmbeddingProviderFactory.resolve(
                config: config(provider: "auto", voyageKey: "k"),
                indexDirectory: directory.path
            )
            Issue.record("resolve did not throw")
        } catch let error as ProviderError {
            let message = error.localizedDescription
            #expect(message.contains("OPENAI_API_KEY"))
            #expect(message.contains("index --force"))
        }

        let rebuilt = try await EmbeddingProviderFactory.resolve(config: config(provider: "auto", voyageKey: "k"))
        #expect(rebuilt.providerID == "voyage")
    }

    // MARK: - Model mapping

    @Test("MLX replaces a short model name with its own default")
    func mlxIgnoresForeignShortModelName() throws {
        let resolved = try EmbeddingProviderFactory.make(provider: "mlx", config: config(provider: "mlx"))

        #expect(resolved.modelID == EmbeddingModelDefaults.mlxModel)
        #expect(resolved.dimension == EmbeddingModelDefaults.mlxDimension)
    }

    @Test("swift-embeddings honors the configured model")
    func swiftEmbeddingsHonorsConfiguredModel() throws {
        let resolved = try EmbeddingProviderFactory.make(
            provider: "swift",
            config: config(provider: "swift", model: "bge-base-en-v1.5")
        )

        #expect(resolved.dimension == 768)
        #expect(resolved.modelID == SwiftEmbeddingsProvider.Model.bgeBase.huggingFaceId)
    }
}

// MARK: - Test Doubles

/// Records whether the expensive availability path was ever taken.
private actor ProbeCounter {
    private(set) var wasProbed = false
    func markProbed() {
        wasProbed = true
    }
}

private struct NeverReadyProvider: EmbeddingProvider {
    static let availabilityProbes = ProbeCounter()

    let id = "never-ready"
    let name = "Never Ready"
    let dimension = 384

    func isAvailable() async -> Bool {
        await Self.availabilityProbes.markProbed()
        return true
    }

    func isReady() async -> Bool {
        false
    }

    func embed(_: String) async throws -> [Float] {
        [Float](repeating: 0, count: dimension)
    }
}
