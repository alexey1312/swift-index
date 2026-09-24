// MARK: - EmbeddingProviderFactory

import Foundation
import Logging

/// The embedding provider selected for a run, together with the facts the index
/// depends on.
///
/// `dimension` comes from the provider that was actually chosen — never from the
/// first entry of a fallback chain. Reading the dimension off an unavailable
/// provider is what silently produced index corruption: an `auto` chain reported
/// MLX's 1024 while embedding through the 384-dimensional fallback.
public struct ResolvedEmbedding: Sendable {
    /// The chain to embed with. Always pinned to a single provider.
    public let chain: EmbeddingProviderChain

    /// Identifier of the provider that was selected, e.g. `"swift-embeddings"`.
    public let providerID: String

    /// The model the selected provider will use.
    public let modelID: String

    /// Vector dimension of the selected provider.
    public let dimension: Int

    public init(chain: EmbeddingProviderChain, providerID: String, modelID: String, dimension: Int) {
        self.chain = chain
        self.providerID = providerID
        self.modelID = modelID
        self.dimension = dimension
    }
}

/// Builds embedding providers from configuration.
///
/// This is the single place that maps a provider string onto a provider. It used to
/// exist in five copies (index, search, search-docs, watch and the MCP context) that
/// had drifted apart: some appended a differently-dimensioned fallback, some knew
/// about Gemini and some did not, and unknown strings silently became MLX. Indexing
/// with one copy and searching with another could therefore embed into two different
/// vector spaces.
public enum EmbeddingProviderFactory {
    /// Resolves the configured provider, probing availability where the choice is
    /// automatic.
    ///
    /// Under `auto` an existing index decides first: its `meta.json` records the
    /// provider and model that built it, and a different choice would embed queries
    /// into another vector space. A new index uses the first cloud provider with an
    /// API key, then MLX when this binary can run it, else swift-embeddings.
    ///
    /// - Parameters:
    ///   - config: Effective configuration.
    ///   - indexDirectory: Index directory whose metadata pins `auto`, if known.
    ///   - logger: Logger for selection diagnostics.
    /// - Returns: The selected provider plus its identity and dimension.
    /// - Throws: `ProviderError` if an explicitly requested provider cannot be used.
    public static func resolve(
        config: Config,
        indexDirectory: String? = nil,
        logger: Logger = Logger(label: "EmbeddingProviderFactory")
    ) async throws -> ResolvedEmbedding {
        let requested = config.embeddingProvider.lowercased()

        guard requested == "auto" else {
            return try make(provider: requested, config: config, logger: logger)
        }

        if let indexDirectory,
           let metadata = IndexMetadata.load(fromIndexDirectory: indexDirectory),
           let pinned = try? make(provider: metadata.providerID, config: config.pinned(to: metadata), logger: logger)
        {
            logger.debug("auto pinned to index provider: \(pinned.providerID)")
            return pinned
        }

        if let cloud = firstCloudProvider(config: config, logger: logger) {
            logger.debug("auto selected cloud provider: \(cloud.providerID)")
            return cloud
        }

        // The Metal library ships only with release artifacts, so its presence marks an
        // install that can run MLX. The model downloads on first use.
        if MLXSupport.isRuntimeAvailable, let mlx = try? make(provider: "mlx", config: config, logger: logger) {
            logger.debug("auto selected mlx: Metal library present")
            return mlx
        }

        logger.debug("auto selected swift-embeddings: no Metal library beside the binary")
        return try make(provider: "swift-embeddings", config: config, logger: logger)
    }

    /// Whether `auto` has no cloud key and so embeds with a local model.
    public static func autoUsesLocalModel(config: Config) -> Bool {
        config.embeddingProvider.lowercased() == "auto" && !hasCloudKey(config: config)
    }

    private static func hasCloudKey(config: Config) -> Bool {
        EmbeddingModelDefaults.cloudPreference.contains { apiKey(for: $0.provider, config: config) != nil }
    }

    private static func apiKey(for provider: String, config: Config) -> String? {
        let key = switch provider {
        case "openai": config.openAIAPIKey
        case "voyage": config.voyageAPIKey
        case "gemini": config.geminiAPIKey
        default: String?.none
        }
        guard let key, !key.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return key
    }

    /// The first cloud provider with a key, built with its own default model.
    ///
    /// The shared `embeddingModel` default names a local model, so it cannot be
    /// passed to a cloud API.
    private static func firstCloudProvider(config: Config, logger: Logger) -> ResolvedEmbedding? {
        for candidate in EmbeddingModelDefaults.cloudPreference
            where apiKey(for: candidate.provider, config: config) != nil
        {
            var cloudConfig = config
            cloudConfig.embeddingModel = candidate.model
            cloudConfig.embeddingDimension = candidate.dimension
            if let resolved = try? make(provider: candidate.provider, config: cloudConfig, logger: logger) {
                return resolved
            }
        }
        return nil
    }

    /// Builds a specific provider without any availability probing.
    ///
    /// - Parameters:
    ///   - provider: Provider identifier (case-insensitive).
    ///   - config: Effective configuration.
    ///   - logger: Logger for diagnostics.
    /// - Returns: The provider pinned as a single-element chain.
    /// - Throws: `ProviderError.apiKeyMissing` for API providers without a key,
    ///   `ProviderError.notAvailable` for an unrecognised identifier.
    public static func make(
        provider: String,
        config: Config,
        logger: Logger = Logger(label: "EmbeddingProviderFactory")
    ) throws -> ResolvedEmbedding {
        switch provider.lowercased() {
        case "mock":
            logger.debug("Using mock embedding provider")
            let mock = MockEmbeddingProvider()
            return pin(mock, id: "mock", model: "mock")

        case "mlx":
            logger.debug("Using MLX embedding provider")
            let selection = EmbeddingModelDefaults.mlxSelection(
                configuredModel: config.embeddingModel,
                configuredDimension: config.embeddingDimension
            )
            let mlx = MLXEmbeddingProvider(huggingFaceId: selection.model, dimension: selection.dimension)
            return pin(mlx, id: "mlx", model: selection.model)

        case "swift-embeddings", "swift", "swiftembeddings":
            logger.debug("Using Swift Embeddings provider")
            // Dimension is derived from the model rather than config: the provider
            // auto-detects it, and an explicit mismatched value corrupts the index.
            let model = EmbeddingModelDefaults.swiftEmbeddingsModel(for: config.embeddingModel)
            if model == nil {
                logger.debug("Unknown swift-embeddings model '\(config.embeddingModel)'; using the default")
            }
            let swift = SwiftEmbeddingsProvider(model: model ?? .miniLM)
            return pin(swift, id: "swift-embeddings", model: swift.modelName)

        case "ollama":
            logger.debug("Using Ollama embedding provider")
            let ollama = OllamaEmbeddingProvider(
                modelName: config.embeddingModel,
                dimension: config.embeddingDimension
            )
            return pin(ollama, id: "ollama", model: config.embeddingModel)

        case "voyage":
            guard let apiKey = config.voyageAPIKey else {
                throw ProviderError.apiKeyMissing(provider: "Voyage AI")
            }
            logger.debug("Using Voyage AI embedding provider")
            let voyage = VoyageProvider(
                apiKey: apiKey,
                modelName: config.embeddingModel,
                dimension: config.embeddingDimension
            )
            return pin(voyage, id: "voyage", model: config.embeddingModel)

        case "openai":
            guard let apiKey = config.openAIAPIKey else {
                throw ProviderError.apiKeyMissing(provider: "OpenAI")
            }
            logger.debug("Using OpenAI embedding provider")
            let openAI = OpenAIProvider(apiKey: apiKey)
            return pin(openAI, id: "openai", model: openAI.modelName)

        case "gemini":
            guard let apiKey = config.geminiAPIKey else {
                throw ProviderError.apiKeyMissing(provider: "Gemini")
            }
            logger.debug("Using Gemini embedding provider")
            let gemini = GeminiEmbeddingProvider(
                apiKey: apiKey,
                modelName: config.embeddingModel,
                dimension: config.embeddingDimension
            )
            return pin(gemini, id: "gemini", model: config.embeddingModel)

        default:
            // Deliberately loud. The previous behaviour — silently substituting the
            // default chain — turned a typo like "gemeni" into an index built with a
            // different provider and dimension than the user asked for.
            throw ProviderError.notAvailable(
                reason: """
                Unknown embedding provider '\(provider)'. \
                Valid providers: mlx, swift-embeddings, ollama, openai, voyage, gemini, auto.
                """
            )
        }
    }

    /// Wraps a single provider in a chain.
    ///
    /// Chains never mix providers of different dimensions: a fallback that changes the
    /// vector space mid-index produces an index that cannot be searched.
    private static func pin(
        _ provider: any EmbeddingProvider,
        id: String,
        model: String
    ) -> ResolvedEmbedding {
        ResolvedEmbedding(
            chain: EmbeddingProviderChain(
                providers: [provider],
                id: "\(id)-chain",
                name: provider.name
            ),
            providerID: id,
            modelID: model,
            dimension: provider.dimension
        )
    }
}

private extension Config {
    /// This config with the model and dimension an existing index was built with.
    func pinned(to metadata: IndexMetadata) -> Config {
        var copy = self
        copy.embeddingModel = metadata.modelID
        copy.embeddingDimension = metadata.dimension
        return copy
    }
}
