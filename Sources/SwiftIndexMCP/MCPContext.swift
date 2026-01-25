// MARK: - MCP Context

import Foundation
import Logging
import SwiftIndexCore

/// Shared context for MCP tools.
///
/// Manages lazy initialization and caching of shared resources like
/// IndexManager, EmbeddingProvider, and configuration.
public actor MCPContext {
    // MARK: - Singleton

    /// Shared instance for MCP tools.
    public static let shared = MCPContext()

    // MARK: - Properties

    private var indexManagers: [String: IndexManager] = [:]
    private var embeddingProvider: EmbeddingProviderChain?
    private var loadedConfigs: [String: Config] = [:]
    private var llmProviders: (utility: LLMProviderChain?, synthesis: LLMProviderChain?)?
    private var queryExpander: QueryExpander?
    private var resultSynthesizer: ResultSynthesizer?
    private var followUpGenerator: FollowUpGenerator?
    private let logger = Logger(label: "MCPContext")

    // MARK: - Initialization

    private init() {}

    // MARK: - Testing Support

    /// Resets all cached state. For testing only.
    @_spi(Testing)
    public func resetForTesting() {
        indexManagers.removeAll()
        embeddingProvider = nil
        loadedConfigs.removeAll()
        llmProviders = nil
        queryExpander = nil
        resultSynthesizer = nil
        followUpGenerator = nil
    }

    // MARK: - Configuration

    /// Load or get cached configuration for a path.
    public func getConfig(for basePath: String) async throws -> Config {
        let resolvedPath = resolvePath(basePath)

        if let cached = loadedConfigs[resolvedPath] {
            return cached
        }

        // Load config using TOMLConfigLoader (handles layered config)
        let envConfig = (try? EnvironmentConfigLoader().load()) ?? .empty
        let config = try TOMLConfigLoader.loadLayered(env: envConfig, projectDirectory: resolvedPath)
        logger.debug("Loaded config for: \(resolvedPath)")

        loadedConfigs[resolvedPath] = config
        return config
    }

    // MARK: - Embedding Provider

    /// Get or create the embedding provider chain.
    public func getEmbeddingProvider(config: Config) async throws -> EmbeddingProviderChain {
        if let existing = embeddingProvider {
            return existing
        }

        let provider = try createEmbeddingProvider(config: config)
        embeddingProvider = provider
        return provider
    }

    private func createEmbeddingProvider(config: Config) throws -> EmbeddingProviderChain {
        switch config.embeddingProvider.lowercased() {
        case "mock":
            logger.debug("Creating mock embedding provider")
            return EmbeddingProviderChain(
                providers: [MockEmbeddingProvider()],
                id: "mock-chain",
                name: "Mock Embeddings"
            )

        case "mlx":
            logger.debug("Creating MLX embedding provider")
            return EmbeddingProviderChain(
                providers: [
                    MLXEmbeddingProvider(
                        huggingFaceId: config.embeddingModel,
                        dimension: config.embeddingDimension
                    ),
                    SwiftEmbeddingsProvider(),
                ],
                id: "mlx-chain",
                name: "MLX with Swift Embeddings fallback"
            )

        case "swift-embeddings", "swift", "swiftembeddings":
            logger.debug("Creating Swift Embeddings provider")
            return EmbeddingProviderChain.softwareOnly

        case "ollama":
            logger.debug("Creating Ollama embedding provider")
            return EmbeddingProviderChain(
                providers: [
                    OllamaEmbeddingProvider(
                        modelName: config.embeddingModel,
                        dimension: config.embeddingDimension
                    ),
                    SwiftEmbeddingsProvider(),
                ],
                id: "ollama-chain",
                name: "Ollama with fallback"
            )

        case "voyage":
            logger.debug("Creating Voyage AI embedding provider")
            if let apiKey = config.voyageAPIKey {
                return EmbeddingProviderChain(
                    providers: [
                        VoyageProvider(
                            apiKey: apiKey,
                            modelName: config.embeddingModel,
                            dimension: config.embeddingDimension
                        ),
                        SwiftEmbeddingsProvider(),
                    ],
                    id: "voyage-chain",
                    name: "Voyage AI with fallback"
                )
            } else {
                throw ProviderError.apiKeyMissing(provider: "Voyage AI")
            }

        case "openai":
            logger.debug("Creating OpenAI embedding provider")
            if let apiKey = config.openAIAPIKey {
                return EmbeddingProviderChain(
                    providers: [
                        OpenAIProvider(apiKey: apiKey),
                        SwiftEmbeddingsProvider(),
                    ],
                    id: "openai-chain",
                    name: "OpenAI with fallback"
                )
            } else {
                throw ProviderError.apiKeyMissing(provider: "OpenAI")
            }

        default:
            logger.debug("Using default provider chain")
            return EmbeddingProviderChain.default
        }
    }

    // MARK: - Index Manager

    /// Get or create an IndexManager for a given path.
    public func getIndexManager(for basePath: String, config: Config) async throws -> IndexManager {
        let resolvedPath = resolvePath(basePath)
        let indexPath = (resolvedPath as NSString).appendingPathComponent(config.indexPath)

        if let cached = indexManagers[indexPath] {
            return cached
        }

        // Get embedding provider for dimension
        let provider = try await getEmbeddingProvider(config: config)

        // Create index manager
        let manager = try IndexManager(
            directory: indexPath,
            dimension: provider.dimension
        )

        // Try to load existing index
        if FileManager.default.fileExists(atPath: indexPath) {
            try await manager.load()
            logger.info("Loaded existing index from: \(indexPath)")
        }

        indexManagers[indexPath] = manager
        return manager
    }

    /// Check if an index exists for a path.
    public func indexExists(for basePath: String, config: Config) -> Bool {
        let resolvedPath = resolvePath(basePath)
        let indexPath = (resolvedPath as NSString).appendingPathComponent(config.indexPath)
        return FileManager.default.fileExists(atPath: indexPath)
    }

    /// Clear cached index manager for a path.
    public func clearIndexManager(for basePath: String, config: Config) {
        let resolvedPath = resolvePath(basePath)
        let indexPath = (resolvedPath as NSString).appendingPathComponent(config.indexPath)
        indexManagers.removeValue(forKey: indexPath)
    }

    /// Save all loaded indexes.
    public func saveAllIndexes() async throws {
        for (path, manager) in indexManagers {
            try await manager.save()
            logger.info("Saved index: \(path)")
        }
    }

    // MARK: - Search

    /// Create a search engine for a path.
    public func createSearchEngine(
        for basePath: String,
        config: Config
    ) async throws -> HybridSearchEngine {
        let manager = try await getIndexManager(for: basePath, config: config)
        let provider = try await getEmbeddingProvider(config: config)

        let chunkStore = await manager.chunkStore
        let vectorStore = await manager.vectorStore

        return HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: provider,
            rrfK: config.rrfK
        )
    }

    // MARK: - LLM Providers

    /// Get or create LLM provider chains for search enhancement.
    public func getLLMProviders(
        config: Config
    ) async throws -> (utility: LLMProviderChain?, synthesis: LLMProviderChain?) {
        // Check if LLM enhancement is enabled
        guard config.searchEnhancement.enabled else {
            return (nil, nil)
        }

        // Return cached providers if available
        if let existing = llmProviders {
            return existing
        }

        // Create utility tier provider
        let utilityProvider: LLMProviderChain?
        do {
            let provider = try LLMProviderFactory.createProvider(
                from: config.searchEnhancement.utility,
                openAIKey: config.openAIAPIKey,
                anthropicKey: config.anthropicAPIKey
            )
            utilityProvider = LLMProviderChain.single(provider)
            logger.debug("Created utility LLM provider: \(config.searchEnhancement.utility.provider)")
        } catch {
            logger.warning("Failed to create utility LLM provider: \(error)")
            utilityProvider = nil
        }

        // Create synthesis tier provider
        let synthesisProvider: LLMProviderChain?
        do {
            let provider = try LLMProviderFactory.createProvider(
                from: config.searchEnhancement.synthesis,
                openAIKey: config.openAIAPIKey,
                anthropicKey: config.anthropicAPIKey
            )
            synthesisProvider = LLMProviderChain.single(provider)
            logger.debug("Created synthesis LLM provider: \(config.searchEnhancement.synthesis.provider)")
        } catch {
            logger.warning("Failed to create synthesis LLM provider: \(error)")
            synthesisProvider = nil
        }

        let providers = (utilityProvider, synthesisProvider)
        llmProviders = providers
        return providers
    }

    /// Get or create query expander for search enhancement.
    public func getQueryExpander(config: Config) async throws -> QueryExpander? {
        guard config.searchEnhancement.enabled else {
            return nil
        }

        if let existing = queryExpander {
            return existing
        }

        let providers = try await getLLMProviders(config: config)
        guard let utility = providers.utility else {
            return nil
        }

        let expander = QueryExpander(provider: utility)
        queryExpander = expander
        return expander
    }

    /// Get or create result synthesizer for search enhancement.
    public func getResultSynthesizer(config: Config) async throws -> ResultSynthesizer? {
        guard config.searchEnhancement.enabled else {
            return nil
        }

        if let existing = resultSynthesizer {
            return existing
        }

        let providers = try await getLLMProviders(config: config)
        guard let synthesis = providers.synthesis else {
            return nil
        }

        let synthesizer = ResultSynthesizer(provider: synthesis)
        resultSynthesizer = synthesizer
        return synthesizer
    }

    /// Get or create follow-up generator for search enhancement.
    public func getFollowUpGenerator(config: Config) async throws -> FollowUpGenerator? {
        guard config.searchEnhancement.enabled else {
            return nil
        }

        if let existing = followUpGenerator {
            return existing
        }

        let providers = try await getLLMProviders(config: config)
        guard let utility = providers.utility else {
            return nil
        }

        let generator = FollowUpGenerator(provider: utility)
        followUpGenerator = generator
        return generator
    }

    // MARK: - Utilities

    private func resolvePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }

        if path == "." || path.isEmpty {
            return FileManager.default.currentDirectoryPath
        }

        return (FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent(path)
    }
}
