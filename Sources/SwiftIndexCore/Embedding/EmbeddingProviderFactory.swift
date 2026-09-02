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
    /// Providers `auto` will consider, in preference order.
    ///
    /// MLX first for quality, but only when it is *ready* — see `resolve(config:logger:)`.
    private static let autoPreference = ["mlx", "swift-embeddings"]

    /// Resolves the configured provider, probing availability where the choice is
    /// automatic.
    ///
    /// - Parameters:
    ///   - config: Effective configuration.
    ///   - logger: Logger for selection diagnostics.
    /// - Returns: The selected provider plus its identity and dimension.
    /// - Throws: `ProviderError` if an explicitly requested provider cannot be used.
    public static func resolve(
        config: Config,
        logger: Logger = Logger(label: "EmbeddingProviderFactory")
    ) async throws -> ResolvedEmbedding {
        let requested = config.embeddingProvider.lowercased()

        guard requested == "auto" else {
            return try make(provider: requested, config: config, logger: logger)
        }

        // "Smart auto": prefer MLX, but only if it can run *now* — metallibs present,
        // Apple Silicon, and the model already downloaded. Probing with `isAvailable()`
        // here would download ~0.4 GB just to answer the question, turning the very
        // first `swiftindex index` into a long silent stall.
        for candidate in autoPreference {
            guard let resolved = try? make(provider: candidate, config: config, logger: logger) else {
                continue
            }
            if await resolved.chain.isReady() {
                logger.debug("auto selected ready provider: \(resolved.providerID)")
                return resolved
            }
        }

        // Nothing is cached yet. Fall back to the provider with the cheapest first run
        // rather than the best quality: swift-embeddings is ~87 MB with no Metal
        // toolchain requirement, where MLX is ~0.4 GB and needs metallibs beside the
        // binary. Users who want MLX can ask for it explicitly.
        logger.debug("auto found no ready provider; defaulting to swift-embeddings")
        return try make(provider: "swift-embeddings", config: config, logger: logger)
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
            let mlx = MLXEmbeddingProvider(
                huggingFaceId: config.embeddingModel,
                dimension: config.embeddingDimension
            )
            return pin(mlx, id: "mlx", model: config.embeddingModel)

        case "swift-embeddings", "swift", "swiftembeddings":
            logger.debug("Using Swift Embeddings provider")
            // Dimension is derived from the model rather than config: the provider
            // auto-detects it, and an explicit mismatched value corrupts the index.
            let swift = SwiftEmbeddingsProvider()
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
