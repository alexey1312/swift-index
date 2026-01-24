// MARK: - GeminiLLMProvider

import Foundation

/// LLM provider that uses Google's Gemini API.
///
/// Requires an API key from Google AI Studio: https://aistudio.google.com/
public struct GeminiLLMProvider: LLMProvider, Sendable {
    // MARK: - Properties

    public let id: String = "gemini"
    public let name: String = "Gemini API"

    private let apiKey: String
    private let defaultModel: String
    private let session: URLSession

    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    // MARK: - Initialization

    public init(
        apiKey: String,
        defaultModel: String = "gemini-1.5-flash"
    ) {
        self.apiKey = apiKey
        self.defaultModel = defaultModel

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config)
    }

    // MARK: - LLMProvider

    public func isAvailable() async -> Bool {
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

        let modelName = model ?? defaultModel
        let endpoint = "\(Self.baseURL)/models/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidInput("Invalid Gemini API URL")
        }

        // Convert messages to Gemini format
        let contents = messages.compactMap { msg -> GeminiLLMContent? in
            let role = msg.role == .user ? "user" : (msg.role == .assistant ? "model" : nil)
            // Skip system messages for contents array (Gemini handles system separately)
            guard let role else { return nil }
            return GeminiLLMContent(role: role, parts: [GeminiLLMPart(text: msg.content)])
        }

        // Find system message
        let systemInstruction = messages.first { $0.role == .system }.map {
            GeminiSystemInstruction(parts: [GeminiLLMPart(text: $0.content)])
        }

        let payload = GeminiLLMRequest(
            contents: contents,
            systemInstruction: systemInstruction
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = try JSONCodec.makeEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.unknown("Invalid response type")
        }

        guard httpResponse.statusCode == 200 else {
            let error = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw LLMError.unknown("Gemini API error: \(error)")
        }

        let result = try JSONCodec.makeDecoder().decode(GeminiLLMResponse.self, from: data)
        guard let firstText = result.candidates.first?.content.parts.first?.text else {
            throw LLMError.unknown("Empty response from Gemini")
        }

        return firstText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Request/Response Types

private struct GeminiLLMRequest: Encodable {
    let contents: [GeminiLLMContent]
    let systemInstruction: GeminiSystemInstruction?
}

private struct GeminiSystemInstruction: Encodable {
    let parts: [GeminiLLMPart]
}

private struct GeminiLLMContent: Codable {
    let role: String
    let parts: [GeminiLLMPart]
}

private struct GeminiLLMPart: Codable {
    let text: String
}

private struct GeminiLLMResponse: Decodable {
    let candidates: [GeminiCandidate]

    struct GeminiCandidate: Decodable {
        let content: GeminiLLMContent
    }
}
