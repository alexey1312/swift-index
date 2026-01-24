// MARK: - Config Model

import Foundation

/// Complete configuration for SwiftIndex.
///
/// Created by merging partial configs from multiple sources
/// with priority: CLI > Environment > Project > Global > Defaults.
public struct Config: Sendable, Equatable {
    // MARK: - Embedding Configuration

    /// Preferred embedding provider ID.
    public var embeddingProvider: String

    /// Model name for the embedding provider.
    public var embeddingModel: String

    /// Expected dimension of embedding vectors.
    public var embeddingDimension: Int

    /// Maximum chunks per embedding batch call.
    public var embeddingBatchSize: Int

    /// Idle timeout before flushing embedding batch (milliseconds).
    public var embeddingBatchTimeoutMs: Int

    /// Memory limit for pending embedding chunks (megabytes).
    public var embeddingBatchMemoryLimitMB: Int

    // MARK: - Search Configuration

    /// Weight for semantic search (0.0 to 1.0).
    public var semanticWeight: Float

    /// RRF k parameter for rank fusion.
    public var rrfK: Int

    /// Whether multi-hop search is enabled.
    public var multiHopEnabled: Bool

    /// Maximum depth for multi-hop search.
    public var multiHopDepth: Int

    /// Default output format for search results (human, json, toon).
    public var outputFormat: String

    /// Default number of search results to return.
    public var searchLimit: Int

    /// Whether to expand queries using LLM by default.
    public var expandQueryByDefault: Bool

    /// Whether to synthesize results using LLM by default.
    public var synthesizeByDefault: Bool

    /// Default file extensions to filter search results.
    public var defaultExtensions: [String]

    /// Default path filter pattern (glob syntax).
    public var defaultPathFilter: String?

    // MARK: - Indexing Configuration

    /// Glob patterns for files/directories to exclude.
    public var excludePatterns: [String]

    /// File extensions to include (empty = all supported).
    public var includeExtensions: [String]

    /// Maximum file size to index (bytes).
    public var maxFileSize: Int

    /// Target chunk size in characters.
    public var chunkSize: Int

    /// Overlap between chunks in characters.
    public var chunkOverlap: Int

    // MARK: - Storage Configuration

    /// Path to the index directory.
    public var indexPath: String

    /// Path to the cache directory.
    public var cachePath: String

    // MARK: - API Keys

    /// Voyage AI API key (optional).
    public var voyageAPIKey: String?

    /// OpenAI API key (optional).
    public var openAIAPIKey: String?

    // MARK: - Performance

    /// Maximum concurrent tasks for parallel indexing.
    public var maxConcurrentTasks: Int

    // MARK: - Watch Mode

    /// Debounce interval for file changes (milliseconds).
    public var watchDebounceMs: Int

    // MARK: - Logging

    /// Log level (debug, info, warning, error).
    public var logLevel: String

    // MARK: - Search Enhancement (LLM)

    /// LLM-powered search enhancement configuration.
    public var searchEnhancement: SearchEnhancementConfig

    // MARK: - Initialization

    public init(
        embeddingProvider: String = "auto",
        embeddingModel: String = "all-MiniLM-L6-v2",
        embeddingDimension: Int = 384,
        embeddingBatchSize: Int = 32,
        embeddingBatchTimeoutMs: Int = 150,
        embeddingBatchMemoryLimitMB: Int = 10,
        semanticWeight: Float = 0.7,
        rrfK: Int = 60,
        multiHopEnabled: Bool = false,
        multiHopDepth: Int = 2,
        outputFormat: String = "human",
        searchLimit: Int = 20,
        expandQueryByDefault: Bool = false,
        synthesizeByDefault: Bool = false,
        defaultExtensions: [String] = [],
        defaultPathFilter: String? = nil,
        excludePatterns: [String] = Config.defaultExcludePatterns,
        includeExtensions: [String] = [],
        maxFileSize: Int = 1_000_000,
        chunkSize: Int = 1500,
        chunkOverlap: Int = 200,
        indexPath: String = ".swiftindex",
        cachePath: String = "~/.cache/swiftindex",
        voyageAPIKey: String? = nil,
        openAIAPIKey: String? = nil,
        maxConcurrentTasks: Int = ProcessInfo.processInfo.activeProcessorCount,
        watchDebounceMs: Int = 500,
        logLevel: String = "info",
        searchEnhancement: SearchEnhancementConfig = .default
    ) {
        self.embeddingProvider = embeddingProvider
        self.embeddingModel = embeddingModel
        self.embeddingDimension = embeddingDimension
        self.embeddingBatchSize = embeddingBatchSize
        self.embeddingBatchTimeoutMs = embeddingBatchTimeoutMs
        self.embeddingBatchMemoryLimitMB = embeddingBatchMemoryLimitMB
        self.semanticWeight = semanticWeight
        self.rrfK = rrfK
        self.multiHopEnabled = multiHopEnabled
        self.multiHopDepth = multiHopDepth
        self.outputFormat = outputFormat
        self.searchLimit = searchLimit
        self.expandQueryByDefault = expandQueryByDefault
        self.synthesizeByDefault = synthesizeByDefault
        self.defaultExtensions = defaultExtensions
        self.defaultPathFilter = defaultPathFilter
        self.excludePatterns = excludePatterns
        self.includeExtensions = includeExtensions
        self.maxFileSize = maxFileSize
        self.chunkSize = chunkSize
        self.chunkOverlap = chunkOverlap
        self.indexPath = indexPath
        self.cachePath = cachePath
        self.voyageAPIKey = voyageAPIKey
        self.openAIAPIKey = openAIAPIKey
        self.maxConcurrentTasks = maxConcurrentTasks
        self.watchDebounceMs = watchDebounceMs
        self.logLevel = logLevel
        self.searchEnhancement = searchEnhancement
    }
}

// MARK: - Search Enhancement Config

/// Configuration for LLM-powered search enhancements.
///
/// Enables query expansion, result synthesis, and follow-up suggestions
/// using a dual-tier LLM architecture:
/// - **Utility tier**: Fast operations (query expansion, follow-ups)
/// - **Synthesis tier**: Deep analysis (result summarization)
public struct SearchEnhancementConfig: Sendable, Equatable {
    /// Whether search enhancement is enabled.
    public var enabled: Bool

    /// Configuration for fast utility operations.
    public var utility: LLMTierConfig

    /// Configuration for deep synthesis operations.
    public var synthesis: LLMTierConfig

    public init(
        enabled: Bool = false,
        utility: LLMTierConfig = .defaultUtility,
        synthesis: LLMTierConfig = .defaultSynthesis
    ) {
        self.enabled = enabled
        self.utility = utility
        self.synthesis = synthesis
    }

    /// Default configuration (disabled).
    public static let `default` = SearchEnhancementConfig()
}

/// Configuration for a single LLM tier.
public struct LLMTierConfig: Sendable, Equatable {
    /// LLM provider identifier.
    ///
    /// Supported providers:
    /// - `claude-code-cli`: Claude Code CLI (requires `claude` command)
    /// - `codex-cli`: Codex CLI (requires `codex` command)
    /// - `ollama`: Local Ollama server
    /// - `openai`: OpenAI API
    public var provider: String

    /// Model name override (optional, uses provider default if nil).
    public var model: String?

    /// Request timeout in seconds.
    public var timeout: TimeInterval

    public init(
        provider: String,
        model: String? = nil,
        timeout: TimeInterval = 60
    ) {
        self.provider = provider
        self.model = model
        self.timeout = timeout
    }

    /// Default utility tier (fast operations).
    public static let defaultUtility = LLMTierConfig(
        provider: "claude-code-cli",
        model: nil,
        timeout: 30
    )

    /// Default synthesis tier (deep analysis).
    public static let defaultSynthesis = LLMTierConfig(
        provider: "claude-code-cli",
        model: nil,
        timeout: 120
    )
}

// MARK: - Defaults

public extension Config {
    /// Default exclude patterns.
    static let defaultExcludePatterns: [String] = [
        ".git",
        ".build",
        "DerivedData",
        "Pods",
        "Carthage",
        ".swiftpm",
        "node_modules",
        "*.xcodeproj",
        "*.xcworkspace",
        ".swiftindex",
    ]

    /// Default configuration.
    static let `default` = Config()

    /// Create config by merging partial configs with priority.
    ///
    /// - Parameter partials: Array of partial configs, highest priority first.
    /// - Returns: Complete merged config.
    static func merge(_ partials: [PartialConfig]) -> Config {
        var config = Config.default

        // Apply partials in reverse order (lowest priority first)
        for partial in partials.reversed() {
            config.apply(partial)
        }

        return config
    }

    private mutating func apply(_ partial: PartialConfig) {
        applyIfPresent(partial.embeddingProvider, to: \.embeddingProvider)
        applyIfPresent(partial.embeddingModel, to: \.embeddingModel)
        applyIfPresent(partial.embeddingDimension, to: \.embeddingDimension)
        applyIfPresent(partial.embeddingBatchSize, to: \.embeddingBatchSize)
        applyIfPresent(partial.embeddingBatchTimeoutMs, to: \.embeddingBatchTimeoutMs)
        applyIfPresent(partial.embeddingBatchMemoryLimitMB, to: \.embeddingBatchMemoryLimitMB)
        applyIfPresent(partial.semanticWeight, to: \.semanticWeight)
        applyIfPresent(partial.rrfK, to: \.rrfK)
        applyIfPresent(partial.multiHopEnabled, to: \.multiHopEnabled)
        applyIfPresent(partial.multiHopDepth, to: \.multiHopDepth)
        applyIfPresent(partial.outputFormat, to: \.outputFormat)
        applyIfPresent(partial.searchLimit, to: \.searchLimit)
        applyIfPresent(partial.expandQueryByDefault, to: \.expandQueryByDefault)
        applyIfPresent(partial.synthesizeByDefault, to: \.synthesizeByDefault)
        applyIfPresent(partial.defaultExtensions, to: \.defaultExtensions)
        applyIfPresent(partial.defaultPathFilter, to: \.defaultPathFilter)
        applyIfPresent(partial.excludePatterns, to: \.excludePatterns)
        applyIfPresent(partial.includeExtensions, to: \.includeExtensions)
        applyIfPresent(partial.maxFileSize, to: \.maxFileSize)
        applyIfPresent(partial.chunkSize, to: \.chunkSize)
        applyIfPresent(partial.chunkOverlap, to: \.chunkOverlap)
        applyIfPresent(partial.indexPath, to: \.indexPath)
        applyIfPresent(partial.cachePath, to: \.cachePath)
        applyIfPresent(partial.voyageAPIKey, to: \.voyageAPIKey)
        applyIfPresent(partial.openAIAPIKey, to: \.openAIAPIKey)
        applyIfPresent(partial.maxConcurrentTasks, to: \.maxConcurrentTasks)
        applyIfPresent(partial.watchDebounceMs, to: \.watchDebounceMs)
        applyIfPresent(partial.logLevel, to: \.logLevel)
        applyIfPresent(partial.searchEnhancement, to: \.searchEnhancement)
    }

    private mutating func applyIfPresent<T>(
        _ value: T?,
        to keyPath: WritableKeyPath<Config, T>
    ) {
        if let value {
            self[keyPath: keyPath] = value
        }
    }
}
