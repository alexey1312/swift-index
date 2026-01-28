@testable import SwiftIndexCore
import XCTest

/// Tests for OAuth token priority chain in EnvironmentConfigLoader
///
/// Verifies authentication priority:
/// 1. SWIFTINDEX_ANTHROPIC_API_KEY (highest - project override)
/// 2. CLAUDE_CODE_OAUTH_TOKEN (Claude Code CLI auto-set)
/// 3. ANTHROPIC_API_KEY (standard API key)
/// 4. Keychain OAuth Token (lowest - managed fallback)
///
/// Note: Tests use SWIFTINDEX_SKIP_KEYCHAIN=1 to avoid interactive prompts
/// when testing env var priority (Keychain fallback is skipped).
final class EnvironmentConfigLoaderOAuthTests: XCTestCase {
    // MARK: - Setup/Teardown

    override func setUp() {
        super.setUp()
        // Skip Keychain fallback by default to avoid interactive prompts
        setenv("SWIFTINDEX_SKIP_KEYCHAIN", "1", 1)
    }

    override func tearDown() {
        // Clean up env vars
        unsetenv("SWIFTINDEX_SKIP_KEYCHAIN")
        unsetenv("SWIFTINDEX_ANTHROPIC_API_KEY")
        unsetenv("CLAUDE_CODE_OAUTH_TOKEN")
        unsetenv("ANTHROPIC_API_KEY")
        super.tearDown()
    }

    // MARK: - Priority Chain Tests

    func testAnthropicKey_SWIFTINDEX_HasHighestPriority() throws {
        // Given: Multiple sources set
        setenv("SWIFTINDEX_ANTHROPIC_API_KEY", "swiftindex-key", 1)
        setenv("CLAUDE_CODE_OAUTH_TOKEN", "oauth-token", 1)
        setenv("ANTHROPIC_API_KEY", "standard-key", 1)

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

        // When: loading config
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()

        // Then: CLAUDE_CODE_OAUTH_TOKEN should win
        XCTAssertEqual(partial.anthropicAPIKey, "oauth-token")
    }

    func testAnthropicKey_StandardKey_ThirdPriority() throws {
        // Given: Only standard ANTHROPIC_API_KEY set
        setenv("ANTHROPIC_API_KEY", "standard-key", 1)

        // When: loading config
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()

        // Then: ANTHROPIC_API_KEY should be used
        XCTAssertEqual(partial.anthropicAPIKey, "standard-key")
    }

    func testAnthropicKey_NoSourcesSet_ReturnsNil() throws {
        // Given: No env vars (SWIFTINDEX_SKIP_KEYCHAIN is set in setUp)

        // When: loading config
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()

        // Then: anthropicAPIKey should be nil
        XCTAssertNil(partial.anthropicAPIKey)
    }

    // MARK: - Keychain Integration Tests

    //
    // Note: Tests for Keychain fallback are REMOVED because they require
    // interactive Keychain access (password prompt) which cannot be automated.
    // The Keychain integration is tested manually and via KeychainManagerTests
    // which use a test-specific service name.

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
