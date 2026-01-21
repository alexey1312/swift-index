// MARK: - TOML Configuration Loader

import Foundation
import TOMLKit

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
/// [api_keys]
/// voyage = "voyage-api-key"
/// openai = "openai-api-key"
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
    /// Looks for `.swiftindex.toml` in the user's home directory.
    ///
    /// - Parameter homeDirectory: Optional home directory path. If nil, uses the current user's home.
    /// - Returns: A loader configured for the global config file.
    public static func forGlobal(homeDirectory: String? = nil) -> TOMLConfigLoader {
        let home = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
        let path = (home as NSString).appendingPathComponent(".swiftindex.toml")
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

        // Parse TOML
        let table: TOMLTable
        do {
            table = try TOMLTable(string: contents)
        } catch {
            throw ConfigError.invalidSyntax("Invalid TOML: \(error.localizedDescription)")
        }

        return try parseTable(table)
    }

    // MARK: - Parsing

    /// Parses a TOML table into a partial configuration.
    ///
    /// - Parameter table: The root TOML table.
    /// - Returns: A partial configuration with parsed values.
    /// - Throws: `ConfigError.invalidValue` if a value has an unexpected type.
    private func parseTable(_ table: TOMLTable) throws -> PartialConfig {
        var config = PartialConfig()

        // Parse [embedding] section
        if let embedding = table["embedding"]?.table {
            config.embeddingProvider = try parseString(embedding["provider"], key: "embedding.provider")
            config.embeddingModel = try parseString(embedding["model"], key: "embedding.model")
            config.embeddingDimension = try parseInt(embedding["dimension"], key: "embedding.dimension")
        }

        // Parse [search] section
        if let search = table["search"]?.table {
            config.semanticWeight = try parseFloat(search["semantic_weight"], key: "search.semantic_weight")
            config.rrfK = try parseInt(search["rrf_k"], key: "search.rrf_k")
            config.multiHopEnabled = try parseBool(search["multi_hop_enabled"], key: "search.multi_hop_enabled")
            config.multiHopDepth = try parseInt(search["multi_hop_depth"], key: "search.multi_hop_depth")
        }

        // Parse [indexing] section
        if let indexing = table["indexing"]?.table {
            config.excludePatterns = try parseStringArray(indexing["exclude"], key: "indexing.exclude")
            config.includeExtensions = try parseStringArray(
                indexing["include_extensions"],
                key: "indexing.include_extensions"
            )
            config.maxFileSize = try parseInt(indexing["max_file_size"], key: "indexing.max_file_size")
            config.chunkSize = try parseInt(indexing["chunk_size"], key: "indexing.chunk_size")
            config.chunkOverlap = try parseInt(indexing["chunk_overlap"], key: "indexing.chunk_overlap")
        }

        // Parse [storage] section
        if let storage = table["storage"]?.table {
            config.indexPath = try parseString(storage["index_path"], key: "storage.index_path")
            config.cachePath = try parseString(storage["cache_path"], key: "storage.cache_path")
        }

        // Parse [api_keys] section
        if let apiKeys = table["api_keys"]?.table {
            config.voyageAPIKey = try parseString(apiKeys["voyage"], key: "api_keys.voyage")
            config.openAIAPIKey = try parseString(apiKeys["openai"], key: "api_keys.openai")
        }

        // Parse [watch] section
        if let watch = table["watch"]?.table {
            config.watchDebounceMs = try parseInt(watch["debounce_ms"], key: "watch.debounce_ms")
        }

        // Parse [logging] section
        if let logging = table["logging"]?.table {
            config.logLevel = try parseString(logging["level"], key: "logging.level")
        }

        return config
    }

    // MARK: - Type Parsing Helpers

    /// Parses an optional string value from a TOML value.
    private func parseString(_ value: TOMLValue?, key: String) throws -> String? {
        guard let value else { return nil }

        guard let stringValue = value.string else {
            throw ConfigError.invalidValue(
                key: key,
                message: "Expected string, got \(type(of: value))"
            )
        }

        return stringValue
    }

    /// Parses an optional integer value from a TOML value.
    private func parseInt(_ value: TOMLValue?, key: String) throws -> Int? {
        guard let value else { return nil }

        guard let intValue = value.int else {
            throw ConfigError.invalidValue(
                key: key,
                message: "Expected integer, got \(type(of: value))"
            )
        }

        return intValue
    }

    /// Parses an optional float value from a TOML value.
    private func parseFloat(_ value: TOMLValue?, key: String) throws -> Float? {
        guard let value else { return nil }

        // TOML stores floats as Double
        if let doubleValue = value.double {
            return Float(doubleValue)
        }

        // Also accept integers as floats
        if let intValue = value.int {
            return Float(intValue)
        }

        throw ConfigError.invalidValue(
            key: key,
            message: "Expected number, got \(type(of: value))"
        )
    }

    /// Parses an optional boolean value from a TOML value.
    private func parseBool(_ value: TOMLValue?, key: String) throws -> Bool? {
        guard let value else { return nil }

        guard let boolValue = value.bool else {
            throw ConfigError.invalidValue(
                key: key,
                message: "Expected boolean, got \(type(of: value))"
            )
        }

        return boolValue
    }

    /// Parses an optional string array from a TOML value.
    private func parseStringArray(_ value: TOMLValue?, key: String) throws -> [String]? {
        guard let value else { return nil }

        guard let array = value.array else {
            throw ConfigError.invalidValue(
                key: key,
                message: "Expected array, got \(type(of: value))"
            )
        }

        var result: [String] = []
        for (index, element) in array.enumerated() {
            guard let stringValue = element.string else {
                throw ConfigError.invalidValue(
                    key: "\(key)[\(index)]",
                    message: "Expected string in array, got \(type(of: element))"
                )
            }
            result.append(stringValue)
        }

        return result
    }
}

// MARK: - Layered Configuration Loading

extension TOMLConfigLoader {
    /// Loads configuration from multiple sources with layered priority.
    ///
    /// Sources are checked in order (highest to lowest priority):
    /// 1. CLI arguments (provided as `PartialConfig`)
    /// 2. Environment variables
    /// 3. Project `.swiftindex.toml`
    /// 4. Global `~/.swiftindex.toml`
    /// 5. Default values
    ///
    /// - Parameters:
    ///   - cliConfig: Configuration from CLI arguments (highest priority).
    ///   - envConfig: Configuration from environment variables.
    ///   - projectDirectory: Path to the project root directory.
    ///   - homeDirectory: Optional home directory path for global config. If nil, uses current user's home.
    /// - Returns: Complete merged configuration.
    public static func loadLayered(
        cli cliConfig: PartialConfig = .empty,
        env envConfig: PartialConfig = .empty,
        projectDirectory: String,
        homeDirectory: String? = nil
    ) -> Config {
        var partials: [PartialConfig] = [cliConfig, envConfig]

        // Try loading project config
        let projectLoader = TOMLConfigLoader.forProject(at: projectDirectory)
        if let projectConfig = try? projectLoader.load() {
            partials.append(projectConfig)
        }

        // Try loading global config
        let globalLoader = TOMLConfigLoader.forGlobal(homeDirectory: homeDirectory)
        if let globalConfig = try? globalLoader.load() {
            partials.append(globalConfig)
        }

        return Config.merge(partials)
    }
}
