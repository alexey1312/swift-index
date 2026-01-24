// MARK: - MLXLLMProvider

import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// LLM provider using Apple MLX for local text generation on Apple Silicon.
///
/// This provider uses MLX's efficient Metal-based computation to run LLMs
/// locally without requiring cloud APIs. Best for privacy-sensitive use cases
/// and offline operation.
///
/// ## Prerequisites
///
/// - Apple Silicon Mac (M1 or later)
/// - macOS 14.0+
/// - First run downloads model from HuggingFace (~2-7GB depending on model)
///
/// ## Models
///
/// Default models (4-bit quantized for efficiency):
/// - `mlx-community/Qwen3-4B-4bit` (default, good balance)
/// - `mlx-community/SmolLM-135M-Instruct-4bit` (ultra-fast, basic)
/// - `mlx-community/Llama-3.2-1B-Instruct-4bit` (compact, capable)
///
/// ## Usage
///
/// ```swift
/// let provider = MLXLLMProvider()
/// if await provider.isAvailable() {
///     let response = try await provider.complete(messages: [
///         .system("You are a helpful assistant."),
///         .user("Explain what this function does.")
///     ])
/// }
/// ```
///
/// ## Configuration
///
/// ```toml
/// [search.enhancement.utility]
/// provider = "mlx"
/// model = "mlx-community/Qwen3-4B-4bit"  # optional
/// timeout = 60
/// ```
public final class MLXLLMProvider: LLMProvider, @unchecked Sendable {
    // MARK: - Properties

    public let id: String = "mlx"
    public let name: String = "MLX LLM Provider"

    private let defaultModelId: String
    private let maxTokens: Int
    private let modelManager: MLXLLMModelManager

    // MARK: - Supported Models

    /// Pre-configured MLX LLM models (4-bit quantized).
    public enum Model: String, Sendable, CaseIterable {
        /// Qwen3 4B (default, good balance of quality/speed)
        case qwen3_4b = "Qwen3-4B-4bit"
        /// SmolLM 135M (ultra-fast, basic capabilities)
        case smolLM = "SmolLM-135M-Instruct-4bit"
        /// Llama 3.2 1B (compact, good for simple tasks)
        case llama32_1b = "Llama-3.2-1B-Instruct-4bit"
        /// Llama 3.2 3B (larger, better quality)
        case llama32_3b = "Llama-3.2-3B-Instruct-4bit"

        public var huggingFaceId: String {
            "mlx-community/\(rawValue)"
        }

        /// Recommended max tokens for this model.
        public var recommendedMaxTokens: Int {
            switch self {
            case .smolLM:
                256 // Smaller model, keep responses short
            case .qwen3_4b, .llama32_1b, .llama32_3b:
                512
            }
        }
    }

    // MARK: - Initialization

    /// Creates an MLX LLM provider with a specific model.
    ///
    /// - Parameters:
    ///   - model: The model to use (default: qwen3_4b).
    ///   - maxTokens: Maximum tokens to generate (default: model's recommendation).
    public init(model: Model = .qwen3_4b, maxTokens: Int? = nil) {
        defaultModelId = model.huggingFaceId
        self.maxTokens = maxTokens ?? model.recommendedMaxTokens
        modelManager = MLXLLMModelManager(defaultModelId: model.huggingFaceId)
    }

    /// Creates an MLX LLM provider with a custom HuggingFace model ID.
    ///
    /// - Parameters:
    ///   - huggingFaceId: The HuggingFace model ID.
    ///   - maxTokens: Maximum tokens to generate (default: 512).
    public init(huggingFaceId: String, maxTokens: Int = 512) {
        defaultModelId = huggingFaceId
        self.maxTokens = maxTokens
        modelManager = MLXLLMModelManager(defaultModelId: huggingFaceId)
    }

    // MARK: - LLMProvider

    public func isAvailable() async -> Bool {
        // Verify MLX can load the model
        do {
            _ = try await modelManager.ensureModelLoaded(modelId: defaultModelId)
            return true
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

        let modelId = model ?? defaultModelId

        // Run with timeout
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.modelManager.generate(
                    messages: messages,
                    modelId: modelId,
                    maxTokens: self.maxTokens
                )
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw LLMError.timeout(seconds: timeout)
            }

            guard let result = try await group.next() else {
                throw LLMError.unknown("No result from generation")
            }

            group.cancelAll()
            return result
        }
    }
}

// MARK: - MLXLLMModelManager Actor

/// Actor managing thread-safe MLX LLM model loading and text generation.
private actor MLXLLMModelManager {
    private let defaultModelId: String
    private var loadedContainers: [String: ModelContainer] = [:]

    init(defaultModelId: String) {
        self.defaultModelId = defaultModelId
    }

    func ensureModelLoaded(modelId: String) async throws -> ModelContainer {
        if let existing = loadedContainers[modelId] {
            return existing
        }

        let configuration = ModelConfiguration(id: modelId)
        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: configuration
        )
        loadedContainers[modelId] = container
        return container
    }

    func generate(
        messages: [LLMMessage],
        modelId: String,
        maxTokens: Int
    ) async throws -> String {
        let container = try await ensureModelLoaded(modelId: modelId)

        // Build prompt from messages using chat format
        let prompt = buildChatPrompt(from: messages)

        let result = try await container.perform { context in
            let userInput = UserInput(prompt: prompt)
            let lmInput = try await context.processor.prepare(input: userInput)

            let parameters = GenerateParameters(
                maxTokens: maxTokens,
                temperature: 0.7,
                topP: 0.95
            )

            // Use the AsyncStream-based API for better Swift concurrency support
            let stream = try MLXLMCommon.generate(
                input: lmInput,
                parameters: parameters,
                context: context
            )

            var fullText = ""
            for await generation in stream {
                switch generation {
                case let .chunk(text):
                    fullText += text
                case .info:
                    break // Generation complete
                case .toolCall:
                    break // Not used for text generation
                }
            }

            return fullText
        }

        return result
    }

    /// Builds a chat-style prompt from LLM messages.
    ///
    /// Uses a simple format that works across most models:
    /// ```
    /// System: <system message>
    ///
    /// User: <user message>
    ///
    /// Assistant:
    /// ```
    private func buildChatPrompt(from messages: [LLMMessage]) -> String {
        var prompt = ""

        for message in messages {
            switch message.role {
            case .system:
                prompt += "System: \(message.content)\n\n"
            case .user:
                prompt += "User: \(message.content)\n\n"
            case .assistant:
                prompt += "Assistant: \(message.content)\n\n"
            }
        }

        // Add final Assistant: to prompt for completion
        if messages.last?.role != .assistant {
            prompt += "Assistant:"
        }

        return prompt
    }
}
