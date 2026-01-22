// MARK: - EmbeddingProviderRegistry

import Foundation

/// Information about an embedding provider's status and capabilities.
public struct ProviderInfo: Sendable, Equatable {
    /// Unique identifier for the provider.
    public let id: String

    /// Human-readable name.
    public let name: String

    /// Vector dimension produced by this provider.
    public let dimension: Int

    /// Whether the provider is currently available.
    public let isAvailable: Bool

    /// Additional notes about the provider (requirements, limitations).
    public let notes: String

    /// The provider type (local or cloud).
    public let providerType: ProviderType

    /// Model identifier if applicable.
    public let modelId: String?

    public init(
        id: String,
        name: String,
        dimension: Int,
        isAvailable: Bool,
        notes: String,
        providerType: ProviderType,
        modelId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.dimension = dimension
        self.isAvailable = isAvailable
        self.notes = notes
        self.providerType = providerType
        self.modelId = modelId
    }

    /// Provider execution type.
    public enum ProviderType: String, Sendable, Equatable {
        case local
        case cloud
    }
}

/// Registry of available embedding providers with availability checking.
///
/// The registry creates provider instances based on the current configuration
/// and checks their availability. Use this to list all providers and their
/// status for the CLI `providers` command.
///
/// ## Usage
///
/// ```swift
/// let registry = EmbeddingProviderRegistry(config: config)
/// let providers = await registry.allProviders()
///
/// for info in providers {
///     print("\(info.isAvailable ? "✓" : "○") \(info.name)")
/// }
/// ```
public struct EmbeddingProviderRegistry: Sendable {
    /// The configuration used to create providers.
    public let config: Config

    /// Creates a registry with the given configuration.
    ///
    /// - Parameter config: Configuration containing API keys and provider settings.
    public init(config: Config) {
        self.config = config
    }

    /// Returns information about all registered providers.
    ///
    /// Checks availability of each provider concurrently.
    ///
    /// - Returns: Array of provider information, sorted by priority (local first).
    public func allProviders() async -> [ProviderInfo] {
        let providers = createProviders()

        // Check availability concurrently
        return await withTaskGroup(of: ProviderInfo.self, returning: [ProviderInfo].self) { group in
            for (provider, notes, type, modelId) in providers {
                group.addTask {
                    let available = await provider.isAvailable()
                    return ProviderInfo(
                        id: provider.id,
                        name: provider.name,
                        dimension: provider.dimension,
                        isAvailable: available,
                        notes: notes,
                        providerType: type,
                        modelId: modelId
                    )
                }
            }

            var results: [ProviderInfo] = []
            for await info in group {
                results.append(info)
            }

            // Sort by type (local first) then by id for consistent ordering
            return results.sorted { lhs, rhs in
                if lhs.providerType != rhs.providerType {
                    return lhs.providerType == .local
                }
                return lhs.id < rhs.id
            }
        }
    }

    /// Returns the first available provider.
    ///
    /// - Returns: The first provider that reports availability, or nil if none available.
    public func firstAvailable() async -> (any EmbeddingProvider)? {
        let providers = createProviders()

        for (provider, _, _, _) in providers {
            if await provider.isAvailable() {
                return provider
            }
        }
        return nil
    }

    /// Returns a provider by ID.
    ///
    /// - Parameter id: The provider identifier.
    /// - Returns: The provider if found and available, nil otherwise.
    public func provider(id: String) async -> (any EmbeddingProvider)? {
        let providers = createProviders()

        for (provider, _, _, _) in providers where provider.id == id {
            if await provider.isAvailable() {
                return provider
            }
            return nil
        }
        return nil
    }

    // MARK: - Private

    /// Creates all provider instances with their metadata.
    ///
    /// Returns tuple of (provider, notes, type, modelId).
    private func createProviders() -> [(any EmbeddingProvider, String, ProviderInfo.ProviderType, String?)] {
        var providers: [(any EmbeddingProvider, String, ProviderInfo.ProviderType, String?)] = []

        // MLX Provider (Apple Silicon)
        let mlxProvider = MLXEmbeddingProvider()
        providers.append((
            mlxProvider,
            "Local, Apple Silicon required",
            .local,
            "nomic-ai/nomic-embed-text-v1.5"
        ))

        // Swift Embeddings Provider (Pure Swift)
        let swiftProvider = SwiftEmbeddingsProvider()
        providers.append((
            swiftProvider,
            "Local, macOS 15.0+ required",
            .local,
            "sentence-transformers/all-MiniLM-L6-v2"
        ))

        // Ollama Provider
        let ollamaProvider = OllamaEmbeddingProvider()
        providers.append((
            ollamaProvider,
            "Local server, requires ollama running",
            .local,
            "nomic-embed-text"
        ))

        // Voyage Provider (Cloud)
        if let apiKey = config.voyageAPIKey, !apiKey.isEmpty {
            let voyageProvider = VoyageProvider(apiKey: apiKey)
            providers.append((
                voyageProvider,
                "Cloud, API key configured",
                .cloud,
                "voyage-code-2"
            ))
        } else {
            // Create placeholder for listing (will show unavailable)
            let voyageProvider = VoyageProvider(apiKey: "")
            providers.append((
                voyageProvider,
                "Cloud, API key required (VOYAGE_API_KEY)",
                .cloud,
                "voyage-code-2"
            ))
        }

        // OpenAI Provider (Cloud)
        if let apiKey = config.openAIAPIKey, !apiKey.isEmpty {
            let openAIProvider = OpenAIProvider(apiKey: apiKey)
            providers.append((
                openAIProvider,
                "Cloud, API key configured",
                .cloud,
                "text-embedding-3-small"
            ))
        } else {
            // Create placeholder for listing (will show unavailable)
            let openAIProvider = OpenAIProvider(apiKey: "")
            providers.append((
                openAIProvider,
                "Cloud, API key required (OPENAI_API_KEY)",
                .cloud,
                "text-embedding-3-small"
            ))
        }

        return providers
    }
}
