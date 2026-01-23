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
/// multi_hop_enabled = false
/// multi_hop_depth = 2
/// output_format = "human"  # human, json, or toon
///
/// [indexing]
/// exclude = [".git", ".build", "DerivedData"]
/// include_extensions = [".swift", ".m", ".h"]
/// max_file_size = 1000000
/// chunk_size = 1500
/// chunk_overlap = 200
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

    struct EmbeddingSection: Codable {
        var provider: String?
        var model: String?
        var dimension: Int?
    }

    struct SearchSection: Codable {
        var semantic_weight: Double?
        var rrf_k: Int?
        var multi_hop_enabled: Bool?
        var multi_hop_depth: Int?
        var output_format: String?
    }

    struct IndexingSection: Codable {
        var exclude: [String]?
        var include_extensions: [String]?
        var max_file_size: Int?
        var chunk_size: Int?
        var chunk_overlap: Int?
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

    /// Converts the intermediate TOML structure to a PartialConfig.
    func toPartialConfig() -> PartialConfig {
        var config = PartialConfig()

        // Embedding section
        if let embedding {
            config.embeddingProvider = embedding.provider
            config.embeddingModel = embedding.model
            config.embeddingDimension = embedding.dimension
        }

        // Search section
        if let search {
            config.semanticWeight = search.semantic_weight.map { Float($0) }
            config.rrfK = search.rrf_k
            config.multiHopEnabled = search.multi_hop_enabled
            config.multiHopDepth = search.multi_hop_depth
            config.outputFormat = search.output_format
        }

        // Indexing section
        if let indexing {
            config.excludePatterns = indexing.exclude
            config.includeExtensions = indexing.include_extensions
            config.maxFileSize = indexing.max_file_size
            config.chunkSize = indexing.chunk_size
            config.chunkOverlap = indexing.chunk_overlap
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

        return config
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
    /// - Returns: Complete merged configuration.
    static func loadLayered(
        cli cliConfig: PartialConfig = .empty,
        env envConfig: PartialConfig = .empty,
        projectDirectory: String,
        globalConfigDirectory: String? = nil
    ) throws -> Config {
        var partials: [PartialConfig] = [cliConfig, envConfig]

        // Try loading project config
        let projectLoader = TOMLConfigLoader.forProject(at: projectDirectory)
        if FileManager.default.fileExists(atPath: projectLoader.filePath) {
            let projectConfig = try projectLoader.load()
            partials.append(projectConfig)
        }

        // Try loading global config
        let globalLoader = TOMLConfigLoader.forGlobal(configDirectory: globalConfigDirectory)
        if FileManager.default.fileExists(atPath: globalLoader.filePath) {
            let globalConfig = try globalLoader.load()
            partials.append(globalConfig)
        }

        return Config.merge(partials)
    }
}
