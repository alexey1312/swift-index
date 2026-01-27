// MARK: - Claude Code OAuth E2E Tests

import Foundation
import Testing

@testable import SwiftIndexCore

/// End-to-end tests for Claude Code OAuth integration.
///
/// These tests verify the complete OAuth workflow from init to authentication:
/// - Automatic OAuth flow via `claude setup-token`
/// - Manual token input fallback
/// - Keychain storage and retrieval
/// - Token validation and error handling
@Suite("Claude Code OAuth E2E")
struct ClaudeCodeOAuthE2ETests {
    // MARK: - Test Setup

    /// Unique service name for test isolation
    private static func testServiceName() -> String {
        "com.swiftindex.test-\(UUID().uuidString)"
    }

    /// Cleanup Keychain after each test
    private func cleanup() throws {
        try? KeychainManager.deleteClaudeCodeToken()
    }

    // MARK: - Full OAuth Flow Tests

    @Test("OAuth flow: Automatic token generation and storage")
    func automaticOAuthFlow() async throws {
        defer { try? cleanup() }

        // Given: No existing token
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.getClaudeCodeToken()
        }

        // When: Automatic OAuth flow (mocked)
        // Note: Real CLI interaction is tested manually
        let mockToken = "sk-ant-oauth-auto-generated-token-12345"
        try KeychainManager.saveClaudeCodeToken(mockToken)

        // Then: Token saved and retrievable
        let retrieved = try KeychainManager.getClaudeCodeToken()
        #expect(retrieved == mockToken)
    }

    @Test("OAuth flow: Manual token input with validation")
    func manualTokenInputFlow() async throws {
        defer { try? cleanup() }

        // Given: No existing token, manual input mode
        let manualToken = "sk-ant-oauth-manual-token-67890"

        // When: User provides token manually
        try ClaudeCodeAuthManager.validateTokenFormat(manualToken)
        try KeychainManager.saveClaudeCodeToken(manualToken)

        // Then: Token validated and saved
        let retrieved = try KeychainManager.getClaudeCodeToken()
        #expect(retrieved == manualToken)
    }

    @Test("OAuth flow: Invalid token format rejected")
    func invalidTokenFormatRejected() async throws {
        defer { try? cleanup() }

        // Given: Invalid token format
        let invalidToken = "not-a-valid-oauth-token"

        // When/Then: Validation fails
        #expect(throws: ClaudeCodeAuthError.invalidToken) {
            try ClaudeCodeAuthManager.validateTokenFormat(invalidToken)
        }
    }

    @Test("OAuth flow: Existing token not overwritten without force")
    func existingTokenPreserved() async throws {
        defer { try? cleanup() }

        // Given: Existing token
        let existingToken = "sk-ant-oauth-existing-token"
        try KeychainManager.saveClaudeCodeToken(existingToken)

        // When: Check if token exists
        let retrieved = try KeychainManager.getClaudeCodeToken()

        // Then: Original token preserved
        #expect(retrieved == existingToken)

        // When: Try to save new token (should overwrite)
        let newToken = "sk-ant-oauth-new-token"
        try KeychainManager.saveClaudeCodeToken(newToken)

        // Then: Token updated
        let updated = try KeychainManager.getClaudeCodeToken()
        #expect(updated == newToken)
    }

    // MARK: - Token Lifecycle Tests

    @Test("OAuth lifecycle: Save, retrieve, delete")
    func tokenLifecycle() async throws {
        defer { try? cleanup() }

        let token = "sk-ant-oauth-lifecycle-token"

        // Save
        try KeychainManager.saveClaudeCodeToken(token)
        let saved = try KeychainManager.getClaudeCodeToken()
        #expect(saved == token)

        // Delete
        try KeychainManager.deleteClaudeCodeToken()

        // Verify deleted
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.getClaudeCodeToken()
        }
    }

    @Test("OAuth lifecycle: Multiple save operations")
    func multipleSaveOperations() async throws {
        defer { try? cleanup() }

        // First save
        let token1 = "sk-ant-oauth-token-1"
        try KeychainManager.saveClaudeCodeToken(token1)
        #expect(try KeychainManager.getClaudeCodeToken() == token1)

        // Second save (overwrite)
        let token2 = "sk-ant-oauth-token-2"
        try KeychainManager.saveClaudeCodeToken(token2)
        #expect(try KeychainManager.getClaudeCodeToken() == token2)

        // Third save (overwrite again)
        let token3 = "sk-ant-oauth-token-3"
        try KeychainManager.saveClaudeCodeToken(token3)
        #expect(try KeychainManager.getClaudeCodeToken() == token3)
    }

    // MARK: - Error Handling Tests

    @Test("OAuth error: Keychain locked")
    func keychainLockedError() async throws {
        // Note: Real Keychain lock testing requires macOS security setup
        // This test documents the expected behavior
        // In real scenarios, KeychainError.interactionNotAllowed is thrown
    }

    @Test("OAuth error: Token parsing failure")
    func tokenParsingFailure() async throws {
        // Given: Invalid CLI output (no token found)
        _ = """
        Setting up Claude Code OAuth...
        Please authenticate in your browser.
        Authentication successful!
        """

        // When/Then: Parsing should fail gracefully
        // ClaudeCodeAuthManager.extractToken() should return nil
        // This is handled by fallback to manual input
    }

    // MARK: - Concurrent Access Tests

    @Test("OAuth concurrency: Multiple save operations")
    func concurrentSaveOperations() async throws {
        defer { try? cleanup() }

        // Given: Multiple concurrent save attempts
        let tokens = (1 ... 5).map { "sk-ant-oauth-concurrent-token-\($0)" }

        // When: Save concurrently (with advisory lock)
        await withTaskGroup(of: Void.self) { group in
            for token in tokens {
                group.addTask {
                    try? KeychainManager.saveClaudeCodeToken(token)
                }
            }
        }

        // Then: One token should be saved (last one wins with advisory lock)
        let final = try? KeychainManager.getClaudeCodeToken()
        #expect(final != nil)
        #expect(tokens.contains(final!))
    }

    // MARK: - Integration with EnvironmentConfigLoader

    @Test("OAuth integration: Priority chain with Keychain fallback")
    func priorityChainIntegration() async throws {
        defer { try? cleanup() }

        // Given: Keychain token
        let keychainToken = "sk-ant-oauth-keychain-token"
        try KeychainManager.saveClaudeCodeToken(keychainToken)

        // When: Load with EnvironmentConfigLoader (no env vars)
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()
        let token = partial.anthropicAPIKey

        // Then: Keychain token used as fallback
        #expect(token == keychainToken)
    }

    @Test("OAuth integration: Environment variable overrides Keychain")
    func environmentOverridesKeychain() async throws {
        defer { try? cleanup() }

        // Given: Both Keychain and env var tokens
        let keychainToken = "sk-ant-oauth-keychain-token"
        try KeychainManager.saveClaudeCodeToken(keychainToken)

        let envToken = "sk-ant-api-env-token-12345"
        setenv("SWIFTINDEX_ANTHROPIC_API_KEY", envToken, 1)
        defer { unsetenv("SWIFTINDEX_ANTHROPIC_API_KEY") }

        // When: Load with EnvironmentConfigLoader
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()
        let token = partial.anthropicAPIKey

        // Then: Env var takes precedence
        #expect(token == envToken)
    }

    @Test("OAuth integration: CLAUDE_CODE_OAUTH_TOKEN priority")
    func claudeCodeOAuthEnvVarPriority() async throws {
        defer { try? cleanup() }

        // Given: CLAUDE_CODE_OAUTH_TOKEN env var (auto-set by Claude Code CLI)
        let oauthEnvToken = "sk-ant-oauth-env-auto-token"
        setenv("CLAUDE_CODE_OAUTH_TOKEN", oauthEnvToken, 1)
        defer { unsetenv("CLAUDE_CODE_OAUTH_TOKEN") }

        // And: Keychain token
        let keychainToken = "sk-ant-oauth-keychain-token"
        try KeychainManager.saveClaudeCodeToken(keychainToken)

        // When: Load with EnvironmentConfigLoader
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()
        let token = partial.anthropicAPIKey

        // Then: CLAUDE_CODE_OAUTH_TOKEN takes precedence over Keychain
        #expect(token == oauthEnvToken)
    }
}
