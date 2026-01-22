// MARK: - ProviderError Enum

import Foundation

/// Errors that can occur with embedding providers.
public enum ProviderError: Error, Sendable, Equatable {
    /// The provider is not available on this system.
    case notAvailable(reason: String)

    /// The required model is not downloaded.
    case modelNotFound(name: String)

    /// The model is not supported by this provider.
    case unsupportedModel(name: String, reason: String)

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

    /// The embedding operation failed.
    case embeddingFailed(String)

    /// All providers in the chain failed.
    case allProvidersFailed([String: ProviderError])

    /// Generic provider error.
    case unknown(String)
}

// MARK: - LocalizedError

extension ProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .notAvailable(reason):
            return "Provider not available: \(reason)"
        case let .modelNotFound(name):
            return "Model not found: \(name)"
        case let .unsupportedModel(name, reason):
            return "Model '\(name)' not supported: \(reason)"
        case let .downloadFailed(reason):
            return "Model download failed: \(reason)"
        case let .apiKeyMissing(provider):
            return "API key required for \(provider)"
        case let .apiError(code, message):
            return "API error (\(code)): \(message)"
        case let .networkError(message):
            return "Network error: \(message)"
        case let .invalidInput(message):
            return "Invalid input: \(message)"
        case let .dimensionMismatch(expected, actual):
            return "Dimension mismatch: expected \(expected), got \(actual)"
        case .timeout:
            return "Embedding operation timed out"
        case let .embeddingFailed(message):
            return "Embedding failed: \(message)"
        case let .allProvidersFailed(errors):
            let details = errors.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            return "All providers failed: \(details)"
        case let .unknown(message):
            return "Unknown error: \(message)"
        }
    }
}
