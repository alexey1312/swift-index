// MARK: - GeminiProviderTests

import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("GeminiEmbeddingProvider Tests")
struct GeminiEmbeddingProviderTests {
    @Test("Provider has correct properties")
    func providerProperties() {
        let provider = GeminiEmbeddingProvider(apiKey: "test-key")

        #expect(provider.id == "gemini")
        #expect(provider.name == "Gemini Provider")
        #expect(provider.dimension == 768) // Default text-embedding-004
    }

    @Test("Custom configuration")
    func customConfiguration() {
        let provider = GeminiEmbeddingProvider(
            apiKey: "test-key",
            modelName: "custom-model",
            dimension: 1024,
            maxBatchSize: 50
        )

        #expect(provider.dimension == 1024)
        #expect(provider.modelName == "custom-model")
        #expect(provider.maxBatchSize == 50)
    }

    @Test("Availability check")
    func availability() async {
        let providerWithKey = GeminiEmbeddingProvider(apiKey: "key")
        let providerWithoutKey = GeminiEmbeddingProvider(apiKey: "")

        let available = await providerWithKey.isAvailable()
        let unavailable = await providerWithoutKey.isAvailable()

        #expect(available)
        #expect(!unavailable)
    }
}

@Suite("GeminiLLMProvider Tests")
struct GeminiLLMProviderTests {
    @Test("Provider has correct properties")
    func providerProperties() {
        let provider = GeminiLLMProvider(apiKey: "test-key")

        #expect(provider.id == "gemini")
        #expect(provider.name == "Gemini API")
    }

    @Test("Availability check")
    func availability() async {
        let providerWithKey = GeminiLLMProvider(apiKey: "key")
        let providerWithoutKey = GeminiLLMProvider(apiKey: "")

        let available = await providerWithKey.isAvailable()
        let unavailable = await providerWithoutKey.isAvailable()

        #expect(available)
        #expect(!unavailable)
    }
}

@Suite("GeminiCLIProvider Tests")
struct GeminiCLIProviderTests {
    @Test("Provider has correct properties")
    func providerProperties() {
        let provider = GeminiCLIProvider()

        #expect(provider.id == "gemini-cli")
        #expect(provider.name == "Gemini CLI")
    }

    @Test("Custom executable path")
    func customExecutable() {
        let provider = GeminiCLIProvider(executablePath: "/custom/path/gemini")
        // Not exposing executablePath property, but initialization should pass
        #expect(provider.id == "gemini-cli")
    }
}
