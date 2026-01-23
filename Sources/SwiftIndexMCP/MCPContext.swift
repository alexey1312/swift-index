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
    private let logger = Logger(label: "MCPContext")

    // MARK: - Initialization

    private init() {}

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
    public func getEmbeddingProvider(config: Config) async -> EmbeddingProviderChain {
        if let existing = embeddingProvider {
            return existing
        }

        let provider = createEmbeddingProvider(config: config)
        embeddingProvider = provider
        return provider
    }

    private func createEmbeddingProvider(config: Config) -> EmbeddingProviderChain {
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
                logger.warning("VOYAGE_API_KEY not set, using default provider")
                return EmbeddingProviderChain.default
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
                logger.warning("OPENAI_API_KEY not set, using default provider")
                return EmbeddingProviderChain.default
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
        let provider = await getEmbeddingProvider(config: config)

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
        let provider = await getEmbeddingProvider(config: config)

        let chunkStore = await manager.chunkStore
        let vectorStore = await manager.vectorStore

        return HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: provider,
            rrfK: config.rrfK
        )
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
