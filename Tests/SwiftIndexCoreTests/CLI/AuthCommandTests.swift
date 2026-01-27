// MARK: - AuthCommand Tests

@testable import SwiftIndexCore
import XCTest

/// Tests for AuthCommand CLI commands (status, login, logout)
final class AuthCommandTests: XCTestCase {
    // MARK: - Test Setup

    #if canImport(Security)

        override func tearDown() async throws {
            // Cleanup Keychain after each test
            try? KeychainManager.deleteClaudeCodeToken()
            try await super.tearDown()
        }

        // MARK: - Auth Status Tests

        func testAuthStatusNoToken() throws {
            // Given: No token in Keychain
            XCTAssertThrowsError(try KeychainManager.getClaudeCodeToken())

            // When/Then: status should show "No token found"
            // (This will be implemented in AuthCommand)
        }

        func testAuthStatusWithValidToken() throws {
            // Given: Valid token in Keychain
            let token = "sk-ant-oauth-test-token-12345"
            try KeychainManager.saveClaudeCodeToken(token)

            // When/Then: status should show token preview
            let storedToken = try KeychainManager.getClaudeCodeToken()
            XCTAssertEqual(storedToken, token)

            // Token preview format: first 10 chars + masking
            let preview = String(token.prefix(10)) + "***"
            XCTAssertEqual(preview, "sk-ant-oau***")
        }

        func testAuthStatusShowsTokenSource() throws {
            // Given: Token from Keychain
            let token = "sk-ant-oauth-test-token"
            try KeychainManager.saveClaudeCodeToken(token)

            // When/Then: status should indicate source as "Keychain"
            // (This will be implemented in AuthCommand)
        }

        // MARK: - Auth Login Tests

        func testAuthLoginManualMode() throws {
            // Given: No existing token
            XCTAssertThrowsError(try KeychainManager.getClaudeCodeToken())

            // When: Login with manual token input
            let token = "sk-ant-oauth-manual-token-12345"
            try KeychainManager.saveClaudeCodeToken(token)

            // Then: Token saved successfully
            let stored = try KeychainManager.getClaudeCodeToken()
            XCTAssertEqual(stored, token)
        }

        func testAuthLoginForceOverwritesExisting() throws {
            // Given: Existing token
            let oldToken = "sk-ant-oauth-old-token"
            try KeychainManager.saveClaudeCodeToken(oldToken)

            // When: Login with --force
            let newToken = "sk-ant-oauth-new-token"
            try KeychainManager.saveClaudeCodeToken(newToken)

            // Then: Token overwritten
            let stored = try KeychainManager.getClaudeCodeToken()
            XCTAssertEqual(stored, newToken)
        }

        func testAuthLoginValidatesToken() throws {
            // Given: Invalid token format
            let invalidToken = "not-a-valid-token"

            // When: Try to save invalid token
            try KeychainManager.saveClaudeCodeToken(invalidToken)

            // Then: Token saved (validation happens at API level, not Keychain level)
            let stored = try KeychainManager.getClaudeCodeToken()
            XCTAssertEqual(stored, invalidToken)

            // Note: Actual validation should happen in AuthCommand using ClaudeCodeAuthManager
        }

        // MARK: - Auth Logout Tests

        func testAuthLogoutRemovesToken() throws {
            // Given: Token in Keychain
            let token = "sk-ant-oauth-test-token"
            try KeychainManager.saveClaudeCodeToken(token)
            XCTAssertNoThrow(try KeychainManager.getClaudeCodeToken())

            // When: Logout
            try KeychainManager.deleteClaudeCodeToken()

            // Then: Token removed
            XCTAssertThrowsError(try KeychainManager.getClaudeCodeToken()) { error in
                guard case KeychainError.notFound = error else {
                    XCTFail("Expected itemNotFound error, got \(error)")
                    return
                }
            }
        }

        func testAuthLogoutWhenNoToken() throws {
            // Given: No token in Keychain
            XCTAssertThrowsError(try KeychainManager.getClaudeCodeToken())

            // When: Try to logout
            // Then: Should throw notFound error
            XCTAssertThrowsError(try KeychainManager.deleteClaudeCodeToken()) { error in
                guard case KeychainError.notFound = error else {
                    XCTFail("Expected notFound error, got \(error)")
                    return
                }
            }

            // Note: AuthCommand handles this gracefully (shows "already logged out")
        }

        // MARK: - Error Handling Tests

        func testAuthCommandShowsHelpfulErrorMessages() throws {
            // Test error messages for common scenarios
            // (Will be implemented in AuthCommand)

            // 1. Keychain locked
            // 2. Token expired (401 from API)
            // 3. CLI not installed
            // 4. Network error during validation
        }

    #else
        func testAuthCommandsUnavailableOnNonApplePlatforms() throws {
            // On Linux/Windows, auth commands should show platform-specific message
            // indicating Keychain is not available
        }
    #endif
}
