// MARK: - FileHasher

import Crypto
import Foundation

/// Centralized file hashing utility.
///
/// Provides a single source of truth for computing file content hashes,
/// ensuring consistent hash values across all components (parsers, indexers, etc.).
public enum FileHasher {
    /// Computes SHA-256 hash of the given content.
    ///
    /// Returns the full 64-character hexadecimal string representation
    /// of the SHA-256 digest.
    ///
    /// - Parameter content: The string content to hash.
    /// - Returns: 64-character lowercase hex string.
    public static func hash(_ content: String) -> String {
        let data = Data(content.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
