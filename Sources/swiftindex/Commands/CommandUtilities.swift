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

    // MARK: - Executable Path Resolution

    /// Result of executable path resolution with metadata about the source.
    struct ExecutablePathResult {
        let path: String
        let isDevelopmentBuild: Bool
        let source: ExecutablePathSource
    }

    /// Source of resolved executable path.
    enum ExecutablePathSource: String {
        case explicitOverride = "explicit override"
        case homebrew = "Homebrew"
        case mise
        case pathLookup = "PATH"
        case currentExecutable = "current executable"
    }

    /// Resolves the swiftindex executable path with intelligent detection.
    ///
    /// Resolution priority:
    /// 1. Explicit override via `--binary-path`
    /// 2. Homebrew path (`/opt/homebrew/bin/swiftindex`) — ARM macOS only
    /// 3. mise shim (`~/.local/share/mise/shims/swiftindex`)
    /// 4. `which swiftindex` PATH lookup
    /// 5. Fallback to `CommandLine.arguments[0]` with dev build warning
    ///
    /// - Parameter explicitPath: Optional explicit path override (from `--binary-path`).
    /// - Returns: Resolved path with metadata about the source and dev build status.
    static func resolveExecutablePath(explicitPath: String? = nil) -> ExecutablePathResult {
        let fm = FileManager.default

        // 1. Explicit override
        if let explicitPath {
            return ExecutablePathResult(
                path: resolvePath(explicitPath),
                isDevelopmentBuild: false,
                source: .explicitOverride
            )
        }

        // 2. Check Homebrew path (ARM macOS only, Intel not supported)
        let homebrewPath = "/opt/homebrew/bin/swiftindex"
        if fm.fileExists(atPath: homebrewPath) {
            return ExecutablePathResult(path: homebrewPath, isDevelopmentBuild: false, source: .homebrew)
        }

        // 3. Check mise shim
        let miseShimPath = ("~/.local/share/mise/shims/swiftindex" as NSString).expandingTildeInPath
        if fm.fileExists(atPath: miseShimPath) {
            return ExecutablePathResult(path: miseShimPath, isDevelopmentBuild: false, source: .mise)
        }

        // 4. Try `which swiftindex`
        if let path = runWhichSwiftindex() {
            return ExecutablePathResult(
                path: path,
                isDevelopmentBuild: isDevelopmentPath(path),
                source: .pathLookup
            )
        }

        // 5. Fall back to current executable
        let current = resolvePath(CommandLine.arguments[0])
        return ExecutablePathResult(
            path: current,
            isDevelopmentBuild: isDevelopmentPath(current),
            source: .currentExecutable
        )
    }

    /// Runs `which swiftindex` to find the binary in PATH.
    private static func runWhichSwiftindex() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["swiftindex"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Checks if a path appears to be a development build.
    private static func isDevelopmentPath(_ path: String) -> Bool {
        [".build/debug/", ".build/release/", "DerivedData/", ".swiftpm/"]
            .contains { path.contains($0) }
    }

    // MARK: - Configuration Loading

    /// Loads configuration from file or uses defaults.
    ///
    /// Configuration is merged from multiple sources with priority:
    /// CLI > Environment > Project > Global > Defaults
    ///
    /// - Parameters:
    ///   - configPath: Optional explicit path to a configuration file.
    ///   - projectDirectory: Directory for auto-discovering `.swiftindex.toml`.
    ///   - logger: Logger for debug output.
    /// - Returns: The merged configuration.
    /// - Throws: ConfigError if the explicit config file cannot be loaded.
    static func loadConfig(
        from configPath: String?,
        projectDirectory: String = FileManager.default.currentDirectoryPath,
        logger: Logger
    ) throws -> Config {
        let envPartial = loadEnvironmentConfig()
        if envPartial != .empty {
            logger.debug("Loaded environment configuration")
        }

        // If explicit --config flag: load only that specific file
        if let configPath {
            let resolvedPath = resolvePath(configPath)
            logger.debug("Loading config from explicit path: \(resolvedPath)")

            guard FileManager.default.fileExists(atPath: resolvedPath) else {
                throw ConfigError.fileNotFound(resolvedPath)
            }

            let fileLoader = TOMLConfigLoader(filePath: resolvedPath)
            let filePartial = try fileLoader.load()
            return Config.merge([envPartial, filePartial])
        }

        // Auto-discovery: project .swiftindex.toml + global ~/.swiftindex.toml
        logger.debug("Auto-discovering config from: \(projectDirectory)")
        return try TOMLConfigLoader.loadLayered(
            env: envPartial,
            projectDirectory: projectDirectory
        )
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
