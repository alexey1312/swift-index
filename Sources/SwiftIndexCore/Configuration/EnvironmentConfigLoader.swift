// MARK: - EnvironmentConfigLoader

import Foundation
import Logging

/// Loads configuration from environment variables.
///
/// The environment is injected rather than read from the process on every lookup, so
/// callers — tests especially — can supply an exact set of variables. Reading the
/// process directly made behaviour depend on whatever the developer happened to have
/// exported, and forced tests to mutate global state with `setenv`, which races when
/// they run in parallel.
public struct EnvironmentConfigLoader: ConfigLoader {
    private let logger = Logger(label: "com.swiftindex.config.environment")

    /// The variables this loader reads.
    private let environment: [String: String]

    /// Creates a loader over the current process environment.
    public init() {
        self.init(environment: ProcessInfo.processInfo.environment)
    }

    /// Creates a loader over an explicit set of variables.
    ///
    /// - Parameter environment: Variables to read instead of the process environment.
    public init(environment: [String: String]) {
        self.environment = environment
    }

    public func load() throws -> PartialConfig {
        var partial = PartialConfig()

        if let provider = environment["SWIFTINDEX_EMBEDDING_PROVIDER"] {
            partial.embeddingProvider = provider
        }

        if let model = environment["SWIFTINDEX_EMBEDDING_MODEL"] {
            partial.embeddingModel = model
        }

        if let voyageKey = environment["SWIFTINDEX_VOYAGE_API_KEY"] {
            partial.voyageAPIKey = voyageKey
        }

        if partial.voyageAPIKey == nil,
           let voyageKey = environment["VOYAGE_API_KEY"]
        {
            partial.voyageAPIKey = voyageKey
        }

        if let openAIKey = environment["SWIFTINDEX_OPENAI_API_KEY"] {
            partial.openAIAPIKey = openAIKey
        }

        if partial.openAIAPIKey == nil,
           let openAIKey = environment["OPENAI_API_KEY"]
        {
            partial.openAIAPIKey = openAIKey
        }

        if let geminiKey = environment["SWIFTINDEX_GEMINI_API_KEY"] {
            partial.geminiAPIKey = geminiKey
        }

        if partial.geminiAPIKey == nil,
           let geminiKey = environment["GEMINI_API_KEY"]
        {
            partial.geminiAPIKey = geminiKey
        }

        // Anthropic API key / OAuth token priority chain:
        // 1. SWIFTINDEX_ANTHROPIC_API_KEY (project-specific override)
        // 2. CLAUDE_CODE_OAUTH_TOKEN (auto-set by Claude Code CLI)
        // 3. ANTHROPIC_API_KEY (standard API key)
        // 4. Keychain OAuth Token (managed via `swiftindex auth`)
        if let anthropicKey = environment["SWIFTINDEX_ANTHROPIC_API_KEY"] {
            partial.anthropicAPIKey = anthropicKey
        } else if let oauthToken = environment["CLAUDE_CODE_OAUTH_TOKEN"] {
            partial.anthropicAPIKey = oauthToken
        } else if let anthropicKey = environment["ANTHROPIC_API_KEY"] {
            partial.anthropicAPIKey = anthropicKey
        } else if environment["SWIFTINDEX_SKIP_KEYCHAIN"] == nil {
            // Fallback: Check Keychain for OAuth token (only if no env vars set)
            // Set SWIFTINDEX_SKIP_KEYCHAIN=1 to disable Keychain access (for testing)
            do {
                partial.anthropicAPIKey = try ClaudeCodeAuthManager.getToken()
            } catch KeychainError.notFound {
                // Expected case - no token stored yet, not an error
                // Don't log anything
            } catch KeychainError.keychainLocked {
                // Log as ERROR since this blocks auth but user can fix it
                logger.error(
                    "Failed to retrieve OAuth token from Keychain: Keychain is locked",
                    metadata: [
                        "error_id": .string("keychain_locked"),
                        "suggestion": .string(
                            "Unlock Keychain with: security unlock-keychain ~/Library/Keychains/login.keychain-db"
                        ),
                    ]
                )
            } catch {
                // Log any other Keychain errors with full context
                logger.error(
                    "Failed to retrieve OAuth token from Keychain",
                    metadata: [
                        "error": .string(error.localizedDescription),
                        "error_id": .string("keychain_read_failed"),
                    ]
                )
            }
        }

        if let logLevel = environment["SWIFTINDEX_LOG_LEVEL"] {
            partial.logLevel = logLevel
        }

        return partial
    }
}
