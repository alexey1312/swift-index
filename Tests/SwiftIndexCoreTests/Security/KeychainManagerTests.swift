import Security
@testable import SwiftIndexCore
import XCTest

/// Unit tests for KeychainManager
///
/// Tests verify CRUD operations for OAuth tokens in macOS Keychain:
/// - Token storage and retrieval
/// - Token deletion
/// - Error handling (duplicate saves, not found)
/// - Platform availability
///
/// Implementation Notes:
/// - Tests use unique service/account names for isolation
/// - Cleanup after each test to avoid state pollution
/// - Platform guard: only runs on Apple platforms with Security.framework
final class KeychainManagerTests: XCTestCase {
    // Test-specific service name to avoid conflicts with production keychain items
    let testServiceName = "com.swiftindex.oauth.test"
    let testAccountName = "claude-code-oauth-token-test"

    override func tearDown() async throws {
        try await super.tearDown()
        // Cleanup: delete test token after each test
        try? KeychainManager.deleteToken(
            service: testServiceName,
            account: testAccountName
        )
    }

    // MARK: - Save Token Tests

    func testSaveToken_Success() throws {
        // Given: a valid OAuth token
        let token = "sk-ant-oauth-test-token-12345"

        // When: saving to Keychain
        try KeychainManager.saveToken(
            token,
            service: testServiceName,
            account: testAccountName
        )

        // Then: token should be retrievable
        let retrieved = try KeychainManager.getToken(
            service: testServiceName,
            account: testAccountName
        )
        XCTAssertEqual(retrieved, token)
    }

    func testSaveToken_Update_Success() throws {
        // Given: existing token
        let oldToken = "sk-ant-oauth-old-token"
        try KeychainManager.saveToken(
            oldToken,
            service: testServiceName,
            account: testAccountName
        )

        // When: updating with new token
        let newToken = "sk-ant-oauth-new-token"
        try KeychainManager.saveToken(
            newToken,
            service: testServiceName,
            account: testAccountName
        )

        // Then: new token should be retrieved
        let retrieved = try KeychainManager.getToken(
            service: testServiceName,
            account: testAccountName
        )
        XCTAssertEqual(retrieved, newToken)
    }

    func testSaveToken_EmptyToken_ThrowsError() throws {
        // When: trying to save empty token
        // Then: should throw validation error
        XCTAssertThrowsError(
            try KeychainManager.saveToken(
                "",
                service: testServiceName,
                account: testAccountName
            )
        ) { error in
            guard case KeychainError.invalidToken = error else {
                XCTFail("Expected .invalidToken, got \(error)")
                return
            }
        }
    }

    // MARK: - Get Token Tests

    func testGetToken_NotFound_ThrowsError() throws {
        // When: retrieving non-existent token
        // Then: should throw notFound error
        XCTAssertThrowsError(
            try KeychainManager.getToken(
                service: testServiceName,
                account: testAccountName
            )
        ) { error in
            guard case KeychainError.notFound = error else {
                XCTFail("Expected .notFound, got \(error)")
                return
            }
        }
    }

    func testGetToken_AfterSave_ReturnsToken() throws {
        // Given: saved token
        let token = "sk-ant-oauth-test-12345"
        try KeychainManager.saveToken(
            token,
            service: testServiceName,
            account: testAccountName
        )

        // When: retrieving token
        let retrieved = try KeychainManager.getToken(
            service: testServiceName,
            account: testAccountName
        )

        // Then: should match saved token
        XCTAssertEqual(retrieved, token)
    }

    // MARK: - Delete Token Tests

    func testDeleteToken_Success() throws {
        // Given: saved token
        let token = "sk-ant-oauth-test-12345"
        try KeychainManager.saveToken(
            token,
            service: testServiceName,
            account: testAccountName
        )

        // When: deleting token
        try KeychainManager.deleteToken(
            service: testServiceName,
            account: testAccountName
        )

        // Then: token should not be found
        XCTAssertThrowsError(
            try KeychainManager.getToken(
                service: testServiceName,
                account: testAccountName
            )
        ) { error in
            guard case KeychainError.notFound = error else {
                XCTFail("Expected .notFound, got \(error)")
                return
            }
        }
    }

    func testDeleteToken_NotFound_ThrowsError() throws {
        // When: deleting non-existent token
        // Then: should throw notFound error
        XCTAssertThrowsError(
            try KeychainManager.deleteToken(
                service: testServiceName,
                account: testAccountName
            )
        ) { error in
            guard case KeychainError.notFound = error else {
                XCTFail("Expected .notFound, got \(error)")
                return
            }
        }
    }

    // MARK: - Convenience Methods Tests

    func testClaudeCodeTokenConvenienceMethods() throws {
        // Test save/get/delete flow using test-specific service/account
        // to avoid Keychain prompts in CI (production keys require user interaction)
        let token = "sk-ant-oauth-convenience-test-12345678901234567890"

        // Save using test service/account
        try KeychainManager.saveToken(
            token,
            service: testServiceName,
            account: testAccountName
        )

        // Retrieve and verify
        let retrieved = try KeychainManager.getToken(
            service: testServiceName,
            account: testAccountName
        )
        XCTAssertEqual(retrieved, token)

        // Delete
        try KeychainManager.deleteToken(
            service: testServiceName,
            account: testAccountName
        )

        // Verify deletion
        XCTAssertThrowsError(
            try KeychainManager.getToken(
                service: testServiceName,
                account: testAccountName
            )
        ) { error in
            guard case KeychainError.notFound = error else {
                XCTFail("Expected .notFound, got \(error)")
                return
            }
        }
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentSave_LastWriteWins() async throws {
        // Given: multiple concurrent save operations
        let tokens = (1 ... 10).map { "sk-ant-oauth-concurrent-\($0)" }
        let service = testServiceName
        let account = testAccountName

        // When: saving concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for token in tokens {
                group.addTask {
                    try KeychainManager.saveToken(
                        token,
                        service: service,
                        account: account
                    )
                }
            }
            try await group.waitForAll()
        }

        // Then: one of the tokens should be saved (last write wins)
        let retrieved = try KeychainManager.getToken(
            service: testServiceName,
            account: testAccountName
        )
        XCTAssertTrue(tokens.contains(retrieved), "Retrieved token should be one of the saved tokens")
    }
}
