// MARK: - LLMProviderChain

import Foundation

/// A chain of LLM providers with automatic fallback.
///
/// The chain tries providers in order until one succeeds. This enables
/// graceful degradation from preferred providers (e.g., Claude Code CLI)
/// to fallback options (e.g., Ollama, OpenAI API).
///
/// ## Usage
///
/// ```swift
/// let chain = LLMProviderChain(providers: [
///     ClaudeCodeCLIProvider(),
///     OllamaLLMProvider(),
/// ])
///
/// // Automatically uses best available provider
/// let response = try await chain.complete(messages: [
///     .user("Expand this search query: swift async")
/// ])
/// ```
///
/// ## Thread Safety
///
/// The chain is thread-safe and can be used from multiple tasks concurrently.
/// Each provider manages its own internal synchronization.
public final class LLMProviderChain: LLMProvider, @unchecked Sendable {
    // MARK: - Properties

    public let id: String
    public let name: String

    private let providers: [any LLMProvider]

    /// The currently active provider (cached after first successful use).
    private let activeProviderManager: ActiveLLMProviderManager

    // MARK: - Initialization

    /// Creates a chain with the specified providers.
    ///
    /// - Parameters:
    ///   - providers: Array of providers in priority order (first = highest).
    ///   - id: Unique identifier for this chain.
    ///   - name: Human-readable name.
    public init(
        providers: [any LLMProvider],
        id: String = "llm-chain",
        name: String = "LLM Provider Chain"
    ) {
        self.providers = providers
        self.id = id
        self.name = name
        activeProviderManager = ActiveLLMProviderManager()
    }

    // MARK: - LLMProvider

    public func isAvailable() async -> Bool {
        // Chain is available if any provider is available
        for provider in providers {
            if await provider.isAvailable() {
                return true
            }
        }
        return false
    }

    public func complete(
        messages: [LLMMessage],
        model: String?,
        timeout: TimeInterval
    ) async throws -> String {
        guard !messages.isEmpty else {
            throw LLMError.invalidInput("Messages cannot be empty")
        }

        // Try cached active provider first
        if let active = await activeProviderManager.activeProvider {
            do {
                return try await active.complete(
                    messages: messages,
                    model: model,
                    timeout: timeout
                )
            } catch {
                // Active provider failed, clear cache and try others
                await activeProviderManager.clearActiveProvider()
            }
        }

        // Try providers in order
        var errors: [String: LLMError] = [:]

        for provider in providers {
            guard await provider.isAvailable() else {
                errors[provider.id] = .notAvailable(reason: "Provider reported unavailable")
                continue
            }

            do {
                let result = try await provider.complete(
                    messages: messages,
                    model: model,
                    timeout: timeout
                )
                // Cache successful provider
                await activeProviderManager.setActiveProvider(provider)
                return result
            } catch let error as LLMError {
                errors[provider.id] = error
            } catch {
                errors[provider.id] = .unknown(error.localizedDescription)
            }
        }

        throw LLMError.allProvidersFailed(errors)
    }

    // MARK: - Chain Management

    /// Returns the currently active provider, if any.
    public func activeProvider() async -> (any LLMProvider)? {
        await activeProviderManager.activeProvider
    }

    /// Clears the cached active provider, forcing re-evaluation on next call.
    public func resetActiveProvider() async {
        await activeProviderManager.clearActiveProvider()
    }

    /// Returns all providers in the chain.
    public var allProviders: [any LLMProvider] {
        providers
    }

    /// Returns the first available provider without caching.
    public func firstAvailableProvider() async -> (any LLMProvider)? {
        for provider in providers {
            if await provider.isAvailable() {
                return provider
            }
        }
        return nil
    }

    /// Checks availability of all providers.
    ///
    /// - Returns: Dictionary mapping provider IDs to their availability status.
    public func checkAllProviders() async -> [String: Bool] {
        var results: [String: Bool] = [:]

        await withTaskGroup(of: (String, Bool).self) { group in
            for provider in providers {
                group.addTask {
                    let available = await provider.isAvailable()
                    return (provider.id, available)
                }
            }

            for await (id, available) in group {
                results[id] = available
            }
        }

        return results
    }
}

// MARK: - ActiveLLMProviderManager

/// Actor managing the cached active LLM provider.
private actor ActiveLLMProviderManager {
    var activeProvider: (any LLMProvider)?

    func setActiveProvider(_ provider: any LLMProvider) {
        activeProvider = provider
    }

    func clearActiveProvider() {
        activeProvider = nil
    }
}

// MARK: - Builder

public extension LLMProviderChain {
    /// Builder for constructing custom LLM provider chains.
    final class Builder: @unchecked Sendable {
        private var providers: [any LLMProvider] = []
        private var chainId: String = "custom-llm-chain"
        private var chainName: String = "Custom LLM Chain"

        public init() {}

        /// Adds a provider to the chain.
        @discardableResult
        public func add(_ provider: any LLMProvider) -> Builder {
            providers.append(provider)
            return self
        }

        /// Sets the chain identifier.
        @discardableResult
        public func id(_ id: String) -> Builder {
            chainId = id
            return self
        }

        /// Sets the chain name.
        @discardableResult
        public func name(_ name: String) -> Builder {
            chainName = name
            return self
        }

        /// Builds the provider chain.
        public func build() -> LLMProviderChain {
            LLMProviderChain(
                providers: providers,
                id: chainId,
                name: chainName
            )
        }
    }
}

// MARK: - Convenience Extensions

public extension LLMProviderChain {
    /// Creates a chain with a single provider.
    static func single(_ provider: any LLMProvider) -> LLMProviderChain {
        LLMProviderChain(
            providers: [provider],
            id: "single-\(provider.id)",
            name: provider.name
        )
    }

    /// Creates a chain from a builder configuration.
    static func build(
        _ configure: (Builder) -> Void
    ) -> LLMProviderChain {
        let builder = Builder()
        configure(builder)
        return builder.build()
    }
}
