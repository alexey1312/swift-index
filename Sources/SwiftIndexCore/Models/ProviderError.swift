// MARK: - ProviderError Enum

import Foundation

/// Errors that can occur with embedding providers.
public enum ProviderError: Error, Sendable, Equatable {
    /// The provider is not available on this system.
    case notAvailable(reason: String)

    /// The required model is not downloaded.
    case modelNotFound(name: String)

    /// Model download failed.
    case downloadFailed(reason: String)

    /// API key is required but not provided.
    case apiKeyMissing(provider: String)

    /// API request failed.
    case apiError(code: Int, message: String)

    /// Network error occurred.
    case networkError(String)

    /// The input text is invalid (empty, too long, etc.).
    case invalidInput(String)

    /// Vector dimension mismatch.
    case dimensionMismatch(expected: Int, actual: Int)

    /// The embedding operation timed out.
    case timeout

    /// All providers in the chain failed.
    case allProvidersFailed([String: ProviderError])

    /// Generic provider error.
    case unknown(String)
}

// MARK: - LocalizedError

extension ProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAvailable(let reason):
            return "Provider not available: \(reason)"
        case .modelNotFound(let name):
            return "Model not found: \(name)"
        case .downloadFailed(let reason):
            return "Model download failed: \(reason)"
        case .apiKeyMissing(let provider):
            return "API key required for \(provider)"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .dimensionMismatch(let expected, let actual):
            return "Dimension mismatch: expected \(expected), got \(actual)"
        case .timeout:
            return "Embedding operation timed out"
        case .allProvidersFailed(let errors):
            let details = errors.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            return "All providers failed: \(details)"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}
