import Foundation

/// Errors that can occur during Keychain operations
///
/// SwiftIndex uses macOS Keychain via Security.framework to securely store
/// Claude Code OAuth tokens. This enum covers common failure scenarios.
///
/// Platform Support:
/// - ✅ macOS, iOS, tvOS, watchOS (Security.framework available)
/// - ❌ Linux, Windows (fallback to environment variables)
public enum KeychainError: Error, Equatable {
    /// Token not found in Keychain
    ///
    /// Occurs when:
    /// - User hasn't authenticated yet (`auth login` not run)
    /// - Token was deleted (`auth logout`)
    /// - Using wrong service/account name
    case notFound

    /// Keychain is locked
    ///
    /// Mitigation:
    /// - User must unlock Keychain: `security unlock-keychain`
    /// - Fallback to environment variable: `ANTHROPIC_API_KEY`
    case keychainLocked

    /// Invalid token (empty, malformed)
    case invalidToken

    /// Generic Keychain operation failed
    ///
    /// Wraps underlying Security.framework OSStatus errors
    case operationFailed(OSStatus)

    /// Unknown error (should not happen in production)
    case unknown
}

extension KeychainError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound:
            "OAuth token not found in Keychain. Run 'swiftindex auth login' to authenticate."

        case .keychainLocked:
            """
            Keychain is locked. Unlock it with:
              security unlock-keychain ~/Library/Keychains/login.keychain-db

            Alternative: Set environment variable ANTHROPIC_API_KEY
            """

        case .invalidToken:
            "Invalid token: cannot be empty"

        case let .operationFailed(status):
            "Keychain operation failed with status \(status)"

        case .unknown:
            "Unknown Keychain error"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notFound:
            "Authenticate with: swiftindex auth login"

        case .keychainLocked:
            "Unlock Keychain or use environment variable"

        case .invalidToken:
            "Provide a valid OAuth token (sk-ant-oauth-...)"

        case .operationFailed:
            "Check Keychain Access.app permissions"

        case .unknown:
            nil
        }
    }
}
