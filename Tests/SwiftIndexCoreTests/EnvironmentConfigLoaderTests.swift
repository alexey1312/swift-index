// MARK: - EnvironmentConfigLoaderTests

import Foundation
@testable import SwiftIndexCore
import Testing

/// Tests for reading configuration out of environment variables.
///
/// Each test supplies its own variables rather than calling `setenv`. The previous
/// approach mutated the process environment, which is global: tests running in
/// parallel overwrote each other's variables, and results depended on whatever the
/// developer had exported in their shell — a real `ANTHROPIC_API_KEY` would make a
/// "no key set" assertion fail.
@Suite("EnvironmentConfigLoader Tests")
struct EnvironmentConfigLoaderTests {
    private func load(_ environment: [String: String]) throws -> PartialConfig {
        // Keychain lookup is a fallback when no Anthropic variable is present; it is
        // system state, so tests opt out of it explicitly.
        var variables = environment
        variables["SWIFTINDEX_SKIP_KEYCHAIN"] = "1"
        return try EnvironmentConfigLoader(environment: variables).load()
    }

    // MARK: - Embedding

    @Test("Loads embedding provider and model")
    func loadEmbeddingSettings() throws {
        let config = try load([
            "SWIFTINDEX_EMBEDDING_PROVIDER": "ollama",
            "SWIFTINDEX_EMBEDDING_MODEL": "nomic-embed-text",
        ])

        #expect(config.embeddingProvider == "ollama")
        #expect(config.embeddingModel == "nomic-embed-text")
    }

    // MARK: - Anthropic priority chain

    @Test("Loads SWIFTINDEX_ANTHROPIC_API_KEY from environment")
    func loadAnthropicKeyFromSwiftIndexVar() throws {
        let config = try load(["SWIFTINDEX_ANTHROPIC_API_KEY": "swiftindex-anthropic-key"])
        #expect(config.anthropicAPIKey == "swiftindex-anthropic-key")
    }

    @Test("Falls back to ANTHROPIC_API_KEY when SWIFTINDEX_ not set")
    func fallbackToAnthropicKey() throws {
        let config = try load(["ANTHROPIC_API_KEY": "fallback-anthropic-key"])
        #expect(config.anthropicAPIKey == "fallback-anthropic-key")
    }

    @Test("SWIFTINDEX_ANTHROPIC_API_KEY takes priority over ANTHROPIC_API_KEY")
    func swiftIndexKeyHasPriority() throws {
        let config = try load([
            "SWIFTINDEX_ANTHROPIC_API_KEY": "priority-key",
            "ANTHROPIC_API_KEY": "fallback-key",
        ])
        #expect(config.anthropicAPIKey == "priority-key")
    }

    @Test("CLAUDE_CODE_OAUTH_TOKEN sits between the two Anthropic keys")
    func oauthTokenPriority() throws {
        // Below the project-specific override...
        let overridden = try load([
            "SWIFTINDEX_ANTHROPIC_API_KEY": "override",
            "CLAUDE_CODE_OAUTH_TOKEN": "oauth",
        ])
        #expect(overridden.anthropicAPIKey == "override")

        // ...and above the plain API key.
        let preferred = try load([
            "CLAUDE_CODE_OAUTH_TOKEN": "oauth",
            "ANTHROPIC_API_KEY": "plain",
        ])
        #expect(preferred.anthropicAPIKey == "oauth")
    }

    @Test("Returns nil when no Anthropic key is set")
    func noAnthropicKey() throws {
        let config = try load([:])
        #expect(config.anthropicAPIKey == nil)
    }

    // MARK: - Provider keys and their fallbacks

    @Test("Loads SWIFTINDEX_OPENAI_API_KEY and falls back to OPENAI_API_KEY")
    func openAIKeyChain() throws {
        #expect(try load(["SWIFTINDEX_OPENAI_API_KEY": "primary"]).openAIAPIKey == "primary")
        #expect(try load(["OPENAI_API_KEY": "fallback"]).openAIAPIKey == "fallback")
        #expect(
            try load([
                "SWIFTINDEX_OPENAI_API_KEY": "primary",
                "OPENAI_API_KEY": "fallback",
            ]).openAIAPIKey == "primary"
        )
    }

    @Test("Loads SWIFTINDEX_VOYAGE_API_KEY and falls back to VOYAGE_API_KEY")
    func voyageKeyChain() throws {
        #expect(try load(["SWIFTINDEX_VOYAGE_API_KEY": "primary"]).voyageAPIKey == "primary")
        #expect(try load(["VOYAGE_API_KEY": "fallback"]).voyageAPIKey == "fallback")
        #expect(
            try load([
                "SWIFTINDEX_VOYAGE_API_KEY": "primary",
                "VOYAGE_API_KEY": "fallback",
            ]).voyageAPIKey == "primary"
        )
    }

    @Test("Loads SWIFTINDEX_GEMINI_API_KEY and falls back to GEMINI_API_KEY")
    func geminiKeyChain() throws {
        #expect(try load(["SWIFTINDEX_GEMINI_API_KEY": "primary"]).geminiAPIKey == "primary")
        #expect(try load(["GEMINI_API_KEY": "fallback"]).geminiAPIKey == "fallback")
        #expect(
            try load([
                "SWIFTINDEX_GEMINI_API_KEY": "primary",
                "GEMINI_API_KEY": "fallback",
            ]).geminiAPIKey == "primary"
        )
    }

    // MARK: - Logging

    @Test("Loads log level from environment")
    func loadLogLevel() throws {
        #expect(try load(["SWIFTINDEX_LOG_LEVEL": "debug"]).logLevel == "debug")
    }

    // MARK: - Empty environment

    @Test("Returns empty config when no environment variables set")
    func emptyEnvironment() throws {
        let config = try load([:])

        #expect(config.embeddingProvider == nil)
        #expect(config.embeddingModel == nil)
        #expect(config.openAIAPIKey == nil)
        #expect(config.voyageAPIKey == nil)
        #expect(config.geminiAPIKey == nil)
        #expect(config.anthropicAPIKey == nil)
        #expect(config.logLevel == nil)
    }

    @Test("An unrelated variable is ignored")
    func unrelatedVariablesIgnored() throws {
        let config = try load(["PATH": "/usr/bin", "HOME": "/Users/test"])
        #expect(config == .empty)
    }

    // MARK: - Process environment

    @Test("The default initializer reads the process environment")
    func defaultInitializerUsesProcessEnvironment() throws {
        // The injectable initializer must not change what production code sees.
        let loader = EnvironmentConfigLoader()
        _ = try loader.load()
    }
}
