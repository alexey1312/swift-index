// MARK: - Claude Code OAuth E2E Tests

import Foundation
import Testing

@testable import SwiftIndexCore

/// End-to-end tests for Claude Code OAuth integration.
///
/// Uses test-specific Keychain service/account to avoid interactive prompts.
@Suite("Claude Code OAuth E2E")
struct ClaudeCodeOAuthE2ETests {
    // Test-specific service/account to avoid Keychain prompts
    private let testService = "com.swiftindex.oauth.e2e-test"
    private let testAccount = "claude-code-oauth-e2e-test"

    // MARK: - Test Cleanup

    private func cleanup() {
        try? KeychainManager.deleteToken(service: testService, account: testAccount)
    }

    // MARK: - Full OAuth Flow Tests

    @Test("OAuth flow: Token save and retrieval")
    func tokenSaveAndRetrieval() async throws {
        defer { cleanup() }

        // Given: No existing token
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.getToken(service: testService, account: testAccount)
        }

        // When: Save token
        let token = "sk-ant-oauth-auto-generated-token-12345"
        try KeychainManager.saveToken(token, service: testService, account: testAccount)

        // Then: Token saved and retrievable
        let retrieved = try KeychainManager.getToken(service: testService, account: testAccount)
        #expect(retrieved == token)
    }

    @Test("OAuth flow: Manual token input with validation")
    func manualTokenInputFlow() async throws {
        defer { cleanup() }

        // Given: Manual input mode
        let manualToken = "sk-ant-oauth-manual-token-6789012345678901234"

        // When: Validate and save
        try ClaudeCodeAuthManager.validateTokenFormat(manualToken)
        try KeychainManager.saveToken(manualToken, service: testService, account: testAccount)

        // Then: Token validated and saved
        let retrieved = try KeychainManager.getToken(service: testService, account: testAccount)
        #expect(retrieved == manualToken)
    }

    @Test("OAuth flow: New format token (sk-ant-oat01-)")
    func newFormatToken() async throws {
        defer { cleanup() }

        // Given: New format token
        let newFormatToken = "sk-ant-oat01-test-token-123456789012345"

        // When: Validate and save
        try ClaudeCodeAuthManager.validateTokenFormat(newFormatToken)
        try KeychainManager.saveToken(newFormatToken, service: testService, account: testAccount)

        // Then: Token validated and saved
        let retrieved = try KeychainManager.getToken(service: testService, account: testAccount)
        #expect(retrieved == newFormatToken)
    }

    @Test("OAuth flow: Invalid token format rejected")
    func invalidTokenFormatRejected() async throws {
        // Given: Invalid token format
        let invalidToken = "not-a-valid-oauth-token"

        // When/Then: Validation fails
        #expect(throws: ClaudeCodeAuthError.invalidToken) {
            try ClaudeCodeAuthManager.validateTokenFormat(invalidToken)
        }
    }

    @Test("OAuth flow: Token update (overwrite)")
    func tokenUpdate() async throws {
        defer { cleanup() }

        // Given: Existing token
        let existingToken = "sk-ant-oauth-existing-token-1234567890"
        try KeychainManager.saveToken(existingToken, service: testService, account: testAccount)

        // When: Save new token
        let newToken = "sk-ant-oauth-new-token-0987654321"
        try KeychainManager.saveToken(newToken, service: testService, account: testAccount)

        // Then: Token updated
        let updated = try KeychainManager.getToken(service: testService, account: testAccount)
        #expect(updated == newToken)
    }

    // MARK: - Token Lifecycle Tests

    @Test("OAuth lifecycle: Save, retrieve, delete")
    func tokenLifecycle() async throws {
        defer { cleanup() }

        let token = "sk-ant-oauth-lifecycle-token-123456789"

        // Save
        try KeychainManager.saveToken(token, service: testService, account: testAccount)
        let saved = try KeychainManager.getToken(service: testService, account: testAccount)
        #expect(saved == token)

        // Delete
        try KeychainManager.deleteToken(service: testService, account: testAccount)

        // Verify deleted
        #expect(throws: KeychainError.notFound) {
            try KeychainManager.getToken(service: testService, account: testAccount)
        }
    }

    @Test("OAuth lifecycle: Multiple save operations")
    func multipleSaveOperations() async throws {
        defer { cleanup() }

        // First save
        let token1 = "sk-ant-oauth-token-1-1234567890123456"
        try KeychainManager.saveToken(token1, service: testService, account: testAccount)
        #expect(try KeychainManager.getToken(service: testService, account: testAccount) == token1)

        // Second save (overwrite)
        let token2 = "sk-ant-oauth-token-2-1234567890123456"
        try KeychainManager.saveToken(token2, service: testService, account: testAccount)
        #expect(try KeychainManager.getToken(service: testService, account: testAccount) == token2)

        // Third save (overwrite again)
        let token3 = "sk-ant-oauth-token-3-1234567890123456"
        try KeychainManager.saveToken(token3, service: testService, account: testAccount)
        #expect(try KeychainManager.getToken(service: testService, account: testAccount) == token3)
    }

    // MARK: - Concurrent Access Tests

    @Test("OAuth concurrency: Multiple save operations")
    func concurrentSaveOperations() async throws {
        defer { cleanup() }

        // Given: Multiple concurrent save attempts
        let tokens = (1 ... 5).map { "sk-ant-oauth-concurrent-token-\($0)-12345" }
        let service = testService
        let account = testAccount

        // When: Save concurrently (with advisory lock)
        await withTaskGroup(of: Void.self) { group in
            for token in tokens {
                group.addTask {
                    try? KeychainManager.saveToken(token, service: service, account: account)
                }
            }
        }

        // Then: One token should be saved (last one wins with advisory lock)
        let final = try? KeychainManager.getToken(service: testService, account: testAccount)
        #expect(final != nil)
        #expect(tokens.contains(final!))
    }

    // MARK: - Token Parsing Tests

    @Test("Token parsing: Legacy format")
    func parseTokenLegacyFormat() throws {
        let output = """
        Success! Generated OAuth token:
        sk-ant-oauth-abc123_xyz789-abcdefghijklmnopqrstuvwxyz
        """

        let token = try ClaudeCodeAuthManager.parseToken(from: output)
        #expect(token == "sk-ant-oauth-abc123_xyz789-abcdefghijklmnopqrstuvwxyz")
    }

    @Test("Token parsing: New format (oat01)")
    func parseTokenNewFormat() throws {
        let output = """
        Success! Generated OAuth token:
        sk-ant-oat01-v8a7uwluChMvsevK-3vtBpS-1Zl6rTkGRzhfcZ
        """

        let token = try ClaudeCodeAuthManager.parseToken(from: output)
        #expect(token.hasPrefix("sk-ant-oat01-"))
    }

    @Test("Token parsing: No token in output")
    func parseTokenNoToken() throws {
        let output = """
        Error: Authentication failed
        Please try again
        """

        #expect(throws: ClaudeCodeAuthError.parsingFailed) {
            try ClaudeCodeAuthManager.parseToken(from: output)
        }
    }
}
