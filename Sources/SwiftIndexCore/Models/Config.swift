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

    // MARK: - Search Configuration

    /// Weight for semantic search (0.0 to 1.0).
    public var semanticWeight: Float

    /// RRF k parameter for rank fusion.
    public var rrfK: Int

    /// Whether multi-hop search is enabled.
    public var multiHopEnabled: Bool

    /// Maximum depth for multi-hop search.
    public var multiHopDepth: Int

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

    // MARK: - Watch Mode

    /// Debounce interval for file changes (milliseconds).
    public var watchDebounceMs: Int

    // MARK: - Logging

    /// Log level (debug, info, warning, error).
    public var logLevel: String

    // MARK: - Initialization

    public init(
        embeddingProvider: String = "auto",
        embeddingModel: String = "all-MiniLM-L6-v2",
        embeddingDimension: Int = 384,
        semanticWeight: Float = 0.7,
        rrfK: Int = 60,
        multiHopEnabled: Bool = false,
        multiHopDepth: Int = 2,
        excludePatterns: [String] = Config.defaultExcludePatterns,
        includeExtensions: [String] = [],
        maxFileSize: Int = 1_000_000,
        chunkSize: Int = 1500,
        chunkOverlap: Int = 200,
        indexPath: String = ".swiftindex",
        cachePath: String = "~/.cache/swiftindex",
        voyageAPIKey: String? = nil,
        openAIAPIKey: String? = nil,
        watchDebounceMs: Int = 500,
        logLevel: String = "info"
    ) {
        self.embeddingProvider = embeddingProvider
        self.embeddingModel = embeddingModel
        self.embeddingDimension = embeddingDimension
        self.semanticWeight = semanticWeight
        self.rrfK = rrfK
        self.multiHopEnabled = multiHopEnabled
        self.multiHopDepth = multiHopDepth
        self.excludePatterns = excludePatterns
        self.includeExtensions = includeExtensions
        self.maxFileSize = maxFileSize
        self.chunkSize = chunkSize
        self.chunkOverlap = chunkOverlap
        self.indexPath = indexPath
        self.cachePath = cachePath
        self.voyageAPIKey = voyageAPIKey
        self.openAIAPIKey = openAIAPIKey
        self.watchDebounceMs = watchDebounceMs
        self.logLevel = logLevel
    }
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
            if let v = partial.embeddingProvider { config.embeddingProvider = v }
            if let v = partial.embeddingModel { config.embeddingModel = v }
            if let v = partial.embeddingDimension { config.embeddingDimension = v }
            if let v = partial.semanticWeight { config.semanticWeight = v }
            if let v = partial.rrfK { config.rrfK = v }
            if let v = partial.multiHopEnabled { config.multiHopEnabled = v }
            if let v = partial.multiHopDepth { config.multiHopDepth = v }
            if let v = partial.excludePatterns { config.excludePatterns = v }
            if let v = partial.includeExtensions { config.includeExtensions = v }
            if let v = partial.maxFileSize { config.maxFileSize = v }
            if let v = partial.chunkSize { config.chunkSize = v }
            if let v = partial.chunkOverlap { config.chunkOverlap = v }
            if let v = partial.indexPath { config.indexPath = v }
            if let v = partial.cachePath { config.cachePath = v }
            if let v = partial.voyageAPIKey { config.voyageAPIKey = v }
            if let v = partial.openAIAPIKey { config.openAIAPIKey = v }
            if let v = partial.watchDebounceMs { config.watchDebounceMs = v }
            if let v = partial.logLevel { config.logLevel = v }
        }

        return config
    }
}
