// MARK: - LLMMessage Model

import Foundation

/// A message in an LLM conversation.
///
/// Messages represent the conversation history sent to an LLM provider.
/// Each message has a role (system, user, or assistant) and content.
///
/// ## Usage
///
/// ```swift
/// let messages: [LLMMessage] = [
///     .system("You are a helpful code assistant."),
///     .user("Explain what this function does."),
/// ]
///
/// let response = try await provider.complete(messages: messages)
/// ```
public struct LLMMessage: Sendable, Equatable, Codable {
    // MARK: - Properties

    /// The role of the message sender.
    public let role: Role

    /// The content of the message.
    public let content: String

    // MARK: - Role

    /// The role of a message sender in a conversation.
    public enum Role: String, Sendable, Equatable, Codable {
        /// System message providing instructions or context.
        case system

        /// User message (human input).
        case user

        /// Assistant message (model response).
        case assistant
    }

    // MARK: - Initialization

    /// Creates a message with the specified role and content.
    ///
    /// - Parameters:
    ///   - role: The role of the message sender.
    ///   - content: The content of the message.
    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    // MARK: - Convenience Initializers

    /// Creates a system message.
    ///
    /// System messages typically provide instructions or context
    /// for how the model should behave.
    ///
    /// - Parameter content: The system instruction content.
    /// - Returns: A new system message.
    public static func system(_ content: String) -> LLMMessage {
        LLMMessage(role: .system, content: content)
    }

    /// Creates a user message.
    ///
    /// User messages represent human input in the conversation.
    ///
    /// - Parameter content: The user's input content.
    /// - Returns: A new user message.
    public static func user(_ content: String) -> LLMMessage {
        LLMMessage(role: .user, content: content)
    }

    /// Creates an assistant message.
    ///
    /// Assistant messages represent previous model responses,
    /// useful for multi-turn conversations.
    ///
    /// - Parameter content: The assistant's response content.
    /// - Returns: A new assistant message.
    public static func assistant(_ content: String) -> LLMMessage {
        LLMMessage(role: .assistant, content: content)
    }
}

// MARK: - CustomStringConvertible

extension LLMMessage: CustomStringConvertible {
    public var description: String {
        "[\(role.rawValue)] \(content.prefix(50))\(content.count > 50 ? "..." : "")"
    }
}

// MARK: - Array Extension

public extension [LLMMessage] {
    /// Estimates the token count for the message array.
    ///
    /// Uses a simple approximation of ~4 characters per token.
    /// This is suitable for context window estimation but not exact.
    var estimatedTokenCount: Int {
        let totalCharacters = reduce(0) { $0 + $1.content.count }
        return totalCharacters / 4
    }

    /// Creates a simple conversation with a system prompt and user query.
    ///
    /// - Parameters:
    ///   - systemPrompt: The system instruction.
    ///   - userQuery: The user's query.
    /// - Returns: An array with system and user messages.
    static func conversation(
        system systemPrompt: String,
        user userQuery: String
    ) -> [LLMMessage] {
        [
            .system(systemPrompt),
            .user(userQuery),
        ]
    }
}
