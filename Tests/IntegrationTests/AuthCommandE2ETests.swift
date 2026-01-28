// MARK: - Auth Command E2E Tests

import Foundation
import Testing

@testable import SwiftIndexCore

/// End-to-end tests for `swiftindex auth` CLI commands.
///
/// Uses test-specific Keychain service/account to avoid interactive prompts.
@Suite("Auth Command E2E")
struct AuthCommandE2ETests {
    // Test-specific service/account to avoid Keychain prompts
    private let testService = "com.swiftindex.oauth.auth-e2e-test"
    private let testAccount = "claude-code-oauth-auth-e2e-test"

    // MARK: - Test Cleanup

    private func cleanup() {
        try? KeychainManager.deleteToken(service: testService, account: testAccount)
    }

    // MARK: - Auth Status Tests

    @Test("auth status: No token found")
    func authStatusNoToken() async throws {
        defer { cleanup() }

        // Given: No token in Keychain
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.getToken(service: testService, account: testAccount)
        }
    }

    @Test("auth status: Valid token from Keychain")
    func authStatusValidKeychainToken() async throws {
        defer { cleanup() }

        // Given: Valid token in Keychain
        let token = "sk-ant-oauth-status-test-token-123456789"
        try KeychainManager.saveToken(token, service: testService, account: testAccount)

        // When: Get token
        let retrieved = try KeychainManager.getToken(service: testService, account: testAccount)

        // Then: Token retrieved successfully
        #expect(retrieved == token)
    }

    @Test("auth status: Shows correct token preview")
    func authStatusTokenPreview() async throws {
        defer { cleanup() }

        // Given: Token in Keychain
        let token = "sk-ant-oauth-preview-test-token-12345"
        try KeychainManager.saveToken(token, service: testService, account: testAccount)

        // When: Generate preview
        let preview = String(token.prefix(10)) + "***"

        // Then: Preview format correct
        #expect(preview == "sk-ant-oau***")
    }

    // MARK: - Auth Login Tests

    @Test("auth login: Manual mode with valid legacy token")
    func authLoginManualModeLegacyToken() async throws {
        defer { cleanup() }

        // Given: Valid legacy format token
        let token = "sk-ant-oauth-manual-valid-token-123456789"

        // When: Validate and save
        try ClaudeCodeAuthManager.validateTokenFormat(token)
        try KeychainManager.saveToken(token, service: testService, account: testAccount)

        // Then: Token saved successfully
        let saved = try KeychainManager.getToken(service: testService, account: testAccount)
        #expect(saved == token)
    }

    @Test("auth login: Manual mode with new format token (oat01)")
    func authLoginManualModeNewToken() async throws {
        defer { cleanup() }

        // Given: Valid new format token
        let token = "sk-ant-oat01-manual-valid-token-123456789"

        // When: Validate and save
        try ClaudeCodeAuthManager.validateTokenFormat(token)
        try KeychainManager.saveToken(token, service: testService, account: testAccount)

        // Then: Token saved successfully
        let saved = try KeychainManager.getToken(service: testService, account: testAccount)
        #expect(saved == token)
    }

    @Test("auth login: Manual mode with invalid token format")
    func authLoginManualModeInvalid() async throws {
        // Given: Invalid token format
        let invalidToken = "invalid-token-format"

        // When/Then: Validation fails
        #expect(throws: ClaudeCodeAuthError.invalidToken) {
            try ClaudeCodeAuthManager.validateTokenFormat(invalidToken)
        }
    }

    @Test("auth login: Force flag overwrites existing token")
    func authLoginForceOverwrite() async throws {
        defer { cleanup() }

        // Given: Existing token
        let existingToken = "sk-ant-oauth-existing-token-123456789"
        try KeychainManager.saveToken(existingToken, service: testService, account: testAccount)

        // When: Login with force (new token)
        let newToken = "sk-ant-oauth-new-token-forced-123456789"
        try KeychainManager.saveToken(newToken, service: testService, account: testAccount)

        // Then: New token saved
        let saved = try KeychainManager.getToken(service: testService, account: testAccount)
        #expect(saved == newToken)
    }

    // MARK: - Auth Logout Tests

    @Test("auth logout: Removes token successfully")
    func authLogoutRemovesToken() async throws {
        defer { cleanup() }

        // Given: Token in Keychain
        let token = "sk-ant-oauth-logout-test-token-123456789"
        try KeychainManager.saveToken(token, service: testService, account: testAccount)
        #expect(try KeychainManager.getToken(service: testService, account: testAccount) == token)

        // When: Logout
        try KeychainManager.deleteToken(service: testService, account: testAccount)

        // Then: Token removed
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.getToken(service: testService, account: testAccount)
        }
    }

    @Test("auth logout: Handles no token gracefully")
    func authLogoutNoToken() async throws {
        defer { cleanup() }

        // Given: No token in Keychain
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.getToken(service: testService, account: testAccount)
        }

        // When: Try to logout
        // Then: Should throw notFound
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.deleteToken(service: testService, account: testAccount)
        }
    }

    // MARK: - Integration Tests

    @Test("auth integration: Full login-status-logout cycle")
    func authFullCycle() async throws {
        defer { cleanup() }

        // 1. Initial state: no token
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.getToken(service: testService, account: testAccount)
        }

        // 2. Login
        let token = "sk-ant-oauth-full-cycle-token-123456789"
        try ClaudeCodeAuthManager.validateTokenFormat(token)
        try KeychainManager.saveToken(token, service: testService, account: testAccount)

        // 3. Check status
        let saved = try KeychainManager.getToken(service: testService, account: testAccount)
        #expect(saved == token)

        // 4. Logout
        try KeychainManager.deleteToken(service: testService, account: testAccount)

        // 5. Verify logged out
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.getToken(service: testService, account: testAccount)
        }
    }

    // MARK: - Environment Variable Tests

    @Test("auth: Environment variable token priority")
    func authEnvironmentTokenPriority() async throws {
        defer {
            unsetenv("CLAUDE_CODE_OAUTH_TOKEN")
        }

        // Given: Token from env var
        let envToken = "sk-ant-oauth-env-token-123456789"
        setenv("CLAUDE_CODE_OAUTH_TOKEN", envToken, 1)

        // When: Load via EnvironmentConfigLoader
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()
        let token = partial.anthropicAPIKey

        // Then: Env token used
        #expect(token == envToken)
    }

    @Test("auth: SWIFTINDEX prefix has highest priority")
    func authSwiftindexPrefixPriority() async throws {
        defer {
            unsetenv("SWIFTINDEX_ANTHROPIC_API_KEY")
            unsetenv("CLAUDE_CODE_OAUTH_TOKEN")
            unsetenv("ANTHROPIC_API_KEY")
        }

        // Given: All env vars set
        let projectKey = "project-key-12345"
        let oauthToken = "sk-ant-oauth-token-12345"
        let anthropicKey = "standard-key-12345"

        setenv("SWIFTINDEX_ANTHROPIC_API_KEY", projectKey, 1)
        setenv("CLAUDE_CODE_OAUTH_TOKEN", oauthToken, 1)
        setenv("ANTHROPIC_API_KEY", anthropicKey, 1)

        // When: Load config
        let loader = EnvironmentConfigLoader()
        let partial = try loader.load()
        let token = partial.anthropicAPIKey

        // Then: SWIFTINDEX_ prefix wins
        #expect(token == projectKey)
    }
}
