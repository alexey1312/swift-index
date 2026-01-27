// MARK: - EnvironmentConfigLoader

import Foundation

/// Loads configuration from environment variables.
public struct EnvironmentConfigLoader: ConfigLoader {
    public init() {}

    public func load() throws -> PartialConfig {
        var partial = PartialConfig()

        if let provider = ProcessInfo.processInfo.environment["SWIFTINDEX_EMBEDDING_PROVIDER"] {
            partial.embeddingProvider = provider
        }

        if let model = ProcessInfo.processInfo.environment["SWIFTINDEX_EMBEDDING_MODEL"] {
            partial.embeddingModel = model
        }

        if let voyageKey = ProcessInfo.processInfo.environment["SWIFTINDEX_VOYAGE_API_KEY"] {
            partial.voyageAPIKey = voyageKey
        }

        if partial.voyageAPIKey == nil,
           let voyageKey = ProcessInfo.processInfo.environment["VOYAGE_API_KEY"]
        {
            partial.voyageAPIKey = voyageKey
        }

        if let openAIKey = ProcessInfo.processInfo.environment["SWIFTINDEX_OPENAI_API_KEY"] {
            partial.openAIAPIKey = openAIKey
        }

        if partial.openAIAPIKey == nil,
           let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        {
            partial.openAIAPIKey = openAIKey
        }

        if let geminiKey = ProcessInfo.processInfo.environment["SWIFTINDEX_GEMINI_API_KEY"] {
            partial.geminiAPIKey = geminiKey
        }

        if partial.geminiAPIKey == nil,
           let geminiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
        {
            partial.geminiAPIKey = geminiKey
        }

        // Anthropic API key / OAuth token priority chain:
        // 1. SWIFTINDEX_ANTHROPIC_API_KEY (project-specific override)
        // 2. CLAUDE_CODE_OAUTH_TOKEN (auto-set by Claude Code CLI)
        // 3. ANTHROPIC_API_KEY (standard API key)
        // 4. Keychain OAuth Token (managed via `swiftindex auth`)
        if let anthropicKey = ProcessInfo.processInfo.environment["SWIFTINDEX_ANTHROPIC_API_KEY"] {
            partial.anthropicAPIKey = anthropicKey
        } else if let oauthToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"] {
            partial.anthropicAPIKey = oauthToken
        } else if let anthropicKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
            partial.anthropicAPIKey = anthropicKey
        } else {
            // Fallback: Check Keychain for OAuth token (only if no env vars set)
            partial.anthropicAPIKey = try? ClaudeCodeAuthManager.getToken()
        }

        if let logLevel = ProcessInfo.processInfo.environment["SWIFTINDEX_LOG_LEVEL"] {
            partial.logLevel = logLevel
        }

        return partial
    }
}
