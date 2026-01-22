// MARK: - Init Command

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

/// Command to initialize SwiftIndex configuration in a project.
///
/// Usage:
///   swiftindex init
///   swiftindex init --provider mlx
///   swiftindex init --force
struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize SwiftIndex configuration for a project",
        discussion: """
        Creates a `.swiftindex.toml` configuration file in the current
        directory with sensible defaults for Swift projects.

        The configuration can be customized later by editing the file
        or by passing options to this command.

        Existing configuration files will not be overwritten unless
        --force is specified.
        """
    )

    // MARK: - Options

    @Option(
        name: .shortAndLong,
        help: "Embedding provider to use (mlx, ollama, voyage, openai, swift)"
    )
    var provider: String?

    @Option(
        name: .shortAndLong,
        help: "Embedding model name"
    )
    var model: String?

    @Flag(
        name: .shortAndLong,
        help: "Overwrite existing configuration"
    )
    var force: Bool = false

    @Flag(
        name: .shortAndLong,
        help: "Enable verbose debug output"
    )
    var verbose: Bool = false

    // MARK: - Execution

    mutating func run() async throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        logger.info("Initializing SwiftIndex configuration")

        let configPath = ".swiftindex.toml"
        let fullPath = FileManager.default.currentDirectoryPath + "/" + configPath

        // Check if config already exists
        if FileManager.default.fileExists(atPath: fullPath), !force {
            print("Configuration file already exists: \(configPath)")
            print("Use --force to overwrite.")
            throw ExitCode.failure
        }

        // Detect project type and suggest appropriate settings
        let projectInfo = detectProjectInfo()
        logger.debug("Detected project info: \(projectInfo)")

        var resolvedProvider = provider ?? "mlx"
        var resolvedModel = model ?? defaultModel(for: resolvedProvider)

        if usesMLX(provider: resolvedProvider), !isMetalToolchainAvailable() {
            print("MetalToolchain not found. MLX requires Metal shader tools.")
            let wantsInstall = promptYesNo(
                "Install MetalToolchain now? (run: xcode-select --install) [Y/n]",
                defaultYes: true
            )
            if !wantsInstall {
                let wantsFallback = promptYesNo(
                    "Switch to Swift Embeddings (CPU) defaults instead? [Y/n]",
                    defaultYes: true
                )
                if wantsFallback {
                    resolvedProvider = "swift"
                    resolvedModel = defaultModel(for: resolvedProvider)
                    print("Using Swift Embeddings defaults instead of MLX.")
                } else {
                    print("Cannot continue without MetalToolchain for MLX.")
                    throw ExitCode.failure
                }
            } else {
                print("Please install MetalToolchain and re-run if MLX fails to load.")
            }
        }

        // Generate configuration content
        let configContent = generateConfigContent(
            provider: resolvedProvider,
            model: resolvedModel,
            projectInfo: projectInfo
        )

        // Write configuration file
        do {
            try configContent.write(toFile: fullPath, atomically: true, encoding: .utf8)
            print("Created configuration file: \(configPath)")
            print("")
            printConfigSummary(provider: resolvedProvider, model: resolvedModel)
        } catch {
            logger.error("Failed to write configuration: \(error.localizedDescription)")
            throw error
        }

        // Suggest next steps
        print("")
        print("Next steps:")
        print("  1. Review and customize .swiftindex.toml")
        print("  2. Run 'swiftindex index' to build the index")
        print("  3. Run 'swiftindex search <query>' to search your code")

        logger.info("Initialization completed")
    }

    // MARK: - Private Methods

    private func detectProjectInfo() -> ProjectInfo {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath

        var info = ProjectInfo()

        // Check for Swift Package Manager
        if fm.fileExists(atPath: cwd + "/Package.swift") {
            info.isSPM = true
        }

        // Check for Xcode project
        let contents = (try? fm.contentsOfDirectory(atPath: cwd)) ?? []
        info.hasXcodeProject = contents.contains { $0.hasSuffix(".xcodeproj") }
        info.hasXcodeWorkspace = contents.contains { $0.hasSuffix(".xcworkspace") }

        // Check for CocoaPods
        if fm.fileExists(atPath: cwd + "/Podfile") {
            info.hasCocoaPods = true
        }

        // Check for Carthage
        if fm.fileExists(atPath: cwd + "/Cartfile") {
            info.hasCarthage = true
        }

        return info
    }

    private func generateConfigContent(
        provider: String,
        model: String?,
        projectInfo: ProjectInfo
    ) -> String {
        var lines: [String] = []

        // Header comment
        lines.append("# SwiftIndex Configuration")
        lines.append("# Generated by 'swiftindex init'")
        lines.append("")

        // Embedding section
        lines.append("[embedding]")
        lines.append("# Provider options: mlx, swift, ollama, voyage, openai")
        lines.append("provider = \"\(provider)\"")
        if let model {
            lines.append("model = \"\(model)\"")
        } else {
            lines.append("# model = \"\(suggestedModel(for: provider))\"")
        }
        if let dimension = defaultDimension(for: provider, model: model) {
            if self.model == nil {
                lines.append("dimension = \(dimension)")
            } else {
                lines.append("# dimension = \(dimension)")
            }
        } else {
            lines.append("# dimension = 384")
        }
        lines.append("")
        lines.append("# Provider examples and defaults:")
        lines.append("# MLX (Apple Silicon + Metal toolchain)")
        lines.append("# provider = \"mlx\"")
        lines.append("# model = \"\(suggestedModel(for: "mlx"))\"")
        lines.append("# Swift Embeddings (CPU)")
        lines.append("# provider = \"swift\"")
        lines.append("# model = \"\(suggestedModel(for: "swift"))\"")
        lines.append("# Ollama (local server)")
        lines.append("# provider = \"ollama\"")
        lines.append("# model = \"nomic-embed-text\"")
        lines.append("# Voyage (cloud)")
        lines.append("# provider = \"voyage\"")
        lines.append("# model = \"voyage-large-2\"")
        lines.append("# OpenAI (cloud)")
        lines.append("# provider = \"openai\"")
        lines.append("# model = \"text-embedding-3-large\"")
        lines.append("")

        // Search section
        lines.append("[search]")
        lines.append("semantic_weight = 0.7")
        lines.append("rrf_k = 60")
        lines.append("multi_hop_enabled = false")
        lines.append("multi_hop_depth = 2")
        lines.append("")

        // Indexing section
        lines.append("[indexing]")

        // Build exclude patterns based on project type
        var excludePatterns = [".git", ".build", "DerivedData"]

        if projectInfo.hasCocoaPods {
            excludePatterns.append("Pods")
        }

        if projectInfo.hasCarthage {
            excludePatterns.append("Carthage")
        }

        let excludeStr = excludePatterns.map { "\"\($0)\"" }.joined(separator: ", ")
        lines.append("exclude = [\(excludeStr)]")

        lines.append("include_extensions = [\".swift\", \".m\", \".h\"]")
        lines.append("max_file_size = 1000000")
        lines.append("chunk_size = 1500")
        lines.append("chunk_overlap = 200")
        lines.append("")

        // Storage section
        lines.append("[storage]")
        lines.append("index_path = \".swiftindex\"")
        lines.append("# cache_path = \"~/.cache/swiftindex\"")
        lines.append("")

        // API keys section (commented out for security)
        lines.append("[api_keys]")
        lines.append("# Uncomment and fill in if using cloud providers")
        lines.append("# voyage = \"your-voyage-api-key\"")
        lines.append("# openai = \"your-openai-api-key\"")
        lines.append("")

        // Watch section
        lines.append("[watch]")
        lines.append("debounce_ms = 500")
        lines.append("")

        // Logging section
        lines.append("[logging]")
        lines.append("level = \"info\"")

        return lines.joined(separator: "\n")
    }

    private func printConfigSummary(provider: String?, model: String?) {
        print("Configuration summary:")
        print("  Provider: \(provider ?? "auto-detect")")
        print("  Model: \(model ?? "default")")
        print("  Index path: .swiftindex/")
    }

    private func usesMLX(provider: String) -> Bool {
        provider.lowercased() == "mlx"
    }

    private func defaultModel(for provider: String) -> String? {
        switch provider.lowercased() {
        case "mlx":
            "mlx-community/bge-small-en-v1.5-4bit"
        case "swift", "swift-embeddings", "swiftembeddings":
            "all-MiniLM-L6-v2"
        default:
            nil
        }
    }

    private func suggestedModel(for provider: String) -> String {
        if let defaultModel = defaultModel(for: provider) {
            return defaultModel
        }
        switch provider.lowercased() {
        case "ollama":
            return "nomic-embed-text"
        case "voyage":
            return "voyage-large-2"
        case "openai":
            return "text-embedding-3-large"
        default:
            return "bge-small-en-v1.5"
        }
    }

    private func defaultDimension(for provider: String, model: String?) -> Int? {
        let resolvedModel = model ?? defaultModel(for: provider)
        guard let resolvedModel else {
            return nil
        }
        switch resolvedModel {
        case "mlx-community/bge-small-en-v1.5-4bit",
             "all-MiniLM-L6-v2",
             "bge-small-en-v1.5":
            return 384
        case "mlx-community/bge-large-en-v1.5-4bit":
            return 1024
        case "mlx-community/nomic-embed-text-v1.5-4bit":
            return 768
        default:
            return nil
        }
    }

    private func isMetalToolchainAvailable() -> Bool {
        if let override = ProcessInfo.processInfo.environment["SWIFTINDEX_METALTOOLCHAIN_OVERRIDE"]?.lowercased() {
            switch override {
            case "present":
                return true
            case "missing":
                return false
            default:
                break
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "metal"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func promptYesNo(_ prompt: String, defaultYes: Bool) -> Bool {
        print(prompt, terminator: " ")
        guard let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !response.isEmpty
        else {
            return defaultYes
        }
        let lower = response.lowercased()
        if lower.hasPrefix("y") { return true }
        if lower.hasPrefix("n") { return false }
        return defaultYes
    }
}

// MARK: - ProjectInfo

private struct ProjectInfo {
    var isSPM: Bool = false
    var hasXcodeProject: Bool = false
    var hasXcodeWorkspace: Bool = false
    var hasCocoaPods: Bool = false
    var hasCarthage: Bool = false
}
