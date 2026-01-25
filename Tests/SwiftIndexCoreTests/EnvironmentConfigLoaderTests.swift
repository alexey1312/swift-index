// MARK: - EnvironmentConfigLoaderTests

import Foundation
@testable import SwiftIndexCore
import Testing

@Suite("EnvironmentConfigLoader Tests")
struct EnvironmentConfigLoaderTests {
    // MARK: - Test Helpers

    /// Saves the current environment variables that we'll modify in tests.
    private struct SavedEnvironment: ~Copyable {
        private let keys: [String]
        private let savedValues: [String: String?]

        init(keys: [String]) {
            self.keys = keys
            var saved: [String: String?] = [:]
            for key in keys {
                saved[key] = ProcessInfo.processInfo.environment[key]
            }
            self.savedValues = saved
        }

        deinit {
            for key in keys {
                if let originalValue = savedValues[key] {
                    if let value = originalValue {
                        setenv(key, value, 1)
                    } else {
                        unsetenv(key)
                    }
                }
            }
        }
    }

    // MARK: - Anthropic API Key Tests

    @Test("Loads SWIFTINDEX_ANTHROPIC_API_KEY from environment")
    func loadAnthropicKeyFromSwiftIndexVar() throws {
        let savedEnv = SavedEnvironment(keys: [
            "SWIFTINDEX_ANTHROPIC_API_KEY",
            "ANTHROPIC_API_KEY",
        ])
        _ = savedEnv

        setenv("SWIFTINDEX_ANTHROPIC_API_KEY", "swiftindex-anthropic-key", 1)
        unsetenv("ANTHROPIC_API_KEY")

        let loader = EnvironmentConfigLoader()
        let config = try loader.load()

        #expect(config.anthropicAPIKey == "swiftindex-anthropic-key")
    }

    @Test("Falls back to ANTHROPIC_API_KEY when SWIFTINDEX_ not set")
    func fallbackToAnthropicKey() throws {
        let savedEnv = SavedEnvironment(keys: [
            "SWIFTINDEX_ANTHROPIC_API_KEY",
            "ANTHROPIC_API_KEY",
        ])
        _ = savedEnv

        unsetenv("SWIFTINDEX_ANTHROPIC_API_KEY")
        setenv("ANTHROPIC_API_KEY", "fallback-anthropic-key", 1)

        let loader = EnvironmentConfigLoader()
        let config = try loader.load()

        #expect(config.anthropicAPIKey == "fallback-anthropic-key")
    }

    @Test("SWIFTINDEX_ANTHROPIC_API_KEY takes priority over ANTHROPIC_API_KEY")
    func swiftIndexKeyHasPriority() throws {
        let savedEnv = SavedEnvironment(keys: [
            "SWIFTINDEX_ANTHROPIC_API_KEY",
            "ANTHROPIC_API_KEY",
        ])
        _ = savedEnv

        setenv("SWIFTINDEX_ANTHROPIC_API_KEY", "priority-key", 1)
        setenv("ANTHROPIC_API_KEY", "fallback-key", 1)

        let loader = EnvironmentConfigLoader()
        let config = try loader.load()

        #expect(config.anthropicAPIKey == "priority-key")
    }

    @Test("Returns nil when no Anthropic key is set")
    func noAnthropicKey() throws {
        let savedEnv = SavedEnvironment(keys: [
            "SWIFTINDEX_ANTHROPIC_API_KEY",
            "ANTHROPIC_API_KEY",
        ])
        _ = savedEnv

        unsetenv("SWIFTINDEX_ANTHROPIC_API_KEY")
        unsetenv("ANTHROPIC_API_KEY")

        let loader = EnvironmentConfigLoader()
        let config = try loader.load()

        #expect(config.anthropicAPIKey == nil)
    }

    // MARK: - Voyage API Key Tests

    @Test("SWIFTINDEX_VOYAGE_API_KEY takes priority over VOYAGE_API_KEY")
    func voyageKeyPriority() throws {
        let savedEnv = SavedEnvironment(keys: [
            "SWIFTINDEX_VOYAGE_API_KEY",
            "VOYAGE_API_KEY",
        ])
        _ = savedEnv

        setenv("SWIFTINDEX_VOYAGE_API_KEY", "priority-voyage-key", 1)
        setenv("VOYAGE_API_KEY", "fallback-voyage-key", 1)

        let loader = EnvironmentConfigLoader()
        let config = try loader.load()

        #expect(config.voyageAPIKey == "priority-voyage-key")
    }

    @Test("Falls back to VOYAGE_API_KEY when SWIFTINDEX_ not set")
    func voyageKeyFallback() throws {
        let savedEnv = SavedEnvironment(keys: [
            "SWIFTINDEX_VOYAGE_API_KEY",
            "VOYAGE_API_KEY",
        ])
        _ = savedEnv

        unsetenv("SWIFTINDEX_VOYAGE_API_KEY")
        setenv("VOYAGE_API_KEY", "fallback-voyage-key", 1)

        let loader = EnvironmentConfigLoader()
        let config = try loader.load()

        #expect(config.voyageAPIKey == "fallback-voyage-key")
    }

    // MARK: - OpenAI API Key Tests

    @Test("SWIFTINDEX_OPENAI_API_KEY takes priority over OPENAI_API_KEY")
    func openAIKeyPriority() throws {
        let savedEnv = SavedEnvironment(keys: [
            "SWIFTINDEX_OPENAI_API_KEY",
            "OPENAI_API_KEY",
        ])
        _ = savedEnv

        setenv("SWIFTINDEX_OPENAI_API_KEY", "priority-openai-key", 1)
        setenv("OPENAI_API_KEY", "fallback-openai-key", 1)

        let loader = EnvironmentConfigLoader()
        let config = try loader.load()

        #expect(config.openAIAPIKey == "priority-openai-key")
    }

    @Test("Falls back to OPENAI_API_KEY when SWIFTINDEX_ not set")
    func openAIKeyFallback() throws {
        let savedEnv = SavedEnvironment(keys: [
            "SWIFTINDEX_OPENAI_API_KEY",
            "OPENAI_API_KEY",
        ])
        _ = savedEnv

        unsetenv("SWIFTINDEX_OPENAI_API_KEY")
        setenv("OPENAI_API_KEY", "fallback-openai-key", 1)

        let loader = EnvironmentConfigLoader()
        let config = try loader.load()

        #expect(config.openAIAPIKey == "fallback-openai-key")
    }

    // MARK: - Gemini API Key Tests

    @Test("SWIFTINDEX_GEMINI_API_KEY takes priority over GEMINI_API_KEY")
    func geminiKeyPriority() throws {
        let savedEnv = SavedEnvironment(keys: [
            "SWIFTINDEX_GEMINI_API_KEY",
            "GEMINI_API_KEY",
        ])
        _ = savedEnv

        setenv("SWIFTINDEX_GEMINI_API_KEY", "priority-gemini-key", 1)
        setenv("GEMINI_API_KEY", "fallback-gemini-key", 1)

        let loader = EnvironmentConfigLoader()
        let config = try loader.load()

        #expect(config.geminiAPIKey == "priority-gemini-key")
    }

    @Test("Falls back to GEMINI_API_KEY when SWIFTINDEX_ not set")
    func geminiKeyFallback() throws {
        let savedEnv = SavedEnvironment(keys: [
            "SWIFTINDEX_GEMINI_API_KEY",
            "GEMINI_API_KEY",
        ])
        _ = savedEnv

        unsetenv("SWIFTINDEX_GEMINI_API_KEY")
        setenv("GEMINI_API_KEY", "fallback-gemini-key", 1)

        let loader = EnvironmentConfigLoader()
        let config = try loader.load()

        #expect(config.geminiAPIKey == "fallback-gemini-key")
    }

    // MARK: - Other Environment Variable Tests

    @Test("Loads embedding provider from environment")
    func loadEmbeddingProvider() throws {
        let savedEnv = SavedEnvironment(keys: ["SWIFTINDEX_EMBEDDING_PROVIDER"])
        _ = savedEnv

        setenv("SWIFTINDEX_EMBEDDING_PROVIDER", "voyage", 1)

        let loader = EnvironmentConfigLoader()
        let config = try loader.load()

        #expect(config.embeddingProvider == "voyage")
    }

    @Test("Loads embedding model from environment")
    func loadEmbeddingModel() throws {
        let savedEnv = SavedEnvironment(keys: ["SWIFTINDEX_EMBEDDING_MODEL"])
        _ = savedEnv

        setenv("SWIFTINDEX_EMBEDDING_MODEL", "all-MiniLM-L6-v2", 1)

        let loader = EnvironmentConfigLoader()
        let config = try loader.load()

        #expect(config.embeddingModel == "all-MiniLM-L6-v2")
    }

    @Test("Loads log level from environment")
    func loadLogLevel() throws {
        let savedEnv = SavedEnvironment(keys: ["SWIFTINDEX_LOG_LEVEL"])
        _ = savedEnv

        setenv("SWIFTINDEX_LOG_LEVEL", "debug", 1)

        let loader = EnvironmentConfigLoader()
        let config = try loader.load()

        #expect(config.logLevel == "debug")
    }

    @Test("Returns empty config when no environment variables set")
    func emptyEnvironment() throws {
        let savedEnv = SavedEnvironment(keys: [
            "SWIFTINDEX_EMBEDDING_PROVIDER",
            "SWIFTINDEX_EMBEDDING_MODEL",
            "SWIFTINDEX_VOYAGE_API_KEY",
            "VOYAGE_API_KEY",
            "SWIFTINDEX_OPENAI_API_KEY",
            "OPENAI_API_KEY",
            "SWIFTINDEX_GEMINI_API_KEY",
            "GEMINI_API_KEY",
            "SWIFTINDEX_ANTHROPIC_API_KEY",
            "ANTHROPIC_API_KEY",
            "SWIFTINDEX_LOG_LEVEL",
        ])
        _ = savedEnv

        // Unset all environment variables
        unsetenv("SWIFTINDEX_EMBEDDING_PROVIDER")
        unsetenv("SWIFTINDEX_EMBEDDING_MODEL")
        unsetenv("SWIFTINDEX_VOYAGE_API_KEY")
        unsetenv("VOYAGE_API_KEY")
        unsetenv("SWIFTINDEX_OPENAI_API_KEY")
        unsetenv("OPENAI_API_KEY")
        unsetenv("SWIFTINDEX_GEMINI_API_KEY")
        unsetenv("GEMINI_API_KEY")
        unsetenv("SWIFTINDEX_ANTHROPIC_API_KEY")
        unsetenv("ANTHROPIC_API_KEY")
        unsetenv("SWIFTINDEX_LOG_LEVEL")

        let loader = EnvironmentConfigLoader()
        let config = try loader.load()

        #expect(config.embeddingProvider == nil)
        #expect(config.embeddingModel == nil)
        #expect(config.voyageAPIKey == nil)
        #expect(config.openAIAPIKey == nil)
        #expect(config.geminiAPIKey == nil)
        #expect(config.anthropicAPIKey == nil)
        #expect(config.logLevel == nil)
    }
}
