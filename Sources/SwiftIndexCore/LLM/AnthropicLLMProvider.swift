// MARK: - AnthropicLLMProvider

import Foundation

/// LLM provider that uses the Anthropic Messages API for text generation.
///
/// This provider connects directly to Anthropic's API, avoiding the CLI overhead
/// that causes 30-40s delays with `claude-code-cli`. Direct API access typically
/// completes in 5-10s.
///
/// ## Prerequisites
///
/// Set the `ANTHROPIC_API_KEY` environment variable or pass it directly.
///
/// ## Usage
///
/// ```swift
/// let provider = AnthropicLLMProvider(apiKey: "sk-ant-...")
/// let response = try await provider.complete(messages: [
///     .system("You are a helpful assistant."),
///     .user("What is the capital of France?")
/// ])
/// ```
///
/// ## Performance Comparison
///
/// | Provider | Typical Latency |
/// |----------|----------------|
/// | `claude-code-cli` | ~35-40s |
/// | `anthropic` (this) | ~5-10s |
public struct AnthropicLLMProvider: LLMProvider, Sendable {
    // MARK: - Properties

    public let id: String = "anthropic"
    public let name: String = "Anthropic API"

    /// The Anthropic API key.
    private let apiKey: String

    /// The API base URL.
    private let baseURL: URL

    /// The default model to use.
    public let defaultModel: Model

    /// URL session for making requests.
    private let session: URLSession

    // MARK: - Model

    /// Supported Anthropic Claude 4.5 models.
    public enum Model: String, Sendable {
        case sonnet = "claude-sonnet-4-5-20250929"
        case haiku = "claude-haiku-4-5-20251001"
        case opus = "claude-opus-4-5-20251101"
    }

    // MARK: - Initialization

    /// Creates an Anthropic LLM provider.
    ///
    /// - Parameters:
    ///   - apiKey: Anthropic API key.
    ///   - baseURL: API base URL. Default is Anthropic's API.
    ///   - defaultModel: Default model for completions.
    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
        defaultModel: Model = .haiku
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.defaultModel = defaultModel

        // Configure session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
    }

    // MARK: - LLMProvider

    public func isAvailable() async -> Bool {
        // Anthropic is available if we have an API key
        !apiKey.isEmpty
    }

    public func complete(
        messages: [LLMMessage],
        model: String?,
        timeout: TimeInterval
    ) async throws -> String {
        guard !messages.isEmpty else {
            throw LLMError.invalidInput("Messages cannot be empty")
        }

        guard !apiKey.isEmpty else {
            throw LLMError.apiKeyMissing(provider: "Anthropic")
        }

        let messagesURL = baseURL.appendingPathComponent("messages")

        // Build request
        var request = URLRequest(url: messagesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = timeout

        // Separate system message from conversation messages
        // Anthropic API uses a dedicated "system" field, not a system role in messages
        let systemMessage = messages.first { $0.role == .system }?.content
        let conversationMessages = messages.filter { $0.role != .system }

        // Convert messages to Anthropic format
        let anthropicMessages = conversationMessages.map { message -> [String: String] in
            [
                "role": message.role.rawValue,
                "content": message.content,
            ]
        }

        let payload = MessagesRequest(
            model: model ?? defaultModel.rawValue,
            maxTokens: 4096,
            system: systemMessage,
            messages: anthropicMessages
        )

        request.httpBody = try JSONCodec.makeEncoder().encode(payload)

        // Make request
        let (data, response) = try await session.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError("Invalid response type")
        }

        // Handle errors
        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw LLMError.apiKeyMissing(provider: "Anthropic")
        case 404:
            throw LLMError.modelNotFound(name: model ?? defaultModel.rawValue)
        case 429:
            // Parse retry-after header if available
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Double($0) }
            throw LLMError.rateLimited(retryAfter: retryAfter)
        case 529:
            // Anthropic overloaded
            throw LLMError.apiError(code: 529, message: "Anthropic API is temporarily overloaded")
        default:
            let errorMessage = parseErrorMessage(from: data) ?? "Unknown error"
            throw LLMError.apiError(code: httpResponse.statusCode, message: errorMessage)
        }

        // Parse response
        let messagesResponse = try JSONCodec.makeDecoder().decode(MessagesResponse.self, from: data)

        // Extract text content from response
        guard let textContent = messagesResponse.content.first(where: { $0.type == "text" }) else {
            throw LLMError.unknown("No text content in response")
        }

        return textContent.text
    }

    // MARK: - Private Methods

    private func parseErrorMessage(from data: Data) -> String? {
        struct ErrorResponse: Decodable {
            let error: ErrorDetail

            struct ErrorDetail: Decodable {
                let type: String
                let message: String
            }
        }

        return try? JSONCodec.makeDecoder().decode(ErrorResponse.self, from: data).error.message
    }
}

// MARK: - Request/Response Types

private struct MessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [[String: String]]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(maxTokens, forKey: .maxTokens)
        if let system {
            try container.encode(system, forKey: .system)
        }
        try container.encode(messages, forKey: .messages)
    }
}

private struct MessagesResponse: Decodable {
    let id: String
    let type: String
    let role: String
    let content: [ContentBlock]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case role
        case content
        case stopReason = "stop_reason"
    }

    struct ContentBlock: Decodable {
        let type: String
        let text: String
    }
}
