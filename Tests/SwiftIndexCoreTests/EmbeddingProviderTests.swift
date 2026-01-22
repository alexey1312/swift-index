// MARK: - EmbeddingProviderTests

import Foundation
@testable import SwiftIndexCore
import Testing

// MARK: - Mock Provider

/// Mock embedding provider for testing.
final class MockEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    let id: String
    let name: String
    let dimension: Int

    private let available: Bool
    private let shouldFail: Bool
    private let failureError: ProviderError

    var embedCallCount: Int = 0
    var embedBatchCallCount: Int = 0

    init(
        id: String = "mock",
        name: String = "Mock Provider",
        dimension: Int = 384,
        available: Bool = true,
        shouldFail: Bool = false,
        failureError: ProviderError = .unknown("Mock failure")
    ) {
        self.id = id
        self.name = name
        self.dimension = dimension
        self.available = available
        self.shouldFail = shouldFail
        self.failureError = failureError
    }

    func isAvailable() async -> Bool {
        available
    }

    func embed(_ text: String) async throws -> [Float] {
        embedCallCount += 1

        if shouldFail {
            throw failureError
        }

        // Generate deterministic embedding based on text hash
        return generateEmbedding(for: text)
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        embedBatchCallCount += 1

        if shouldFail {
            throw failureError
        }

        return texts.map { generateEmbedding(for: $0) }
    }

    private func generateEmbedding(for text: String) -> [Float] {
        // Generate normalized vector from text hash
        var embedding = (0 ..< dimension).map { i in
            Float(sin(Double(text.hashValue &+ i)))
        }

        // L2 normalize
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            embedding = embedding.map { $0 / norm }
        }

        return embedding
    }
}

// MARK: - MLXEmbeddingProvider Tests

@Suite("MLXEmbeddingProvider Tests")
struct MLXEmbeddingProviderTests {
    @Test("Provider has correct properties")
    func providerProperties() {
        let provider = MLXEmbeddingProvider()

        #expect(provider.id == "mlx")
        #expect(provider.name == "MLX Embeddings")
        #expect(provider.dimension == 384) // Default is bge-small-en-v1.5-4bit (memory-safe)
    }

    @Test("Provider with custom configuration")
    func customConfiguration() {
        let provider = MLXEmbeddingProvider(
            huggingFaceId: "custom-model",
            dimension: 768,
            maxBatchSize: 16
        )

        #expect(provider.dimension == 768)
    }

    @Test("Empty text throws invalidInput error")
    func emptyTextThrows() async throws {
        let provider = MLXEmbeddingProvider()

        await #expect(throws: ProviderError.self) {
            _ = try await provider.embed("")
        }
    }

    @Test("Empty batch returns empty array")
    func emptyBatchReturnsEmpty() async throws {
        let provider = MLXEmbeddingProvider()

        let result = try await provider.embed([String]())
        #expect(result.isEmpty)
    }

    @Test("Batch with empty text throws invalidInput error")
    func batchWithEmptyTextThrows() async throws {
        let provider = MLXEmbeddingProvider()

        await #expect(throws: ProviderError.self) {
            _ = try await provider.embed(["hello", "", "world"])
        }
    }

    #if arch(arm64) && os(macOS)
        @Test("Availability check on Apple Silicon")
        func availabilityAppleSilicon() async {
            let provider = MLXEmbeddingProvider()

            // On Apple Silicon, availability depends on model being present
            // This test verifies the check doesn't crash
            _ = await provider.isAvailable()
        }
    #endif
}

// MARK: - SwiftEmbeddingsProvider Tests

@Suite("SwiftEmbeddingsProvider Tests")
struct SwiftEmbeddingsProviderTests {
    @Test("Provider has correct properties")
    func testProviderProperties() {
        let provider = SwiftEmbeddingsProvider()

        #expect(provider.id == "swift-embeddings")
        #expect(provider.name == "Swift Embeddings")
        #expect(provider.dimension == 384)
    }

    @Test("Model enum dimensions")
    func modelDimensions() {
        #expect(SwiftEmbeddingsProvider.Model.bgeSmall.dimension == 384)
        #expect(SwiftEmbeddingsProvider.Model.bgeBase.dimension == 768)
        #expect(SwiftEmbeddingsProvider.Model.miniLM.dimension == 384)
    }

    @Test("Model HuggingFace IDs")
    func modelHuggingFaceIds() {
        #expect(SwiftEmbeddingsProvider.Model.bgeSmall.huggingFaceId == "BAAI/bge-small-en-v1.5")
        #expect(SwiftEmbeddingsProvider.Model.bgeBase.huggingFaceId == "BAAI/bge-base-en-v1.5")
        #expect(SwiftEmbeddingsProvider.Model.miniLM.huggingFaceId == "sentence-transformers/all-MiniLM-L6-v2")
    }

    @Test("Provider with different models")
    func differentModels() {
        let smallProvider = SwiftEmbeddingsProvider(model: .bgeSmall)
        let baseProvider = SwiftEmbeddingsProvider(model: .bgeBase)

        #expect(smallProvider.dimension == 384)
        #expect(baseProvider.dimension == 768)
    }

    @Test("Custom model configuration")
    func customModelConfiguration() {
        let provider = SwiftEmbeddingsProvider(
            huggingFaceId: "custom-model",
            dimension: 512,
            maxBatchSize: 64
        )

        #expect(provider.dimension == 512)
    }

    @Test("Empty text throws invalidInput error")
    func testEmptyTextThrows() async throws {
        let provider = SwiftEmbeddingsProvider()

        await #expect(throws: ProviderError.self) {
            _ = try await provider.embed("")
        }
    }

    @Test("Empty batch returns empty array")
    func testEmptyBatchReturnsEmpty() async throws {
        let provider = SwiftEmbeddingsProvider()

        let result = try await provider.embed([String]())
        #expect(result.isEmpty)
    }

    @Test("All models are iterable")
    func allModelsCaseIterable() {
        let allModels = SwiftEmbeddingsProvider.Model.allCases
        #expect(allModels.count == 3)
    }
}

// MARK: - EmbeddingProviderChain Tests

@Suite("EmbeddingProviderChain Tests")
struct EmbeddingProviderChainTests {
    @Test("Chain has correct properties")
    func chainProperties() {
        let chain = EmbeddingProviderChain.default

        #expect(chain.id == "default-chain")
        #expect(chain.name == "Default Embedding Chain")
    }

    @Test("Default chain has two providers")
    func defaultChainProviderCount() {
        let chain = EmbeddingProviderChain.default

        #expect(chain.allProviders.count == 2)
    }

    @Test("Software-only chain has one provider")
    func softwareOnlyChainProviderCount() {
        let chain = EmbeddingProviderChain.softwareOnly

        #expect(chain.allProviders.count == 1)
    }

    @Test("Chain uses first available provider")
    func chainUsesFirstAvailable() async throws {
        let firstProvider = MockEmbeddingProvider(id: "first", available: true)
        let secondProvider = MockEmbeddingProvider(id: "second", available: true)

        let chain = EmbeddingProviderChain(
            providers: [firstProvider, secondProvider]
        )

        _ = try await chain.embed("test")

        #expect(firstProvider.embedCallCount == 1)
        #expect(secondProvider.embedCallCount == 0)
    }

    @Test("Chain falls back when first provider unavailable")
    func chainFallbackOnUnavailable() async throws {
        let firstProvider = MockEmbeddingProvider(id: "first", available: false)
        let secondProvider = MockEmbeddingProvider(id: "second", available: true)

        let chain = EmbeddingProviderChain(
            providers: [firstProvider, secondProvider]
        )

        _ = try await chain.embed("test")

        #expect(firstProvider.embedCallCount == 0)
        #expect(secondProvider.embedCallCount == 1)
    }

    @Test("Chain falls back when first provider fails")
    func chainFallbackOnFailure() async throws {
        let firstProvider = MockEmbeddingProvider(
            id: "first",
            available: true,
            shouldFail: true,
            failureError: .timeout
        )
        let secondProvider = MockEmbeddingProvider(id: "second", available: true)

        let chain = EmbeddingProviderChain(
            providers: [firstProvider, secondProvider]
        )

        _ = try await chain.embed("test")

        #expect(firstProvider.embedCallCount == 1)
        #expect(secondProvider.embedCallCount == 1)
    }

    @Test("Chain throws allProvidersFailed when all fail")
    func chainThrowsWhenAllFail() async throws {
        let firstProvider = MockEmbeddingProvider(
            id: "first",
            available: true,
            shouldFail: true
        )
        let secondProvider = MockEmbeddingProvider(
            id: "second",
            available: true,
            shouldFail: true
        )

        let chain = EmbeddingProviderChain(
            providers: [firstProvider, secondProvider]
        )

        await #expect(throws: ProviderError.self) {
            _ = try await chain.embed("test")
        }
    }

    @Test("Chain caches active provider")
    func chainCachesActiveProvider() async throws {
        let provider = MockEmbeddingProvider(id: "cached", available: true)

        let chain = EmbeddingProviderChain(providers: [provider])

        _ = try await chain.embed("first")
        _ = try await chain.embed("second")

        // Active provider should be cached
        let active = await chain.activeProvider()
        #expect(active?.id == "cached")
    }

    @Test("Reset active provider clears cache")
    func testResetActiveProvider() async throws {
        let provider = MockEmbeddingProvider(id: "cached", available: true)

        let chain = EmbeddingProviderChain(providers: [provider])

        _ = try await chain.embed("test")
        await chain.resetActiveProvider()

        let active = await chain.activeProvider()
        #expect(active == nil)
    }

    @Test("Check all providers returns availability map")
    func testCheckAllProviders() async {
        let available = MockEmbeddingProvider(id: "available", available: true)
        let unavailable = MockEmbeddingProvider(id: "unavailable", available: false)

        let chain = EmbeddingProviderChain(
            providers: [available, unavailable]
        )

        let status = await chain.checkAllProviders()

        #expect(status["available"] == true)
        #expect(status["unavailable"] == false)
    }

    @Test("First available provider returns correct provider")
    func testFirstAvailableProvider() async {
        let unavailable = MockEmbeddingProvider(id: "unavailable", available: false)
        let available = MockEmbeddingProvider(id: "available", available: true)

        let chain = EmbeddingProviderChain(
            providers: [unavailable, available]
        )

        let first = await chain.firstAvailableProvider()

        #expect(first?.id == "available")
    }

    @Test("Empty batch returns empty array")
    func testEmptyBatchReturnsEmpty() async throws {
        let provider = MockEmbeddingProvider()
        let chain = EmbeddingProviderChain(providers: [provider])

        let result = try await chain.embed([String]())

        #expect(result.isEmpty)
        #expect(provider.embedBatchCallCount == 0)
    }

    @Test("Batch embedding uses correct provider")
    func batchEmbedding() async throws {
        let provider = MockEmbeddingProvider()
        let chain = EmbeddingProviderChain(providers: [provider])

        let texts = ["hello", "world", "test"]
        let result = try await chain.embed(texts)

        #expect(result.count == 3)
        #expect(provider.embedBatchCallCount == 1)
    }

    @Test("Chain availability reflects providers")
    func chainAvailability() async {
        let unavailableChain = EmbeddingProviderChain(
            providers: [
                MockEmbeddingProvider(id: "a", available: false),
                MockEmbeddingProvider(id: "b", available: false),
            ]
        )

        let availableChain = EmbeddingProviderChain(
            providers: [
                MockEmbeddingProvider(id: "a", available: false),
                MockEmbeddingProvider(id: "b", available: true),
            ]
        )

        let unavailableResult = await unavailableChain.isAvailable()
        let availableResult = await availableChain.isAvailable()

        #expect(unavailableResult == false)
        #expect(availableResult == true)
    }

    @Test("Single provider chain")
    func singleProviderChain() {
        let provider = MockEmbeddingProvider(id: "single")
        let chain = EmbeddingProviderChain.single(provider)

        #expect(chain.id == "single-single")
        #expect(chain.allProviders.count == 1)
    }
}

// MARK: - Builder Tests

@Suite("EmbeddingProviderChain.Builder Tests")
struct EmbeddingProviderChainBuilderTests {
    @Test("Builder creates chain with providers")
    func builderCreatesChain() {
        let chain = EmbeddingProviderChain.Builder()
            .add(MockEmbeddingProvider(id: "first"))
            .add(MockEmbeddingProvider(id: "second"))
            .id("test-chain")
            .name("Test Chain")
            .build()

        #expect(chain.id == "test-chain")
        #expect(chain.name == "Test Chain")
        #expect(chain.allProviders.count == 2)
    }

    @Test("Builder adds Swift embeddings")
    func builderAddsSwiftEmbeddings() {
        let chain = EmbeddingProviderChain.Builder()
            .addSwiftEmbeddings(model: .bgeSmall)
            .build()

        #expect(chain.allProviders.count == 1)
        #expect(chain.allProviders.first?.id == "swift-embeddings")
    }

    #if arch(arm64) && os(macOS)
        @Test("Builder adds MLX on Apple Silicon")
        func builderAddsMLXOnAppleSilicon() {
            let chain = EmbeddingProviderChain.Builder()
                .addMLX()
                .build()

            #expect(chain.allProviders.count == 1)
            #expect(chain.allProviders.first?.id == "mlx")
        }
    #endif

    @Test("Build with closure syntax")
    func buildWithClosure() {
        let chain = EmbeddingProviderChain.build { builder in
            builder.add(MockEmbeddingProvider(id: "closure-test"))
            builder.id("closure-chain")
        }

        #expect(chain.id == "closure-chain")
        #expect(chain.allProviders.count == 1)
    }
}

// MARK: - ProviderError Tests

@Suite("ProviderError Tests")
struct ProviderErrorTests {
    @Test("allProvidersFailed error description")
    func allProvidersFailedDescription() {
        let errors: [String: ProviderError] = [
            "mlx": .notAvailable(reason: "No Apple Silicon"),
            "swift": .modelNotFound(name: "bge-small"),
        ]

        let error = ProviderError.allProvidersFailed(errors)

        let description = error.errorDescription
        #expect(description != nil)
        #expect(description!.contains("All providers failed"))
    }

    @Test("ProviderError is Equatable")
    func providerErrorEquatable() {
        let error1 = ProviderError.timeout
        let error2 = ProviderError.timeout
        let error3 = ProviderError.modelNotFound(name: "test")

        #expect(error1 == error2)
        #expect(error1 != error3)
    }

    @Test("ProviderError is Sendable")
    func providerErrorSendable() async {
        let error: ProviderError = .timeout

        await Task.detached {
            // Accessing error from another task verifies Sendable
            _ = error.errorDescription
        }.value
    }
}

// MARK: - EmbeddingProviderRegistry Tests

@Suite("EmbeddingProviderRegistry Tests")
struct EmbeddingProviderRegistryTests {
    @Test("Registry returns all providers")
    func registryReturnsAllProviders() async {
        let config = Config.default
        let registry = EmbeddingProviderRegistry(config: config)

        let providers = await registry.allProviders()

        // Should have MLX, SwiftEmbeddings, Ollama, Voyage, and OpenAI
        #expect(providers.count >= 5)

        let ids = providers.map(\.id)
        #expect(ids.contains("mlx"))
        #expect(ids.contains("swift-embeddings"))
        #expect(ids.contains("ollama"))
        #expect(ids.contains("voyage"))
        #expect(ids.contains("openai"))
    }

    @Test("Registry shows local providers first")
    func registryLocalProvidersFirst() async {
        let config = Config.default
        let registry = EmbeddingProviderRegistry(config: config)

        let providers = await registry.allProviders()

        // Local providers should come before cloud providers
        let localProviders = providers.filter { $0.providerType == .local }
        let cloudProviders = providers.filter { $0.providerType == .cloud }

        #expect(localProviders.count >= 2)
        #expect(cloudProviders.count >= 2)

        // Find indices
        if let firstCloud = providers.firstIndex(where: { $0.providerType == .cloud }),
           let lastLocal = providers.lastIndex(where: { $0.providerType == .local })
        {
            #expect(lastLocal < firstCloud)
        }
    }

    @Test("Registry reflects API key availability for Voyage")
    func registryVoyageAPIKey() async {
        // Without API key
        let configWithoutKey = Config.default
        let registryWithoutKey = EmbeddingProviderRegistry(config: configWithoutKey)
        let providersWithoutKey = await registryWithoutKey.allProviders()

        let voyageWithoutKey = providersWithoutKey.first { $0.id == "voyage" }
        #expect(voyageWithoutKey?.isAvailable == false)
        #expect(voyageWithoutKey?.notes.contains("API key required") == true)

        // With API key
        var configWithKey = Config.default
        configWithKey.voyageAPIKey = "test-api-key"
        let registryWithKey = EmbeddingProviderRegistry(config: configWithKey)
        let providersWithKey = await registryWithKey.allProviders()

        let voyageWithKey = providersWithKey.first { $0.id == "voyage" }
        #expect(voyageWithKey?.notes.contains("API key configured") == true)
    }

    @Test("Registry reflects API key availability for OpenAI")
    func registryOpenAIAPIKey() async {
        // Without API key
        let configWithoutKey = Config.default
        let registryWithoutKey = EmbeddingProviderRegistry(config: configWithoutKey)
        let providersWithoutKey = await registryWithoutKey.allProviders()

        let openAIWithoutKey = providersWithoutKey.first { $0.id == "openai" }
        #expect(openAIWithoutKey?.isAvailable == false)
        #expect(openAIWithoutKey?.notes.contains("API key required") == true)

        // With API key
        var configWithKey = Config.default
        configWithKey.openAIAPIKey = "sk-test-key"
        let registryWithKey = EmbeddingProviderRegistry(config: configWithKey)
        let providersWithKey = await registryWithKey.allProviders()

        let openAIWithKey = providersWithKey.first { $0.id == "openai" }
        #expect(openAIWithKey?.notes.contains("API key configured") == true)
    }

    @Test("ProviderInfo has correct properties")
    func providerInfoProperties() async {
        let config = Config.default
        let registry = EmbeddingProviderRegistry(config: config)

        let providers = await registry.allProviders()
        let mlx = providers.first { $0.id == "mlx" }

        #expect(mlx != nil)
        #expect(mlx?.name == "MLX Embeddings")
        #expect(mlx?.dimension == 768)
        #expect(mlx?.providerType == .local)
        #expect(mlx?.modelId != nil)
    }

    @Test("Registry provider lookup by ID")
    func registryProviderById() async {
        let config = Config.default
        let registry = EmbeddingProviderRegistry(config: config)

        // Lookup should return nil for cloud providers without API keys
        let voyage = await registry.provider(id: "voyage")
        #expect(voyage == nil) // No API key configured

        // Unknown provider should return nil
        let unknown = await registry.provider(id: "unknown-provider")
        #expect(unknown == nil)
    }
}

// MARK: - ProviderInfo Tests

@Suite("ProviderInfo Tests")
struct ProviderInfoTests {
    @Test("ProviderInfo is Sendable")
    func providerInfoSendable() async {
        let info = ProviderInfo(
            id: "test",
            name: "Test Provider",
            dimension: 384,
            isAvailable: true,
            notes: "Test notes",
            providerType: .local,
            modelId: "test-model"
        )

        await Task.detached {
            // Accessing info from another task verifies Sendable
            _ = info.id
            _ = info.name
        }.value
    }

    @Test("ProviderInfo is Equatable")
    func providerInfoEquatable() {
        let info1 = ProviderInfo(
            id: "test",
            name: "Test",
            dimension: 384,
            isAvailable: true,
            notes: "Notes",
            providerType: .local
        )

        let info2 = ProviderInfo(
            id: "test",
            name: "Test",
            dimension: 384,
            isAvailable: true,
            notes: "Notes",
            providerType: .local
        )

        let info3 = ProviderInfo(
            id: "different",
            name: "Test",
            dimension: 384,
            isAvailable: true,
            notes: "Notes",
            providerType: .local
        )

        #expect(info1 == info2)
        #expect(info1 != info3)
    }

    @Test("ProviderType raw values")
    func providerTypeRawValues() {
        #expect(ProviderInfo.ProviderType.local.rawValue == "local")
        #expect(ProviderInfo.ProviderType.cloud.rawValue == "cloud")
    }
}

// MARK: - Integration Tests

@Suite("Embedding Provider Integration Tests")
struct EmbeddingProviderIntegrationTests {
    @Test("Embedding vector is normalized")
    func embeddingNormalized() async throws {
        let provider = MockEmbeddingProvider()
        let embedding = try await provider.embed("test text")

        // Check L2 norm is approximately 1
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        #expect(abs(norm - 1.0) < 0.001)
    }

    @Test("Different texts produce different embeddings")
    func differentEmbeddings() async throws {
        let provider = MockEmbeddingProvider()

        // Use very different texts to ensure different embeddings
        let embedding1 = try await provider.embed("authentication login user credentials")
        let embedding2 = try await provider.embed("database query sql select")

        // Calculate cosine similarity
        let dotProduct = zip(embedding1, embedding2).reduce(0) { $0 + $1.0 * $1.1 }

        // Embeddings should be different (cosine similarity < 1)
        // Note: Mock provider may produce similar embeddings, so use lenient threshold
        #expect(dotProduct < 1.0)
    }

    @Test("Same text produces same embedding")
    func deterministicEmbeddings() async throws {
        let provider = MockEmbeddingProvider()

        let embedding1 = try await provider.embed("test text")
        let embedding2 = try await provider.embed("test text")

        #expect(embedding1 == embedding2)
    }

    @Test("Batch embedding produces correct count")
    func batchEmbeddingCount() async throws {
        let provider = MockEmbeddingProvider(dimension: 384)

        let texts = ["one", "two", "three", "four", "five"]
        let embeddings = try await provider.embed(texts)

        #expect(embeddings.count == 5)
        for embedding in embeddings {
            #expect(embedding.count == 384)
        }
    }

    @Test("Chain maintains dimension consistency")
    func chainDimensionConsistency() async throws {
        let provider1 = MockEmbeddingProvider(id: "p1", dimension: 384)
        let provider2 = MockEmbeddingProvider(id: "p2", dimension: 384)

        let chain = EmbeddingProviderChain(providers: [provider1, provider2])

        #expect(chain.dimension == 384)

        let embedding = try await chain.embed("test")
        #expect(embedding.count == 384)
    }
}
