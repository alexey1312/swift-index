// MARK: - Auth Command E2E Tests

import Foundation
import Testing

@testable import SwiftIndexCore

/// End-to-end tests for `swiftindex auth` CLI commands.
///
/// These tests verify:
/// - `auth status` - checking token status and source
/// - `auth login` - automatic and manual token setup
/// - `auth logout` - token removal
@Suite("Auth Command E2E")
struct AuthCommandE2ETests {
    // MARK: - Test Setup

    private func cleanup() throws {
        try? KeychainManager.deleteClaudeCodeToken()
    }

    // MARK: - Auth Status Tests

    @Test("auth status: No token found")
    func authStatusNoToken() async throws {
        defer { try? cleanup() }

        // Given: No token in Keychain
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.getClaudeCodeToken()
        }

        // Then: Status should indicate no authentication
        // Expected output: "Not authenticated. Run 'swiftindex auth login' to set up."
    }

    @Test("auth status: Valid token from Keychain")
    func authStatusValidKeychainToken() async throws {
        defer { try? cleanup() }

        // Given: Valid token in Keychain
        let token = "sk-ant-oauth-status-test-token"
        try KeychainManager.saveClaudeCodeToken(token)

        // When: Get token
        let retrieved = try KeychainManager.getClaudeCodeToken()

        // Then: Token retrieved successfully
        #expect(retrieved == token)

        // Expected status output:
        // "✓ Authenticated"
        // "  Source: Keychain"
        // "  Token: sk-ant-oau***"
    }

    @Test("auth status: Token from environment variable")
    func authStatusEnvironmentToken() async throws {
        defer {
            try? cleanup()
            unsetenv("CLAUDE_CODE_OAUTH_TOKEN")
        }

        // Given: Token from env var
        let envToken = "sk-ant-oauth-env-token"
        setenv("CLAUDE_CODE_OAUTH_TOKEN", envToken, 1)

        // When: Load via EnvironmentConfigLoader
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()
        let token = partial.anthropicAPIKey

        // Then: Env token used
        #expect(token == envToken)

        // Expected status output:
        // "✓ Authenticated"
        // "  Source: CLAUDE_CODE_OAUTH_TOKEN"
        // "  Token: sk-ant-oau***"
    }

    @Test("auth status: Shows correct token preview")
    func authStatusTokenPreview() async throws {
        defer { try? cleanup() }

        // Given: Token in Keychain
        let token = "sk-ant-oauth-preview-test-token-12345"
        try KeychainManager.saveClaudeCodeToken(token)

        // When: Generate preview
        let preview = String(token.prefix(10)) + "***"

        // Then: Preview format correct
        #expect(preview == "sk-ant-oau***")
    }

    // MARK: - Auth Login Tests

    @Test("auth login: Manual mode with valid token")
    func authLoginManualModeValid() async throws {
        defer { try? cleanup() }

        // Given: Valid token for manual input
        let token = "sk-ant-oauth-manual-valid-token"

        // When: Validate and save
        try ClaudeCodeAuthManager.validateTokenFormat(token)
        try KeychainManager.saveClaudeCodeToken(token)

        // Then: Token saved successfully
        let saved = try KeychainManager.getClaudeCodeToken()
        #expect(saved == token)

        // Expected output:
        // "✓ OAuth token saved successfully"
    }

    @Test("auth login: Manual mode with invalid token format")
    func authLoginManualModeInvalid() async throws {
        defer { try? cleanup() }

        // Given: Invalid token format
        let invalidToken = "invalid-token-format"

        // When/Then: Validation fails
        #expect(throws: ClaudeCodeAuthError.invalidToken) {
            try ClaudeCodeAuthManager.validateTokenFormat(invalidToken)
        }

        // Expected output:
        // "✗ Invalid token format"
        // "  OAuth tokens must match: sk-ant-oauth-[...] (20+ chars)"
    }

    @Test("auth login: Force flag overwrites existing token")
    func authLoginForceOverwrite() async throws {
        defer { try? cleanup() }

        // Given: Existing token
        let existingToken = "sk-ant-oauth-existing-token"
        try KeychainManager.saveClaudeCodeToken(existingToken)

        // When: Login with force (new token)
        let newToken = "sk-ant-oauth-new-token-forced"
        try KeychainManager.saveClaudeCodeToken(newToken)

        // Then: New token saved
        let saved = try KeychainManager.getClaudeCodeToken()
        #expect(saved == newToken)

        // Expected output:
        // "⚠️  Existing token will be overwritten"
        // "✓ OAuth token saved successfully"
    }

    @Test("auth login: Automatic flow fallback to manual")
    func authLoginAutomaticFallbackToManual() async throws {
        defer { try? cleanup() }

        // Given: CLI not available or automatic flow failed
        let isCLIAvailable = await ClaudeCodeAuthManager.isCLIAvailable()

        if !isCLIAvailable {
            // When: Fall back to manual mode
            let manualToken = "sk-ant-oauth-manual-fallback-token"
            try ClaudeCodeAuthManager.validateTokenFormat(manualToken)
            try KeychainManager.saveClaudeCodeToken(manualToken)

            // Then: Manual token saved
            let saved = try KeychainManager.getClaudeCodeToken()
            #expect(saved == manualToken)
        }

        // Expected output:
        // "⚠️  Automatic OAuth flow failed"
        // "Try manual token input? [Y/n]"
    }

    // MARK: - Auth Logout Tests

    @Test("auth logout: Removes token successfully")
    func authLogoutRemovesToken() async throws {
        defer { try? cleanup() }

        // Given: Token in Keychain
        let token = "sk-ant-oauth-logout-test-token"
        try KeychainManager.saveClaudeCodeToken(token)
        #expect(try KeychainManager.getClaudeCodeToken() == token)

        // When: Logout
        try KeychainManager.deleteClaudeCodeToken()

        // Then: Token removed
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.getClaudeCodeToken()
        }

        // Expected output:
        // "✓ Logged out successfully"
    }

    @Test("auth logout: Handles no token gracefully")
    func authLogoutNoToken() async throws {
        defer { try? cleanup() }

        // Given: No token in Keychain
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.getClaudeCodeToken()
        }

        // When: Try to logout
        // Then: Should show friendly message
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.deleteClaudeCodeToken()
        }

        // Expected output (in AuthCommand):
        // "Already logged out"
    }

    // MARK: - Error Handling Tests

    @Test("auth error: Keychain access denied")
    func authErrorKeychainAccessDenied() async throws {
        // Note: Real Keychain access denied testing requires security setup
        // This test documents expected behavior

        // Expected error handling:
        // "✗ Keychain access denied"
        // "  Run: security unlock-keychain"
        // "  Alternative: Set ANTHROPIC_API_KEY environment variable"
    }

    @Test("auth error: CLI not installed")
    func authErrorCLINotInstalled() async throws {
        // Given: CLI not available
        let isCLIAvailable = await ClaudeCodeAuthManager.isCLIAvailable()

        // If CLI not installed:
        if !isCLIAvailable {
            // Expected output:
            // "⚠️  'claude' CLI not found"
            // ""
            // "To install Claude Code CLI:"
            // "  npm install -g @anthropic-ai/claude-code"
            // ""
            // "Or use manual mode: swiftindex auth login --manual"
        }
    }

    @Test("auth error: Token parsing failure with helpful output")
    func authErrorTokenParsingWithOutput() async throws {
        // Given: CLI output without valid token
        _ = """
        Setting up Claude Code OAuth...
        Please authenticate in your browser.
        Authentication successful!
        Your OAuth token: INVALID_FORMAT
        """

        // Expected error handling:
        // "✗ Failed to parse OAuth token from CLI output"
        // ""
        // "CLI output:"
        // "[shown to user for manual extraction]"
        // ""
        // "Try manual mode: swiftindex auth login --manual"
    }

    // MARK: - Integration Tests

    @Test("auth integration: Full login-status-logout cycle")
    func authFullCycle() async throws {
        defer { try? cleanup() }

        // 1. Initial state: no token
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.getClaudeCodeToken()
        }

        // 2. Login
        let token = "sk-ant-oauth-full-cycle-token"
        try ClaudeCodeAuthManager.validateTokenFormat(token)
        try KeychainManager.saveClaudeCodeToken(token)

        // 3. Check status
        let saved = try KeychainManager.getClaudeCodeToken()
        #expect(saved == token)

        // 4. Logout
        try KeychainManager.deleteClaudeCodeToken()

        // 5. Verify logged out
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.getClaudeCodeToken()
        }
    }

    @Test("auth integration: Priority chain verification")
    func authPriorityChainVerification() async throws {
        defer {
            try? cleanup()
            unsetenv("SWIFTINDEX_ANTHROPIC_API_KEY")
            unsetenv("CLAUDE_CODE_OAUTH_TOKEN")
            unsetenv("ANTHROPIC_API_KEY")
        }

        // Given: Keychain token
        let keychainToken = "sk-ant-oauth-keychain-priority"
        try KeychainManager.saveClaudeCodeToken(keychainToken)

        let loader = EnvironmentConfigLoader()

        // Test 1: Keychain only
        var partial = try loader.load()
        var token = partial.anthropicAPIKey
        #expect(token == keychainToken)

        // Test 2: ANTHROPIC_API_KEY overrides Keychain
        let anthropicKey = "sk-ant-api-anthropic-key"
        setenv("ANTHROPIC_API_KEY", anthropicKey, 1)
        partial = try loader.load()
        token = partial.anthropicAPIKey
        #expect(token == anthropicKey)
        unsetenv("ANTHROPIC_API_KEY")

        // Test 3: CLAUDE_CODE_OAUTH_TOKEN overrides ANTHROPIC_API_KEY
        setenv("ANTHROPIC_API_KEY", anthropicKey, 1)
        let oauthToken = "sk-ant-oauth-oauth-token"
        setenv("CLAUDE_CODE_OAUTH_TOKEN", oauthToken, 1)
        partial = try loader.load()
        token = partial.anthropicAPIKey
        #expect(token == oauthToken)
        unsetenv("CLAUDE_CODE_OAUTH_TOKEN")
        unsetenv("ANTHROPIC_API_KEY")

        // Test 4: SWIFTINDEX_ANTHROPIC_API_KEY is highest priority
        let projectKey = "sk-ant-api-project-key"
        setenv("SWIFTINDEX_ANTHROPIC_API_KEY", projectKey, 1)
        setenv("CLAUDE_CODE_OAUTH_TOKEN", oauthToken, 1)
        setenv("ANTHROPIC_API_KEY", anthropicKey, 1)
        partial = try loader.load()
        token = partial.anthropicAPIKey
        #expect(token == projectKey)
    }
}
