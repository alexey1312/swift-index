// MARK: - AnthropicProviderTests

import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("AnthropicLLMProvider Tests")
struct AnthropicLLMProviderTests {
    @Test("Provider has correct properties")
    func providerProperties() {
        let provider = AnthropicLLMProvider(apiKey: "test-key")

        #expect(provider.id == "anthropic")
        #expect(provider.name == "Anthropic API")
    }

    @Test("Default model is Haiku")
    func defaultModel() {
        let provider = AnthropicLLMProvider(apiKey: "test-key")

        #expect(provider.defaultModel == .haiku)
    }

    @Test("Custom model configuration")
    func customModel() {
        let provider = AnthropicLLMProvider(
            apiKey: "test-key",
            defaultModel: .sonnet
        )

        #expect(provider.defaultModel == .sonnet)
    }

    @Test("Availability check with key")
    func availabilityWithKey() async {
        let provider = AnthropicLLMProvider(apiKey: "key")
        let available = await provider.isAvailable()
        #expect(available)
    }

    @Test("Availability check without key")
    func availabilityWithoutKey() async {
        let provider = AnthropicLLMProvider(apiKey: "")
        let available = await provider.isAvailable()
        #expect(!available)
    }

    @Test("Complete throws on empty messages")
    func emptyMessages() async {
        let provider = AnthropicLLMProvider(apiKey: "test-key")
        await #expect(throws: LLMError.self) {
            _ = try await provider.complete(messages: [], model: nil, timeout: 30)
        }
    }

    @Test("Complete throws on missing API key")
    func missingApiKey() async {
        let provider = AnthropicLLMProvider(apiKey: "")
        await #expect(throws: LLMError.self) {
            _ = try await provider.complete(
                messages: [.user("Hello")],
                model: nil,
                timeout: 30
            )
        }
    }

    @Test("Model enum has correct raw values")
    func modelRawValues() {
        #expect(AnthropicLLMProvider.Model.sonnet.rawValue == "claude-sonnet-4-5-20250929")
        #expect(AnthropicLLMProvider.Model.haiku.rawValue == "claude-haiku-4-5-20251001")
        #expect(AnthropicLLMProvider.Model.opus.rawValue == "claude-opus-4-5-20251101")
    }
}

@Suite("LLMProviderFactory Anthropic")
struct LLMProviderFactoryAnthropicTests {
    @Test("Create Anthropic provider from tier config")
    func createFromTierConfig() throws {
        let config = LLMTierConfig(provider: "anthropic")
        let provider = try LLMProviderFactory.createProvider(
            from: config,
            anthropicKey: "test-key"
        )
        #expect(provider.id == "anthropic")
    }

    @Test("Create Anthropic provider by ID")
    func createById() {
        let provider = LLMProviderFactory.createProvider(
            id: .anthropic,
            anthropicKey: "test-key"
        )
        #expect(provider.id == "anthropic")
    }

    @Test("Anthropic provider uses environment key when not provided")
    func environmentKey() {
        // When no key is provided, it should try to read from environment
        let provider = LLMProviderFactory.createProvider(id: .anthropic)
        #expect(provider.id == "anthropic")
    }
}
