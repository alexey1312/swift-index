// MARK: - LLMProviderFactory

import Foundation

/// Factory for creating LLM providers from configuration.
///
/// ## Usage
///
/// ```swift
/// let config = SearchEnhancementConfig.default
/// let utilityProvider = try LLMProviderFactory.createProvider(from: config.utility)
/// let synthesisProvider = try LLMProviderFactory.createProvider(from: config.synthesis)
/// ```
public enum LLMProviderFactory {
    // MARK: - Provider IDs

    /// Known provider identifiers.
    public enum ProviderID: String, CaseIterable {
        case anthropic
        case claudeCodeCLI = "claude-code-cli"
        case codexCLI = "codex-cli"
        case ollama
        case openai
        case mlx
        case gemini
        case geminiCLI = "gemini-cli"
    }

    // MARK: - Factory Methods

    /// Creates an LLM provider from tier configuration.
    ///
    /// - Parameters:
    ///   - config: The tier configuration.
    ///   - openAIKey: OpenAI API key (for openai provider).
    ///   - anthropicKey: Anthropic API key (for anthropic provider).
    /// - Returns: An LLM provider instance.
    /// - Throws: `LLMError.notAvailable` if provider is unknown.
    public static func createProvider(
        from config: LLMTierConfig,
        openAIKey: String? = nil,
        anthropicKey: String? = nil
    ) throws -> any LLMProvider {
        guard let providerID = ProviderID(rawValue: config.provider) else {
            throw LLMError.notAvailable(
                reason: "Unknown provider: \(config.provider). " +
                    "Supported: \(ProviderID.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }

        return createProvider(
            id: providerID,
            model: config.model,
            openAIKey: openAIKey,
            anthropicKey: anthropicKey
        )
    }

    /// Creates an LLM provider by ID.
    ///
    /// - Parameters:
    ///   - id: The provider identifier.
    ///   - model: Optional model override.
    ///   - openAIKey: OpenAI API key (for openai provider).
    ///   - anthropicKey: Anthropic API key (for anthropic provider).
    /// - Returns: An LLM provider instance.
    public static func createProvider(
        id: ProviderID,
        model: String? = nil,
        openAIKey: String? = nil,
        anthropicKey: String? = nil
    ) -> any LLMProvider {
        switch id {
        case .anthropic:
            // Priority chain for Anthropic authentication:
            // 1. Explicit anthropicKey parameter (from config/CLI)
            // 2. SWIFTINDEX_ANTHROPIC_API_KEY (project-specific)
            // 3. CLAUDE_CODE_OAUTH_TOKEN (auto-set by Claude Code CLI)
            // 4. ANTHROPIC_API_KEY (standard API key)
            // 5. Keychain OAuth Token (managed via `swiftindex auth`)
            let key = anthropicKey
                ?? ProcessInfo.processInfo.environment["SWIFTINDEX_ANTHROPIC_API_KEY"]
                ?? ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"]
                ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
                ?? {
                    #if canImport(Security)
                        return try? ClaudeCodeAuthManager.getToken()
                    #else
                        return nil
                    #endif
                }()
                ?? ""

            return AnthropicLLMProvider(
                apiKey: key,
                defaultModel: .haiku
            )

        case .claudeCodeCLI:
            return ClaudeCodeCLIProvider(defaultModel: model)

        case .codexCLI:
            return CodexCLIProvider(defaultModel: model)

        case .ollama:
            return OllamaLLMProvider(defaultModel: model ?? "llama3.2")

        case .openai:
            let key = openAIKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
            let defaultModel: OpenAILLMProvider.Model = .gpt4oMini
            return OpenAILLMProvider(
                apiKey: key,
                defaultModel: defaultModel
            )

        case .mlx:
            if let modelId = model {
                return MLXLLMProvider(huggingFaceId: modelId)
            }
            return MLXLLMProvider()

        case .gemini:
            let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
            return GeminiLLMProvider(apiKey: key, defaultModel: model ?? "gemini-1.5-flash")

        case .geminiCLI:
            return GeminiCLIProvider(defaultModel: model)
        }
    }

    /// Creates an LLM provider chain from search enhancement configuration.
    ///
    /// - Parameters:
    ///   - config: The search enhancement configuration.
    ///   - tier: Which tier to create the chain for.
    ///   - openAIKey: OpenAI API key.
    ///   - anthropicKey: Anthropic API key.
    /// - Returns: An LLM provider chain with fallbacks.
    public static func createChain(
        from config: SearchEnhancementConfig,
        tier: Tier,
        openAIKey: String? = nil,
        anthropicKey: String? = nil
    ) -> LLMProviderChain {
        let tierConfig = tier == .utility ? config.utility : config.synthesis

        // Create primary provider
        let primary: any LLMProvider
        do {
            primary = try createProvider(from: tierConfig, openAIKey: openAIKey, anthropicKey: anthropicKey)
        } catch {
            // Fall back to MLX (matches LLMTierConfig.defaultUtility/defaultSynthesis)
            primary = MLXLLMProvider()
        }

        // Add fallbacks based on availability
        var providers: [any LLMProvider] = [primary]

        // Add Ollama as a fallback if not already primary
        if tierConfig.provider != ProviderID.ollama.rawValue {
            providers.append(OllamaLLMProvider())
        }

        return LLMProviderChain(
            providers: providers,
            id: "\(tier.rawValue)-chain",
            name: "\(tier.rawValue.capitalized) LLM Chain"
        )
    }

    // MARK: - Tier

    /// LLM tier type.
    public enum Tier: String {
        case utility
        case synthesis
    }
}
