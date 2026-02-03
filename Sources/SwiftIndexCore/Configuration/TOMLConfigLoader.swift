// MARK: - TOML Configuration Loader

import Foundation
import TOML

/// Loads configuration from TOML files.
///
/// Parses `.swiftindex.toml` files and converts them to `PartialConfig`.
/// Supports the standard TOML structure with sections for embedding, search, indexing, etc.
///
/// ## Example TOML Structure
///
/// ```toml
/// [embedding]
/// provider = "mlx"
/// model = "all-MiniLM-L6-v2"
/// dimension = 384
///
/// [search]
/// semantic_weight = 0.7
/// rrf_k = 60
/// multi_hop_enabled = true
/// multi_hop_depth = 2
/// output_format = "toon"  # toon, human, or json
///
/// [indexing]
/// exclude = [".git", ".build", "DerivedData"]
/// include_extensions = [".swift", ".m", ".h", ".md"]
/// max_file_size = 1000000
/// chunk_size = 1500
/// chunk_overlap = 200
/// max_concurrent_tasks = 8  # defaults to CPU count
///
/// [storage]
/// index_path = ".swiftindex"
/// cache_path = "~/.cache/swiftindex"
///
/// [watch]
/// debounce_ms = 500
///
/// [logging]
/// level = "info"
/// ```
public struct TOMLConfigLoader: ConfigLoader, Sendable {
    // MARK: - Properties

    /// The path to the TOML configuration file.
    public let filePath: String

    // MARK: - Initialization

    /// Creates a TOML config loader for the specified file path.
    ///
    /// - Parameter filePath: Absolute or relative path to the TOML configuration file.
    public init(filePath: String) {
        self.filePath = filePath
    }

    /// Creates a TOML config loader for the project configuration file.
    ///
    /// Looks for `.swiftindex.toml` in the specified directory.
    ///
    /// - Parameter projectDirectory: Path to the project root directory.
    /// - Returns: A loader configured for the project's config file.
    public static func forProject(at projectDirectory: String) -> TOMLConfigLoader {
        let path = (projectDirectory as NSString).appendingPathComponent(".swiftindex.toml")
        return TOMLConfigLoader(filePath: path)
    }

    /// Creates a TOML config loader for the global configuration file.
    ///
    /// Looks for `config.toml` in `~/.config/swiftindex/`.
    ///
    /// - Parameter configDirectory: Optional config directory path. If nil, uses `~/.config/swiftindex`.
    /// - Returns: A loader configured for the global config file.
    public static func forGlobal(configDirectory: String? = nil) -> TOMLConfigLoader {
        let configDir: String
        if let directory = configDirectory {
            configDir = directory
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            configDir = (home as NSString).appendingPathComponent(".config/swiftindex")
        }
        let path = (configDir as NSString).appendingPathComponent("config.toml")
        return TOMLConfigLoader(filePath: path)
    }

    // MARK: - ConfigLoader

    /// Loads configuration from the TOML file.
    ///
    /// - Returns: A partial configuration with values parsed from the TOML file.
    /// - Throws: `ConfigError.fileNotFound` if the file doesn't exist.
    /// - Throws: `ConfigError.invalidSyntax` if the TOML parsing fails.
    /// - Throws: `ConfigError.invalidValue` if a value has an unexpected type.
    public func load() throws -> PartialConfig {
        // Check file existence
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ConfigError.fileNotFound(filePath)
        }

        // Read file contents
        let contents: String
        do {
            contents = try String(contentsOfFile: filePath, encoding: .utf8)
        } catch {
            throw ConfigError.invalidSyntax("Failed to read file: \(error.localizedDescription)")
        }

        let diagnostics = try TOMLConfigValidator.lint(contents: contents, filePath: filePath)
        let errors = diagnostics.filter { $0.severity == .error }
        if !errors.isEmpty {
            let message = errors
                .map { diagnostic in
                    if let keyPath = diagnostic.keyPath {
                        return "\(keyPath): \(diagnostic.message)"
                    }
                    return diagnostic.message
                }
                .joined(separator: "\n")
            throw ConfigError.invalidValue(key: "config", message: message)
        }

        // Parse TOML using Codable
        let decoder = TOMLDecoder()
        let tomlConfig: TOMLConfig
        do {
            tomlConfig = try decoder.decode(TOMLConfig.self, from: contents)
        } catch {
            throw ConfigError.invalidSyntax("Invalid TOML: \(error.localizedDescription)")
        }

        try validateRemoteConfig(tomlConfig.remote)

        return tomlConfig.toPartialConfig()
    }
}

// MARK: - Intermediate TOML Structure

/// Intermediate Codable struct matching the TOML file structure.
private struct TOMLConfig: Codable {
    var embedding: EmbeddingSection?
    var search: SearchSection?
    var indexing: IndexingSection?
    var storage: StorageSection?
    var watch: WatchSection?
    var logging: LoggingSection?
    var remote: RemoteSection?

    struct EmbeddingSection: Codable {
        var provider: String?
        var model: String?
        var dimension: Int?
        var batch_size: Int?
        var batch_timeout_ms: Int?
        var batch_memory_limit_mb: Int?
    }

    struct SearchSection: Codable {
        var semantic_weight: Double?
        var rrf_k: Int?
        var multi_hop_enabled: Bool?
        var multi_hop_depth: Int?
        var output_format: String?
        var limit: Int?
        var expand_query_by_default: Bool?
        var synthesize_by_default: Bool?
        var default_extensions: [String]?
        var default_path_filter: String?
        var enhancement: EnhancementSection?

        struct EnhancementSection: Codable {
            var enabled: Bool?
            var utility: TierSection?
            var synthesis: TierSection?

            struct TierSection: Codable {
                var provider: String?
                var model: String?
                var timeout: Int?
            }
        }
    }

    struct IndexingSection: Codable {
        var exclude: [String]?
        var include_extensions: [String]?
        var max_file_size: Int?
        var chunk_size: Int?
        var chunk_overlap: Int?
        var max_concurrent_tasks: Int?
    }

    struct StorageSection: Codable {
        var index_path: String?
        var cache_path: String?
    }

    struct WatchSection: Codable {
        var debounce_ms: Int?
    }

    struct LoggingSection: Codable {
        var level: String?
    }

    struct RemoteSection: Codable {
        var enabled: Bool?
        var provider: String?
        var bucket: String?
        var region: String?
        var project: String?
        var prefix: String?
        var sync: SyncSection?

        struct SyncSection: Codable {
            var compression: String?
            var auto_pull: Bool?
        }
    }

    /// Converts the intermediate TOML structure to a PartialConfig.
    func toPartialConfig() -> PartialConfig {
        var config = PartialConfig()

        // Embedding section
        if let embedding {
            config.embeddingProvider = embedding.provider
            config.embeddingModel = embedding.model
            config.embeddingDimension = embedding.dimension
            config.embeddingBatchSize = embedding.batch_size
            config.embeddingBatchTimeoutMs = embedding.batch_timeout_ms
            config.embeddingBatchMemoryLimitMB = embedding.batch_memory_limit_mb
        }

        // Search section
        if let search {
            config.semanticWeight = search.semantic_weight.map { Float($0) }
            config.rrfK = search.rrf_k
            config.multiHopEnabled = search.multi_hop_enabled
            config.multiHopDepth = search.multi_hop_depth
            config.outputFormat = search.output_format
            config.searchLimit = search.limit
            config.expandQueryByDefault = search.expand_query_by_default
            config.synthesizeByDefault = search.synthesize_by_default
            config.defaultExtensions = search.default_extensions
            config.defaultPathFilter = search.default_path_filter

            // Search enhancement subsection
            if let enhancement = search.enhancement {
                var enhancementConfig = SearchEnhancementConfig.default
                if let enabled = enhancement.enabled {
                    enhancementConfig.enabled = enabled
                }
                if let utility = enhancement.utility {
                    var tierConfig = LLMTierConfig.defaultUtility
                    if let provider = utility.provider {
                        tierConfig.provider = provider
                    }
                    tierConfig.model = utility.model
                    if let timeout = utility.timeout {
                        tierConfig.timeout = TimeInterval(timeout)
                    }
                    enhancementConfig.utility = tierConfig
                }
                if let synthesis = enhancement.synthesis {
                    var tierConfig = LLMTierConfig.defaultSynthesis
                    if let provider = synthesis.provider {
                        tierConfig.provider = provider
                    }
                    tierConfig.model = synthesis.model
                    if let timeout = synthesis.timeout {
                        tierConfig.timeout = TimeInterval(timeout)
                    }
                    enhancementConfig.synthesis = tierConfig
                }
                config.searchEnhancement = enhancementConfig
            }
        }

        // Indexing section
        if let indexing {
            config.excludePatterns = indexing.exclude
            config.includeExtensions = indexing.include_extensions
            config.maxFileSize = indexing.max_file_size
            config.chunkSize = indexing.chunk_size
            config.chunkOverlap = indexing.chunk_overlap
            config.maxConcurrentTasks = indexing.max_concurrent_tasks
        }

        // Storage section
        if let storage {
            config.indexPath = storage.index_path
            config.cachePath = storage.cache_path
        }

        // Watch section
        if let watch {
            config.watchDebounceMs = watch.debounce_ms
        }

        // Logging section
        if let logging {
            config.logLevel = logging.level
        }

        // Remote storage section
        if let remote {
            let enabled = remote.enabled ?? true
            if enabled, let provider = remote.provider, let bucket = remote.bucket {
                let sync = RemoteConfig.Sync(
                    compression: RemoteConfig.Compression(rawValue: remote.sync?.compression ?? "zstd") ?? .zstd,
                    autoPull: remote.sync?.auto_pull ?? false
                )
                if let providerValue = RemoteConfig.Provider(rawValue: provider) {
                    config.remote = RemoteConfig(
                        enabled: enabled,
                        provider: providerValue,
                        bucket: bucket,
                        region: remote.region,
                        project: remote.project,
                        prefix: remote.prefix ?? "",
                        sync: sync
                    )
                }
            }
        }

        return config
    }
}

private extension TOMLConfigLoader {
    func validateRemoteConfig(_ remote: TOMLConfig.RemoteSection?) throws {
        guard let remote else { return }
        let enabled = remote.enabled ?? true
        guard enabled else { return }

        guard let provider = remote.provider, !provider.isEmpty else {
            throw ConfigError.missingRequired("remote.provider")
        }

        if RemoteConfig.Provider(rawValue: provider) == nil {
            throw ConfigError.invalidValue(
                key: "remote.provider",
                message: "Supported providers: s3, gcs"
            )
        }

        guard let bucket = remote.bucket, !bucket.isEmpty else {
            throw ConfigError.missingRequired("remote.bucket")
        }

        if provider == RemoteConfig.Provider.s3.rawValue,
           remote.region == nil || remote.region?.isEmpty == true
        {
            throw ConfigError.missingRequired("remote.region")
        }

        if let compression = remote.sync?.compression,
           RemoteConfig.Compression(rawValue: compression) == nil
        {
            throw ConfigError.invalidValue(
                key: "remote.sync.compression",
                message: "Supported values: zstd, none"
            )
        }
    }
}

// MARK: - Layered Configuration Loading

public extension TOMLConfigLoader {
    /// Loads configuration from multiple sources with layered priority.
    ///
    /// Sources are checked in order (highest to lowest priority):
    /// 1. CLI arguments (provided as `PartialConfig`)
    /// 2. Environment variables
    /// 3. Project `.swiftindex.toml`
    /// 4. Global `~/.config/swiftindex/config.toml`
    /// 5. Default values
    ///
    /// - Parameters:
    ///   - cliConfig: Configuration from CLI arguments (highest priority).
    ///   - envConfig: Configuration from environment variables.
    ///   - projectDirectory: Path to the project root directory.
    ///   - globalConfigDirectory: Optional global config directory path. If nil, uses `~/.config/swiftindex`.
    ///   - requireInitialization: If true, throws `ConfigError.notInitialized` when no config files exist.
    /// - Returns: Complete merged configuration.
    /// - Throws: `ConfigError.notInitialized` if `requireInitialization` is true and no config files exist.
    static func loadLayered(
        cli cliConfig: PartialConfig = .empty,
        env envConfig: PartialConfig = .empty,
        projectDirectory: String,
        globalConfigDirectory: String? = nil,
        requireInitialization: Bool = true
    ) throws -> Config {
        var partials: [PartialConfig] = [cliConfig, envConfig]
        var hasConfigFile = false

        // Try loading project config
        let projectLoader = TOMLConfigLoader.forProject(at: projectDirectory)
        if FileManager.default.fileExists(atPath: projectLoader.filePath) {
            let projectConfig = try projectLoader.load()
            partials.append(projectConfig)
            hasConfigFile = true
        }

        // Try loading global config
        let globalLoader = TOMLConfigLoader.forGlobal(configDirectory: globalConfigDirectory)
        if FileManager.default.fileExists(atPath: globalLoader.filePath) {
            let globalConfig = try globalLoader.load()
            partials.append(globalConfig)
            hasConfigFile = true
        }

        // Check if initialization is required but no config files exist
        if requireInitialization, !hasConfigFile {
            throw ConfigError.notInitialized
        }

        return Config.merge(partials)
    }

    /// Checks if configuration has been initialized for the given project.
    ///
    /// Returns true if either a project `.swiftindex.toml` or global config exists.
    ///
    /// - Parameters:
    ///   - projectDirectory: Path to the project root directory.
    ///   - globalConfigDirectory: Optional global config directory path. If nil, uses `~/.config/swiftindex`.
    /// - Returns: True if at least one config file exists.
    static func isInitialized(
        projectDirectory: String,
        globalConfigDirectory: String? = nil
    ) -> Bool {
        let projectLoader = TOMLConfigLoader.forProject(at: projectDirectory)
        if FileManager.default.fileExists(atPath: projectLoader.filePath) {
            return true
        }

        let globalLoader = TOMLConfigLoader.forGlobal(configDirectory: globalConfigDirectory)
        return FileManager.default.fileExists(atPath: globalLoader.filePath)
    }
}
