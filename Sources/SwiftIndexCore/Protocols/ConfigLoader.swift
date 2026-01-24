// MARK: - ConfigLoader Protocol

import Foundation

/// A loader that reads configuration from various sources.
///
/// Config loaders handle different configuration sources:
/// - TOML files
/// - Environment variables
/// - CLI arguments
public protocol ConfigLoader: Sendable {
    /// Load configuration from this source.
    ///
    /// - Returns: A partial configuration with values from this source.
    /// - Throws: `ConfigError` if loading fails.
    func load() throws -> PartialConfig
}

/// A partial configuration with optional fields.
///
/// Used during config merging to allow layered overrides.
public struct PartialConfig: Sendable, Equatable {
    // MARK: - Embedding

    public var embeddingProvider: String?
    public var embeddingModel: String?
    public var embeddingDimension: Int?
    public var embeddingBatchSize: Int?
    public var embeddingBatchTimeoutMs: Int?
    public var embeddingBatchMemoryLimitMB: Int?

    // MARK: - Search

    public var semanticWeight: Float?
    public var rrfK: Int?
    public var multiHopEnabled: Bool?
    public var multiHopDepth: Int?
    public var outputFormat: String?
    public var searchLimit: Int?
    public var expandQueryByDefault: Bool?
    public var synthesizeByDefault: Bool?
    public var defaultExtensions: [String]?
    public var defaultPathFilter: String?

    // MARK: - Indexing

    public var excludePatterns: [String]?
    public var includeExtensions: [String]?
    public var maxFileSize: Int?
    public var chunkSize: Int?
    public var chunkOverlap: Int?

    // MARK: - Storage

    public var indexPath: String?
    public var cachePath: String?

    // MARK: - API Keys (Cloud Providers)

    public var voyageAPIKey: String?
    public var openAIAPIKey: String?

    // MARK: - Performance

    public var maxConcurrentTasks: Int?

    // MARK: - Watch Mode

    public var watchDebounceMs: Int?

    // MARK: - Logging

    public var logLevel: String?

    // MARK: - Search Enhancement (LLM)

    public var searchEnhancement: SearchEnhancementConfig?

    public init(
        embeddingProvider: String? = nil,
        embeddingModel: String? = nil,
        embeddingDimension: Int? = nil,
        embeddingBatchSize: Int? = nil,
        embeddingBatchTimeoutMs: Int? = nil,
        embeddingBatchMemoryLimitMB: Int? = nil,
        semanticWeight: Float? = nil,
        rrfK: Int? = nil,
        multiHopEnabled: Bool? = nil,
        multiHopDepth: Int? = nil,
        outputFormat: String? = nil,
        searchLimit: Int? = nil,
        expandQueryByDefault: Bool? = nil,
        synthesizeByDefault: Bool? = nil,
        defaultExtensions: [String]? = nil,
        defaultPathFilter: String? = nil,
        excludePatterns: [String]? = nil,
        includeExtensions: [String]? = nil,
        maxFileSize: Int? = nil,
        chunkSize: Int? = nil,
        chunkOverlap: Int? = nil,
        indexPath: String? = nil,
        cachePath: String? = nil,
        voyageAPIKey: String? = nil,
        openAIAPIKey: String? = nil,
        maxConcurrentTasks: Int? = nil,
        watchDebounceMs: Int? = nil,
        logLevel: String? = nil,
        searchEnhancement: SearchEnhancementConfig? = nil
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

    /// Empty partial config.
    public static let empty = PartialConfig()
}

/// Errors that can occur during configuration loading.
public enum ConfigError: Error, Sendable, Equatable {
    /// The configuration file was not found.
    case fileNotFound(String)

    /// The configuration file has invalid syntax.
    case invalidSyntax(String)

    /// A required configuration value is missing.
    case missingRequired(String)

    /// A configuration value has an invalid type or format.
    case invalidValue(key: String, message: String)
}
