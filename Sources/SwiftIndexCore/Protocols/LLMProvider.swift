// MARK: - LLMProvider Protocol

import Foundation

/// A provider that performs text generation using large language models.
///
/// LLM providers handle text completion tasks for query expansion,
/// result synthesis, and follow-up generation. The protocol supports
/// both simple completion and streaming responses.
public protocol LLMProvider: Sendable {
    /// Unique identifier for this provider.
    var id: String { get }

    /// Human-readable name of the provider.
    var name: String { get }

    /// Whether this provider is currently available.
    ///
    /// Availability may depend on:
    /// - CLI tool presence (for Claude Code, Codex)
    /// - Network connectivity (for cloud providers)
    /// - API keys (for commercial providers)
    /// - Local server running (for Ollama)
    func isAvailable() async -> Bool

    /// Generate a completion for the given messages.
    ///
    /// - Parameters:
    ///   - messages: Array of conversation messages.
    ///   - model: Optional model override. If nil, uses provider default.
    ///   - timeout: Maximum time to wait for response (seconds).
    /// - Returns: The generated completion text.
    /// - Throws: `LLMError` if generation fails.
    func complete(
        messages: [LLMMessage],
        model: String?,
        timeout: TimeInterval
    ) async throws -> String
}

// MARK: - Default Implementation

public extension LLMProvider {
    /// Generate a completion using the provider's default model and timeout.
    func complete(messages: [LLMMessage]) async throws -> String {
        try await complete(messages: messages, model: nil, timeout: 60)
    }

    /// Generate a completion with a custom timeout.
    func complete(
        messages: [LLMMessage],
        timeout: TimeInterval
    ) async throws -> String {
        try await complete(messages: messages, model: nil, timeout: timeout)
    }
}

// MARK: - LLMError

/// Errors that can occur with LLM providers.
public enum LLMError: Error, Sendable, Equatable {
    /// The provider is not available on this system.
    case notAvailable(reason: String)

    /// The CLI tool required by the provider is not installed.
    case cliNotFound(tool: String)

    /// API key is required but not provided.
    case apiKeyMissing(provider: String)

    /// API request failed.
    case apiError(code: Int, message: String)

    /// Network error occurred.
    case networkError(String)

    /// The input messages are invalid (empty, too long, etc.).
    case invalidInput(String)

    /// The completion operation timed out.
    case timeout(seconds: TimeInterval)

    /// The CLI process failed.
    case processError(exitCode: Int32, stderr: String)

    /// All providers in the chain failed.
    case allProvidersFailed([String: LLMError])

    /// Rate limit exceeded.
    case rateLimited(retryAfter: TimeInterval?)

    /// Model not found or not supported.
    case modelNotFound(name: String)

    /// Generic provider error.
    case unknown(String)
}

// MARK: - LocalizedError

extension LLMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .notAvailable(reason):
            return "LLM provider not available: \(reason)"
        case let .cliNotFound(tool):
            return "CLI tool not found: \(tool)"
        case let .apiKeyMissing(provider):
            return "API key required for \(provider)"
        case let .apiError(code, message):
            return "API error (\(code)): \(message)"
        case let .networkError(message):
            return "Network error: \(message)"
        case let .invalidInput(message):
            return "Invalid input: \(message)"
        case let .timeout(seconds):
            return "LLM operation timed out after \(Int(seconds))s"
        case let .processError(exitCode, stderr):
            return "Process failed (exit \(exitCode)): \(stderr)"
        case let .allProvidersFailed(errors):
            let details = errors.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            return "All LLM providers failed: \(details)"
        case let .rateLimited(retryAfter):
            if let retry = retryAfter {
                return "Rate limited, retry after \(Int(retry))s"
            }
            return "Rate limited"
        case let .modelNotFound(name):
            return "Model not found: \(name)"
        case let .unknown(message):
            return "Unknown error: \(message)"
        }
    }
}
