import Foundation
import Security

/// Manages secure storage of OAuth tokens in macOS Keychain
///
/// SwiftIndex stores Claude Code OAuth tokens in system Keychain for security:
/// - Encrypted at rest (managed by macOS)
/// - Access control via kSecAttrAccessibleWhenUnlocked
/// - No plaintext tokens in config files or environment variables
///
/// Platform Support:
/// - ✅ macOS, iOS, tvOS, watchOS (Security.framework)
/// - ❌ Linux, Windows (fallback to environment variables)
///
/// Usage:
/// ```swift
/// // Save token
/// try KeychainManager.saveClaudeCodeToken("sk-ant-oauth-...")
///
/// // Retrieve token
/// let token = try KeychainManager.getClaudeCodeToken()
///
/// // Delete token
/// try KeychainManager.deleteClaudeCodeToken()
/// ```
///
/// Thread Safety:
/// - Security.framework is thread-safe within single process
/// - Cross-process atomicity NOT guaranteed
/// - Advisory file lock used for write operations
public enum KeychainManager {
    // MARK: - Constants

    /// Default service name for OAuth tokens
    public static let defaultServiceName = "com.swiftindex.oauth"

    /// Default account name for Claude Code OAuth token
    public static let defaultAccountName = "claude-code-oauth-token"

    // MARK: - Public API

    /// Save OAuth token to Keychain
    ///
    /// - Parameters:
    ///   - token: OAuth token string (sk-ant-oauth-...)
    ///   - service: Service identifier (default: com.swiftindex.oauth)
    ///   - account: Account identifier (default: claude-code-oauth-token)
    /// - Throws: KeychainError if save fails
    ///
    /// Behavior:
    /// - If token already exists, updates it (upsert)
    /// - Uses advisory file lock to prevent concurrent writes
    /// - Validates token is non-empty before saving
    public static func saveToken(
        _ token: String,
        service: String = defaultServiceName,
        account: String = defaultAccountName
    ) throws {
        // Validate token
        guard !token.isEmpty else {
            throw KeychainError.invalidToken
        }

        // Acquire advisory lock for write operation
        try withLockFile {
            // Try to update existing item first
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]

            let attributes: [String: Any] = [
                kSecValueData as String: token.data(using: .utf8)!,
            ]

            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)

            if updateStatus == errSecSuccess {
                // Update successful
                return
            } else if updateStatus == errSecItemNotFound {
                // Item doesn't exist, create new
                let addQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                    kSecValueData as String: token.data(using: .utf8)!,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
                ]

                let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

                if addStatus == errSecSuccess {
                    return
                } else if addStatus == errSecInteractionNotAllowed {
                    throw KeychainError.keychainLocked
                } else {
                    throw KeychainError.operationFailed(addStatus)
                }
            } else if updateStatus == errSecInteractionNotAllowed {
                throw KeychainError.keychainLocked
            } else {
                throw KeychainError.operationFailed(updateStatus)
            }
        }
    }

    /// Retrieve OAuth token from Keychain
    ///
    /// - Parameters:
    ///   - service: Service identifier
    ///   - account: Account identifier
    /// - Returns: OAuth token string
    /// - Throws: KeychainError.notFound if token doesn't exist
    public static func getToken(
        service: String = defaultServiceName,
        account: String = defaultAccountName
    ) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8)
            else {
                throw KeychainError.unknown
            }
            return token

        case errSecItemNotFound:
            throw KeychainError.notFound

        case errSecInteractionNotAllowed:
            throw KeychainError.keychainLocked

        default:
            throw KeychainError.operationFailed(status)
        }
    }

    /// Delete OAuth token from Keychain
    ///
    /// - Parameters:
    ///   - service: Service identifier
    ///   - account: Account identifier
    /// - Throws: KeychainError.notFound if token doesn't exist
    public static func deleteToken(
        service: String = defaultServiceName,
        account: String = defaultAccountName
    ) throws {
        try withLockFile {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]

            let status = SecItemDelete(query as CFDictionary)

            switch status {
            case errSecSuccess:
                return

            case errSecItemNotFound:
                throw KeychainError.notFound

            case errSecInteractionNotAllowed:
                throw KeychainError.keychainLocked

            default:
                throw KeychainError.operationFailed(status)
            }
        }
    }

    // MARK: - Convenience Methods

    /// Save Claude Code OAuth token using default service/account names
    public static func saveClaudeCodeToken(_ token: String) throws {
        try saveToken(token, service: defaultServiceName, account: defaultAccountName)
    }

    /// Retrieve Claude Code OAuth token using default service/account names
    public static func getClaudeCodeToken() throws -> String {
        try getToken(service: defaultServiceName, account: defaultAccountName)
    }

    /// Delete Claude Code OAuth token using default service/account names
    public static func deleteClaudeCodeToken() throws {
        try deleteToken(service: defaultServiceName, account: defaultAccountName)
    }

    // MARK: - Advisory File Lock

    /// Lock file path for concurrent write protection
    private static let lockFilePath = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftindex-keychain.lock")
        .path

    /// Execute closure with advisory file lock
    ///
    /// Prevents concurrent writes from multiple SwiftIndex processes.
    /// Note: Advisory lock only - not enforced by OS.
    private static func withLockFile<T>(_ operation: () throws -> T) throws -> T {
        let fd = open(lockFilePath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            // Can't create lock file, proceed without locking
            return try operation()
        }

        defer {
            close(fd)
        }

        // Acquire exclusive lock (blocking)
        guard flock(fd, LOCK_EX) == 0 else {
            // Lock failed, proceed without locking
            return try operation()
        }

        defer {
            flock(fd, LOCK_UN)
        }

        return try operation()
    }
}
