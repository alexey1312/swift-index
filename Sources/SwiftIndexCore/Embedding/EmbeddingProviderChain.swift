// MARK: - EmbeddingProviderChain

import Foundation

/// A chain of embedding providers with automatic fallback.
///
/// The chain tries providers in order until one succeeds. This enables
/// graceful degradation from hardware-accelerated providers (MLX) to
/// pure software implementations (swift-embeddings).
///
/// ## Usage
///
/// ```swift
/// let chain = EmbeddingProviderChain.default
///
/// // Automatically uses best available provider
/// let embedding = try await chain.embed("Hello, world!")
/// ```
///
/// ## Provider Order
///
/// The default chain prioritizes local, privacy-first providers:
/// 1. **MLX** - Apple Silicon native, fastest when available
/// 2. **Swift Embeddings** - Pure Swift fallback, always available
///
/// ## Thread Safety
///
/// The chain is thread-safe and can be used from multiple tasks concurrently.
/// Each provider manages its own internal synchronization.
public final class EmbeddingProviderChain: EmbeddingProvider, @unchecked Sendable {
    // MARK: - Properties

    public let id: String
    public let name: String
    public var dimension: Int {
        // Return dimension of first available provider
        // Falls back to default dimension if no providers configured
        providers.first?.dimension ?? 384
    }

    private let providers: [any EmbeddingProvider]

    /// The currently active provider (cached after first successful use).
    private let activeProviderManager: ActiveProviderManager

    // MARK: - Initialization

    /// Creates a chain with the specified providers.
    ///
    /// - Parameters:
    ///   - providers: Array of providers in priority order (first = highest).
    ///   - id: Unique identifier for this chain.
    ///   - name: Human-readable name.
    public init(
        providers: [any EmbeddingProvider],
        id: String = "chain",
        name: String = "Embedding Provider Chain"
    ) {
        self.providers = providers
        self.id = id
        self.name = name
        self.activeProviderManager = ActiveProviderManager()
    }

    /// Creates the default provider chain optimized for local-first operation.
    ///
    /// Provider order:
    /// 1. MLXEmbeddingProvider (Apple Silicon)
    /// 2. SwiftEmbeddingsProvider (Pure Swift fallback)
    public static var `default`: EmbeddingProviderChain {
        EmbeddingProviderChain(
            providers: [
                MLXEmbeddingProvider(),
                SwiftEmbeddingsProvider()
            ],
            id: "default-chain",
            name: "Default Embedding Chain"
        )
    }

    /// Creates a chain using only pure Swift providers (no hardware dependencies).
    public static var softwareOnly: EmbeddingProviderChain {
        EmbeddingProviderChain(
            providers: [
                SwiftEmbeddingsProvider()
            ],
            id: "software-chain",
            name: "Software-Only Chain"
        )
    }

    // MARK: - EmbeddingProvider

    public func isAvailable() async -> Bool {
        // Chain is available if any provider is available
        for provider in providers {
            if await provider.isAvailable() {
                return true
            }
        }
        return false
    }

    public func embed(_ text: String) async throws -> [Float] {
        // Try cached active provider first
        if let active = await activeProviderManager.activeProvider {
            do {
                return try await active.embed(text)
            } catch {
                // Active provider failed, clear cache and try others
                await activeProviderManager.clearActiveProvider()
            }
        }

        // Try providers in order
        var errors: [String: ProviderError] = [:]

        for provider in providers {
            guard await provider.isAvailable() else {
                errors[provider.id] = .notAvailable(reason: "Provider reported unavailable")
                continue
            }

            do {
                let result = try await provider.embed(text)
                // Cache successful provider
                await activeProviderManager.setActiveProvider(provider)
                return result
            } catch let error as ProviderError {
                errors[provider.id] = error
            } catch {
                errors[provider.id] = .unknown(error.localizedDescription)
            }
        }

        throw ProviderError.allProvidersFailed(errors)
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else {
            return []
        }

        // Try cached active provider first
        if let active = await activeProviderManager.activeProvider {
            do {
                return try await active.embed(texts)
            } catch {
                // Active provider failed, clear cache and try others
                await activeProviderManager.clearActiveProvider()
            }
        }

        // Try providers in order
        var errors: [String: ProviderError] = [:]

        for provider in providers {
            guard await provider.isAvailable() else {
                errors[provider.id] = .notAvailable(reason: "Provider reported unavailable")
                continue
            }

            do {
                let result = try await provider.embed(texts)
                // Cache successful provider
                await activeProviderManager.setActiveProvider(provider)
                return result
            } catch let error as ProviderError {
                errors[provider.id] = error
            } catch {
                errors[provider.id] = .unknown(error.localizedDescription)
            }
        }

        throw ProviderError.allProvidersFailed(errors)
    }

    // MARK: - Chain Management

    /// Returns the currently active provider, if any.
    public func activeProvider() async -> (any EmbeddingProvider)? {
        await activeProviderManager.activeProvider
    }

    /// Clears the cached active provider, forcing re-evaluation on next call.
    public func resetActiveProvider() async {
        await activeProviderManager.clearActiveProvider()
    }

    /// Returns all providers in the chain.
    public var allProviders: [any EmbeddingProvider] {
        providers
    }

    /// Returns the first available provider without caching.
    public func firstAvailableProvider() async -> (any EmbeddingProvider)? {
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

// MARK: - ActiveProviderManager

/// Actor managing the cached active provider.
private actor ActiveProviderManager {
    var activeProvider: (any EmbeddingProvider)?

    func setActiveProvider(_ provider: any EmbeddingProvider) {
        activeProvider = provider
    }

    func clearActiveProvider() {
        activeProvider = nil
    }
}

// MARK: - Builder

extension EmbeddingProviderChain {
    /// Builder for constructing custom provider chains.
    public final class Builder: @unchecked Sendable {
        private var providers: [any EmbeddingProvider] = []
        private var chainId: String = "custom-chain"
        private var chainName: String = "Custom Embedding Chain"

        public init() {}

        /// Adds a provider to the chain.
        @discardableResult
        public func add(_ provider: any EmbeddingProvider) -> Builder {
            providers.append(provider)
            return self
        }

        /// Adds the MLX provider if available on Apple Silicon.
        @discardableResult
        public func addMLX(
            modelName: String = "bge-small-en-v1.5",
            dimension: Int = 384
        ) -> Builder {
            #if arch(arm64) && os(macOS)
            providers.append(MLXEmbeddingProvider(modelName: modelName, dimension: dimension))
            #endif
            return self
        }

        /// Adds the Swift embeddings provider.
        @discardableResult
        public func addSwiftEmbeddings(
            model: SwiftEmbeddingsProvider.Model = .bgeSmall
        ) -> Builder {
            providers.append(SwiftEmbeddingsProvider(model: model))
            return self
        }

        /// Adds the Ollama provider for local server embeddings.
        @discardableResult
        public func addOllama(
            baseURL: URL = URL(string: "http://localhost:11434")!,
            modelName: String = "nomic-embed-text",
            dimension: Int = 768
        ) -> Builder {
            providers.append(OllamaEmbeddingProvider(
                baseURL: baseURL,
                modelName: modelName,
                dimension: dimension
            ))
            return self
        }

        /// Adds the Voyage AI provider for cloud embeddings.
        @discardableResult
        public func addVoyage(
            apiKey: String,
            modelName: String = "voyage-code-2",
            dimension: Int = 1024
        ) -> Builder {
            guard !apiKey.isEmpty else { return self }
            providers.append(VoyageProvider(
                apiKey: apiKey,
                modelName: modelName,
                dimension: dimension
            ))
            return self
        }

        /// Adds the OpenAI provider for cloud embeddings.
        @discardableResult
        public func addOpenAI(
            apiKey: String,
            model: OpenAIProvider.Model = .textEmbedding3Small,
            dimension: Int? = nil
        ) -> Builder {
            guard !apiKey.isEmpty else { return self }
            providers.append(OpenAIProvider(
                apiKey: apiKey,
                model: model,
                dimension: dimension
            ))
            return self
        }

        /// Sets the chain identifier.
        @discardableResult
        public func id(_ id: String) -> Builder {
            self.chainId = id
            return self
        }

        /// Sets the chain name.
        @discardableResult
        public func name(_ name: String) -> Builder {
            self.chainName = name
            return self
        }

        /// Builds the provider chain.
        public func build() -> EmbeddingProviderChain {
            EmbeddingProviderChain(
                providers: providers,
                id: chainId,
                name: chainName
            )
        }
    }
}

// MARK: - Convenience Extensions

extension EmbeddingProviderChain {
    /// Creates a chain with a single provider.
    public static func single(_ provider: any EmbeddingProvider) -> EmbeddingProviderChain {
        EmbeddingProviderChain(
            providers: [provider],
            id: "single-\(provider.id)",
            name: provider.name
        )
    }

    /// Creates a chain from a builder configuration.
    public static func build(
        _ configure: (Builder) -> Void
    ) -> EmbeddingProviderChain {
        let builder = Builder()
        configure(builder)
        return builder.build()
    }
}
