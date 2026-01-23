// MARK: - OpenAILLMProvider

import Foundation

/// LLM provider that uses the OpenAI API for text generation.
///
/// This provider connects to OpenAI's chat completions API to generate
/// responses. Requires an API key.
///
/// ## Prerequisites
///
/// Set the `OPENAI_API_KEY` environment variable or pass it directly.
///
/// ## Usage
///
/// ```swift
/// let provider = OpenAILLMProvider(apiKey: "sk-...")
/// let response = try await provider.complete(messages: [
///     .system("You are a helpful assistant."),
///     .user("What is the capital of France?")
/// ])
/// ```
public struct OpenAILLMProvider: LLMProvider, Sendable {
    // MARK: - Properties

    public let id: String = "openai"
    public let name: String = "OpenAI LLM Provider"

    /// The OpenAI API key.
    private let apiKey: String

    /// The API base URL.
    private let baseURL: URL

    /// The default model to use.
    public let defaultModel: Model

    /// URL session for making requests.
    private let session: URLSession

    // MARK: - Model

    /// Supported OpenAI models.
    public enum Model: String, Sendable {
        case gpt4o = "gpt-4o"
        case gpt4oMini = "gpt-4o-mini"
        case gpt4Turbo = "gpt-4-turbo"
        case gpt35Turbo = "gpt-3.5-turbo"
        case o1
        case o1Mini = "o1-mini"
        case o1Preview = "o1-preview"
        case o3Mini = "o3-mini"
    }

    // MARK: - Initialization

    /// Creates an OpenAI LLM provider.
    ///
    /// - Parameters:
    ///   - apiKey: OpenAI API key.
    ///   - baseURL: API base URL. Default is OpenAI's API.
    ///   - defaultModel: Default model for completions.
    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        defaultModel: Model = .gpt4oMini
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
        // OpenAI is available if we have an API key
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
            throw LLMError.apiKeyMissing(provider: "OpenAI")
        }

        let chatURL = baseURL.appendingPathComponent("chat/completions")

        // Build request
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout

        // Convert messages to OpenAI format
        let openAIMessages = messages.map { message -> [String: String] in
            [
                "role": message.role.rawValue,
                "content": message.content,
            ]
        }

        let payload = ChatCompletionRequest(
            model: model ?? defaultModel.rawValue,
            messages: openAIMessages
        )

        request.httpBody = try JSONEncoder().encode(payload)

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
            throw LLMError.apiKeyMissing(provider: "OpenAI")
        case 404:
            throw LLMError.modelNotFound(name: model ?? defaultModel.rawValue)
        case 429:
            // Parse retry-after header if available
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Double($0) }
            throw LLMError.rateLimited(retryAfter: retryAfter)
        default:
            let errorMessage = parseErrorMessage(from: data) ?? "Unknown error"
            throw LLMError.apiError(code: httpResponse.statusCode, message: errorMessage)
        }

        // Parse response
        let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let choice = chatResponse.choices.first else {
            throw LLMError.unknown("No choices in response")
        }

        return choice.message.content
    }

    // MARK: - Private Methods

    private func parseErrorMessage(from data: Data) -> String? {
        struct ErrorResponse: Decodable {
            let error: ErrorDetail

            struct ErrorDetail: Decodable {
                let message: String
            }
        }

        return try? JSONDecoder().decode(ErrorResponse.self, from: data).error.message
    }
}

// MARK: - Request/Response Types

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [[String: String]]
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let role: String
        let content: String
    }
}
