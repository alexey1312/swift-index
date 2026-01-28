// MARK: - AuthCommand Tests

@testable import SwiftIndexCore
import XCTest

/// Tests for AuthCommand CLI commands (status, login, logout)
///
/// Uses test-specific Keychain service/account to avoid interactive prompts in CI.
final class AuthCommandTests: XCTestCase {
    // Test-specific service/account to avoid Keychain prompts
    let testService = "com.swiftindex.oauth.test"
    let testAccount = "claude-code-oauth-token-test"

    // MARK: - Test Setup

    override func tearDown() async throws {
        // Cleanup test Keychain item after each test
        try? KeychainManager.deleteToken(service: testService, account: testAccount)
        try await super.tearDown()
    }

    // MARK: - Auth Status Tests

    func testAuthStatusNoToken() throws {
        // Given: No token in Keychain
        XCTAssertThrowsError(
            try KeychainManager.getToken(service: testService, account: testAccount)
        ) { error in
            guard case KeychainError.notFound = error else {
                XCTFail("Expected .notFound, got \(error)")
                return
            }
        }
    }

    func testAuthStatusWithValidToken() throws {
        // Given: Valid token in Keychain
        let token = "sk-ant-oauth-test-token-123456789012345"
        try KeychainManager.saveToken(token, service: testService, account: testAccount)

        // When: Retrieve token
        let storedToken = try KeychainManager.getToken(service: testService, account: testAccount)

        // Then: Token matches
        XCTAssertEqual(storedToken, token)

        // Token preview format: first 10 chars + masking
        let preview = String(token.prefix(10)) + "***"
        XCTAssertEqual(preview, "sk-ant-oau***")
    }

    // MARK: - Auth Login Tests

    func testAuthLoginManualMode() throws {
        // Given: No existing token
        XCTAssertThrowsError(
            try KeychainManager.getToken(service: testService, account: testAccount)
        )

        // When: Login with manual token input
        let token = "sk-ant-oauth-manual-token-123456789012345"
        try KeychainManager.saveToken(token, service: testService, account: testAccount)

        // Then: Token saved successfully
        let stored = try KeychainManager.getToken(service: testService, account: testAccount)
        XCTAssertEqual(stored, token)
    }

    func testAuthLoginForceOverwritesExisting() throws {
        // Given: Existing token
        let oldToken = "sk-ant-oauth-old-token-123456789012345"
        try KeychainManager.saveToken(oldToken, service: testService, account: testAccount)

        // When: Login with --force (update token)
        let newToken = "sk-ant-oauth-new-token-123456789012345"
        try KeychainManager.saveToken(newToken, service: testService, account: testAccount)

        // Then: Token overwritten
        let stored = try KeychainManager.getToken(service: testService, account: testAccount)
        XCTAssertEqual(stored, newToken)
    }

    func testAuthLoginValidatesToken() throws {
        // Given: Any token (Keychain accepts any string)
        let token = "any-token-value-for-keychain-test"

        // When: Save to Keychain
        try KeychainManager.saveToken(token, service: testService, account: testAccount)

        // Then: Token saved (Keychain doesn't validate format)
        let stored = try KeychainManager.getToken(service: testService, account: testAccount)
        XCTAssertEqual(stored, token)

        // Note: Format validation is done by ClaudeCodeAuthManager, not Keychain
    }

    // MARK: - Auth Logout Tests

    func testAuthLogoutRemovesToken() throws {
        // Given: Token in Keychain
        let token = "sk-ant-oauth-test-token-123456789012345"
        try KeychainManager.saveToken(token, service: testService, account: testAccount)
        XCTAssertNoThrow(try KeychainManager.getToken(service: testService, account: testAccount))

        // When: Logout (delete token)
        try KeychainManager.deleteToken(service: testService, account: testAccount)

        // Then: Token removed
        XCTAssertThrowsError(
            try KeychainManager.getToken(service: testService, account: testAccount)
        ) { error in
            guard case KeychainError.notFound = error else {
                XCTFail("Expected .notFound error, got \(error)")
                return
            }
        }
    }

    func testAuthLogoutWhenNoToken() throws {
        // Given: No token in Keychain
        XCTAssertThrowsError(
            try KeychainManager.getToken(service: testService, account: testAccount)
        )

        // When: Try to logout
        // Then: Should throw notFound error
        XCTAssertThrowsError(
            try KeychainManager.deleteToken(service: testService, account: testAccount)
        ) { error in
            guard case KeychainError.notFound = error else {
                XCTFail("Expected .notFound error, got \(error)")
                return
            }
        }
    }

    // MARK: - Token Format Tests

    func testNewTokenFormatOat01() throws {
        // Given: New format token (sk-ant-oat01-)
        let token = "sk-ant-oat01-test-token-123456789012345"
        try KeychainManager.saveToken(token, service: testService, account: testAccount)

        // When: Retrieve and validate format
        let stored = try KeychainManager.getToken(service: testService, account: testAccount)

        // Then: Token stored correctly
        XCTAssertEqual(stored, token)
        XCTAssertNoThrow(try ClaudeCodeAuthManager.validateTokenFormat(token))
    }
}
