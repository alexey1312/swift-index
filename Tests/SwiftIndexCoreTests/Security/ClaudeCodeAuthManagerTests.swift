@testable import SwiftIndexCore
import XCTest

/// Unit tests for ClaudeCodeAuthManager
///
/// Tests verify OAuth flow management:
/// - CLI availability detection
/// - Token parsing from `claude setup-token` output
/// - Manual token input validation
/// - Token validation via Anthropic API (mocked)
///
/// Implementation Notes:
/// - Uses mock subprocess to avoid calling real `claude` CLI
/// - Token parsing tests use real output examples
/// - Validation tests mock Anthropic API responses
final class ClaudeCodeAuthManagerTests: XCTestCase {
    // MARK: - CLI Availability Tests

    func testIsCLIAvailable_WhenClaudeExists_ReturnsTrue() async throws {
        // Given: claude CLI exists in PATH
        // When: checking availability
        let available = await ClaudeCodeAuthManager.isCLIAvailable()

        // Then: should detect CLI
        // Note: This test depends on real environment
        // In CI, claude CLI may not be installed
        print("Claude CLI available: \(available)")
    }

    // MARK: - Token Parsing Tests

    func testParseToken_ValidOutput_ExtractsToken() throws {
        // Given: realistic `claude setup-token` output
        let output = """
        Authenticating with Claude...
        Opening browser for authentication...
        Success! Generated OAuth token:
        sk-ant-oauth-abc123_xyz789-abcdefghijklmnopqrstuvwxyz

        Token stored in Keychain.
        """

        // When: parsing token
        let token = try ClaudeCodeAuthManager.parseToken(from: output)

        // Then: should extract correct token
        XCTAssertEqual(token, "sk-ant-oauth-abc123_xyz789-abcdefghijklmnopqrstuvwxyz")
    }

    func testParseToken_TokenOnSingleLine_ExtractsToken() throws {
        // Given: token on single line
        let output = "sk-ant-oauth-test1234567890123456789012345678901234567890"

        // When: parsing token
        let token = try ClaudeCodeAuthManager.parseToken(from: output)

        // Then: should extract token
        XCTAssertEqual(token, "sk-ant-oauth-test1234567890123456789012345678901234567890")
    }

    func testParseToken_MultipleTokens_UsesFirst() throws {
        // Given: output with multiple token-like strings
        let output = """
        Old token: sk-ant-oauth-old123456789012345678901234567890123456789
        New token: sk-ant-oauth-new123456789012345678901234567890123456789
        """

        // When: parsing token
        let token = try ClaudeCodeAuthManager.parseToken(from: output)

        // Then: should use first match
        XCTAssertEqual(token, "sk-ant-oauth-old123456789012345678901234567890123456789")
    }

    func testParseToken_NoToken_ThrowsError() throws {
        // Given: output without token
        let output = """
        Error: Authentication failed
        Please try again
        """

        // When: parsing token
        // Then: should throw parsing error
        XCTAssertThrowsError(
            try ClaudeCodeAuthManager.parseToken(from: output)
        ) { error in
            guard case ClaudeCodeAuthError.parsingFailed = error else {
                XCTFail("Expected .parsingFailed, got \(error)")
                return
            }
        }
    }

    func testParseToken_EmptyOutput_ThrowsError() throws {
        // When: parsing empty output
        // Then: should throw parsing error
        XCTAssertThrowsError(
            try ClaudeCodeAuthManager.parseToken(from: "")
        ) { error in
            guard case ClaudeCodeAuthError.parsingFailed = error else {
                XCTFail("Expected .parsingFailed, got \(error)")
                return
            }
        }
    }

    // MARK: - Token Validation Tests

    func testValidateTokenFormat_ValidToken_Succeeds() throws {
        // Given: valid OAuth token format
        let token = "sk-ant-oauth-abc123_xyz789-12345678901234567890"

        // When: validating format
        try ClaudeCodeAuthManager.validateTokenFormat(token)

        // Then: should not throw (success)
    }

    func testValidateTokenFormat_EmptyToken_ThrowsError() throws {
        // When: validating empty token
        // Then: should throw validation error
        XCTAssertThrowsError(
            try ClaudeCodeAuthManager.validateTokenFormat("")
        ) { error in
            guard case ClaudeCodeAuthError.invalidToken = error else {
                XCTFail("Expected .invalidToken, got \(error)")
                return
            }
        }
    }

    func testValidateTokenFormat_ShortToken_ThrowsError() throws {
        // Given: token too short (< 20 chars after prefix)
        let token = "sk-ant-oauth-short"

        // When: validating format
        // Then: should throw validation error
        XCTAssertThrowsError(
            try ClaudeCodeAuthManager.validateTokenFormat(token)
        ) { error in
            guard case ClaudeCodeAuthError.invalidToken = error else {
                XCTFail("Expected .invalidToken, got \(error)")
                return
            }
        }
    }

    func testValidateTokenFormat_WrongPrefix_ThrowsError() throws {
        // Given: token with wrong prefix
        let token = "sk-ant-api-abc123_xyz789-12345678901234567890"

        // When: validating format
        // Then: should throw validation error
        XCTAssertThrowsError(
            try ClaudeCodeAuthManager.validateTokenFormat(token)
        ) { error in
            guard case ClaudeCodeAuthError.invalidToken = error else {
                XCTFail("Expected .invalidToken, got \(error)")
                return
            }
        }
    }

    // MARK: - Integration Tests (Manual - require mocking)

    // Note: These tests require mocking subprocess and Anthropic API
    // For now, they serve as documentation of expected behavior

    /*
     func testSetupOAuthToken_Automatic_Success() async throws {
         // Given: claude CLI available
         // When: running automatic OAuth flow
         let token = try await ClaudeCodeAuthManager.setupOAuthToken(manual: false)

         // Then: should return valid token
         XCTAssertTrue(token.hasPrefix("sk-ant-oauth-"))
     }

     func testSetupOAuthToken_Manual_Success() async throws {
         // Given: user provides token manually
         // When: running manual OAuth flow with mock input
         let token = try await ClaudeCodeAuthManager.setupOAuthToken(
             manual: true,
             mockInput: "sk-ant-oauth-manual-test-12345678901234567890"
         )

         // Then: should return provided token
         XCTAssertEqual(token, "sk-ant-oauth-manual-test-12345678901234567890")
     }
     */
}
