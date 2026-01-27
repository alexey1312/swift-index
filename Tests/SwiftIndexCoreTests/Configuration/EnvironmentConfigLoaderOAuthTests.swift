@testable import SwiftIndexCore
import XCTest

/// Tests for OAuth token priority chain in EnvironmentConfigLoader
///
/// Verifies authentication priority:
/// 1. SWIFTINDEX_ANTHROPIC_API_KEY (highest - project override)
/// 2. CLAUDE_CODE_OAUTH_TOKEN (Claude Code CLI auto-set)
/// 3. ANTHROPIC_API_KEY (standard API key)
/// 4. Keychain OAuth Token (lowest - managed fallback)
final class EnvironmentConfigLoaderOAuthTests: XCTestCase {
    // MARK: - Priority Chain Tests

    func testAnthropicKey_SWIFTINDEX_HasHighestPriority() throws {
        // Given: Multiple sources set
        setenv("SWIFTINDEX_ANTHROPIC_API_KEY", "swiftindex-key", 1)
        setenv("CLAUDE_CODE_OAUTH_TOKEN", "oauth-token", 1)
        setenv("ANTHROPIC_API_KEY", "standard-key", 1)

        defer {
            unsetenv("SWIFTINDEX_ANTHROPIC_API_KEY")
            unsetenv("CLAUDE_CODE_OAUTH_TOKEN")
            unsetenv("ANTHROPIC_API_KEY")
        }

        // When: loading config
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()

        // Then: SWIFTINDEX_ANTHROPIC_API_KEY should win
        XCTAssertEqual(partial.anthropicAPIKey, "swiftindex-key")
    }

    func testAnthropicKey_OAuthToken_SecondPriority() throws {
        // Given: OAuth token and standard key set (no SWIFTINDEX override)
        setenv("CLAUDE_CODE_OAUTH_TOKEN", "oauth-token", 1)
        setenv("ANTHROPIC_API_KEY", "standard-key", 1)

        defer {
            unsetenv("CLAUDE_CODE_OAUTH_TOKEN")
            unsetenv("ANTHROPIC_API_KEY")
        }

        // When: loading config
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()

        // Then: CLAUDE_CODE_OAUTH_TOKEN should win
        XCTAssertEqual(partial.anthropicAPIKey, "oauth-token")
    }

    func testAnthropicKey_StandardKey_ThirdPriority() throws {
        // Given: Only standard ANTHROPIC_API_KEY set
        setenv("ANTHROPIC_API_KEY", "standard-key", 1)

        defer {
            unsetenv("ANTHROPIC_API_KEY")
        }

        // When: loading config
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()

        // Then: ANTHROPIC_API_KEY should be used
        XCTAssertEqual(partial.anthropicAPIKey, "standard-key")
    }

    func testAnthropicKey_KeychainFallback() throws {
        // Given: No env vars, token in Keychain
        let testToken = "sk-ant-oauth-keychain-test-12345678901234567890"

        // Save test token to Keychain
        try KeychainManager.saveClaudeCodeToken(testToken)

        defer {
            try? KeychainManager.deleteClaudeCodeToken()
        }

        // Ensure no env vars set
        unsetenv("SWIFTINDEX_ANTHROPIC_API_KEY")
        unsetenv("CLAUDE_CODE_OAUTH_TOKEN")
        unsetenv("ANTHROPIC_API_KEY")

        // When: loading config
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()

        // Then: Keychain token should be used
        XCTAssertEqual(partial.anthropicAPIKey, testToken)
    }

    func testAnthropicKey_EnvVarOverridesKeychain() throws {
        // Given: Both env var and Keychain token
        let keychainToken = "sk-ant-oauth-keychain-12345678901234567890"
        let envToken = "env-override-key"

        try KeychainManager.saveClaudeCodeToken(keychainToken)
        setenv("ANTHROPIC_API_KEY", envToken, 1)

        defer {
            try? KeychainManager.deleteClaudeCodeToken()
            unsetenv("ANTHROPIC_API_KEY")
        }

        // When: loading config
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()

        // Then: env var should override Keychain
        XCTAssertEqual(partial.anthropicAPIKey, envToken)
    }

    func testAnthropicKey_NoSourcesSet_ReturnsNil() throws {
        // Given: No env vars or Keychain token
        unsetenv("SWIFTINDEX_ANTHROPIC_API_KEY")
        unsetenv("CLAUDE_CODE_OAUTH_TOKEN")
        unsetenv("ANTHROPIC_API_KEY")

        // Ensure no Keychain token
        try? KeychainManager.deleteClaudeCodeToken()

        // When: loading config
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()

        // Then: anthropicAPIKey should be nil
        XCTAssertNil(partial.anthropicAPIKey)
    }

    // MARK: - Other API Keys Tests (ensure no regression)

    func testVoyageAPIKey_Priority() throws {
        // Given: Both SWIFTINDEX and standard keys set
        setenv("SWIFTINDEX_VOYAGE_API_KEY", "swiftindex-voyage", 1)
        setenv("VOYAGE_API_KEY", "standard-voyage", 1)

        defer {
            unsetenv("SWIFTINDEX_VOYAGE_API_KEY")
            unsetenv("VOYAGE_API_KEY")
        }

        // When: loading config
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()

        // Then: SWIFTINDEX_ prefix should win
        XCTAssertEqual(partial.voyageAPIKey, "swiftindex-voyage")
    }

    func testOpenAIAPIKey_Priority() throws {
        // Given: Both SWIFTINDEX and standard keys set
        setenv("SWIFTINDEX_OPENAI_API_KEY", "swiftindex-openai", 1)
        setenv("OPENAI_API_KEY", "standard-openai", 1)

        defer {
            unsetenv("SWIFTINDEX_OPENAI_API_KEY")
            unsetenv("OPENAI_API_KEY")
        }

        // When: loading config
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()

        // Then: SWIFTINDEX_ prefix should win
        XCTAssertEqual(partial.openAIAPIKey, "swiftindex-openai")
    }
}
