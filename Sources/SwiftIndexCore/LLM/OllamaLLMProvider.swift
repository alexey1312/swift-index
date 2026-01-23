// MARK: - OllamaLLMProvider

import Foundation

/// LLM provider that uses a local Ollama server for text generation.
///
/// Ollama provides a simple way to run LLMs locally. This provider
/// connects to the Ollama API to generate completions.
///
/// ## Prerequisites
///
/// 1. Install Ollama: `brew install ollama`
/// 2. Start Ollama: `ollama serve`
/// 3. Pull a model: `ollama pull llama3.2`
///
/// ## Usage
///
/// ```swift
/// let provider = OllamaLLMProvider()
/// if await provider.isAvailable() {
///     let response = try await provider.complete(messages: [
///         .user("What is the capital of France?")
///     ])
/// }
/// ```
public struct OllamaLLMProvider: LLMProvider, Sendable {
    // MARK: - Properties

    public let id: String = "ollama"
    public let name: String = "Ollama LLM Provider"

    /// The base URL of the Ollama server.
    public let baseURL: URL

    /// The default model to use for completions.
    public let defaultModel: String

    /// URL session for making requests.
    private let session: URLSession

    // MARK: - Initialization

    /// Creates an Ollama LLM provider.
    ///
    /// - Parameters:
    ///   - baseURL: Base URL of the Ollama server. Default is `http://localhost:11434`.
    ///   - defaultModel: Default model for completions. Default is `llama3.2`.
    public init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        defaultModel: String = "llama3.2"
    ) {
        self.baseURL = baseURL
        self.defaultModel = defaultModel

        // Configure session with reasonable timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
    }

    // MARK: - LLMProvider

    public func isAvailable() async -> Bool {
        // Check if Ollama server is running
        let versionURL = baseURL.appendingPathComponent("api/version")

        do {
            var request = URLRequest(url: versionURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 5

            let (_, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }

    public func complete(
        messages: [LLMMessage],
        model: String?,
        timeout: TimeInterval
    ) async throws -> String {
        guard !messages.isEmpty else {
            throw LLMError.invalidInput("Messages cannot be empty")
        }

        let chatURL = baseURL.appendingPathComponent("api/chat")

        // Build request
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        // Convert messages to Ollama format
        let ollamaMessages = messages.map { message -> [String: String] in
            [
                "role": message.role.rawValue,
                "content": message.content,
            ]
        }

        let payload = ChatRequest(
            model: model ?? defaultModel,
            messages: ollamaMessages,
            stream: false
        )

        request.httpBody = try JSONEncoder().encode(payload)

        // Make request
        let (data, response) = try await session.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError("Invalid response type")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 404 {
                throw LLMError.modelNotFound(name: model ?? defaultModel)
            }
            throw LLMError.apiError(code: httpResponse.statusCode, message: errorMessage)
        }

        // Parse response
        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        return chatResponse.message.content
    }
}

// MARK: - Request/Response Types

private struct ChatRequest: Encodable {
    let model: String
    let messages: [[String: String]]
    let stream: Bool
}

private struct ChatResponse: Decodable {
    let message: Message

    struct Message: Decodable {
        let role: String
        let content: String
    }
}
