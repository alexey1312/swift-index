// MARK: - Command Utilities

import Foundation
import Logging
import SwiftIndexCore

// MARK: - CLI Utilities Namespace

/// Namespace for CLI utility functions.
enum CLIUtils {
    // MARK: - Logger Factory

    /// Creates a logger with appropriate log level based on verbose flag.
    ///
    /// - Parameter verbose: If true, sets log level to debug; otherwise info.
    /// - Returns: A configured Logger instance.
    static func makeLogger(verbose: Bool) -> Logger {
        var logger = Logger(label: "com.swiftindex.cli")
        logger.logLevel = verbose ? .debug : .info
        return logger
    }

    // MARK: - Path Resolution

    /// Resolves a path to an absolute path.
    ///
    /// Handles:
    /// - Tilde expansion (~)
    /// - Relative paths (converted to absolute)
    /// - Already absolute paths (returned as-is)
    ///
    /// - Parameter path: The path to resolve.
    /// - Returns: The absolute path string.
    static func resolvePath(_ path: String) -> String {
        let expandedPath = (path as NSString).expandingTildeInPath

        if expandedPath.hasPrefix("/") {
            return expandedPath
        }

        let currentDirectory = FileManager.default.currentDirectoryPath
        return (currentDirectory as NSString).appendingPathComponent(expandedPath)
    }

    // MARK: - Configuration Loading

    /// Loads configuration from file or uses defaults.
    ///
    /// Configuration is merged from multiple sources with priority:
    /// CLI > Environment > Project > Global > Defaults
    ///
    /// - Parameters:
    ///   - configPath: Optional path to a configuration file.
    ///   - logger: Logger for debug output.
    /// - Returns: The merged configuration.
    /// - Throws: ConfigError if the config file cannot be loaded.
    static func loadConfig(from configPath: String?, logger: Logger) throws -> Config {
        var partials: [PartialConfig] = []

        // Load from file if specified
        if let configPath = configPath {
            let resolvedPath = resolvePath(configPath)
            logger.debug("Loading config from: \(resolvedPath)")

            guard FileManager.default.fileExists(atPath: resolvedPath) else {
                throw ConfigError.fileNotFound(resolvedPath)
            }

            // TODO: Implement actual TOML parsing
            // let fileLoader = TOMLConfigLoader(path: resolvedPath)
            // let filePartial = try fileLoader.load()
            // partials.append(filePartial)

            logger.debug("Config file found, parsing not yet implemented")
        }

        // Load from environment
        let envPartial = loadEnvironmentConfig()
        if envPartial != .empty {
            partials.append(envPartial)
            logger.debug("Loaded environment configuration")
        }

        // Merge all partials
        return Config.merge(partials)
    }

    /// Loads configuration from environment variables.
    ///
    /// Supported environment variables:
    /// - SWIFTINDEX_EMBEDDING_PROVIDER
    /// - SWIFTINDEX_EMBEDDING_MODEL
    /// - SWIFTINDEX_VOYAGE_API_KEY
    /// - SWIFTINDEX_OPENAI_API_KEY
    /// - SWIFTINDEX_LOG_LEVEL
    ///
    /// - Returns: A partial configuration with environment values.
    static func loadEnvironmentConfig() -> PartialConfig {
        var partial = PartialConfig()

        if let provider = ProcessInfo.processInfo.environment["SWIFTINDEX_EMBEDDING_PROVIDER"] {
            partial.embeddingProvider = provider
        }

        if let model = ProcessInfo.processInfo.environment["SWIFTINDEX_EMBEDDING_MODEL"] {
            partial.embeddingModel = model
        }

        if let voyageKey = ProcessInfo.processInfo.environment["SWIFTINDEX_VOYAGE_API_KEY"] {
            partial.voyageAPIKey = voyageKey
        }

        // Also check standard VOYAGE_API_KEY
        if partial.voyageAPIKey == nil,
            let voyageKey = ProcessInfo.processInfo.environment["VOYAGE_API_KEY"]
        {
            partial.voyageAPIKey = voyageKey
        }

        if let openAIKey = ProcessInfo.processInfo.environment["SWIFTINDEX_OPENAI_API_KEY"] {
            partial.openAIAPIKey = openAIKey
        }

        // Also check standard OPENAI_API_KEY
        if partial.openAIAPIKey == nil,
            let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        {
            partial.openAIAPIKey = openAIKey
        }

        if let logLevel = ProcessInfo.processInfo.environment["SWIFTINDEX_LOG_LEVEL"] {
            partial.logLevel = logLevel
        }

        return partial
    }
}
