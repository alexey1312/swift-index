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
        print("  4. Add AGENTS.md and CLAUDE.md with project guidance (see README.md)")

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
        // Only write dimension for providers that require explicit dimension (MLX, Voyage, OpenAI)
        // Swift Embeddings and auto providers detect dimension automatically
        if requiresExplicitDimension(provider: provider) {
            if let dimension = defaultDimension(for: provider, model: model) {
                lines.append("dimension = \(dimension)")
            }
        } else {
            lines.append("# dimension is auto-detected from provider")
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
        lines.append("# API keys are read from environment variables:")
        lines.append("#   VOYAGE_API_KEY for Voyage")
        lines.append("#   OPENAI_API_KEY for OpenAI")
        lines.append("")

        // Search section
        lines.append("[search]")
        lines.append("semantic_weight = 0.7")
        lines.append("rrf_k = 60")
        lines.append("multi_hop_enabled = false")
        lines.append("multi_hop_depth = 2")
        lines.append("output_format = \"human\"  # human, json, or toon (token-optimized)")
        lines.append("")
        lines.append("# LLM-powered search enhancements (query expansion, result synthesis)")
        lines.append("# Requires LLM provider access (claude-code-cli, codex-cli, ollama, or openai)")
        lines.append("[search.enhancement]")
        lines.append("enabled = false  # opt-in - enable for LLM-powered features")
        lines.append("")
        lines.append("# Utility tier - fast operations (query expansion, follow-ups)")
        lines.append("[search.enhancement.utility]")
        lines.append("provider = \"claude-code-cli\"  # claude-code-cli | codex-cli | ollama | openai")
        lines.append("# model = \"claude-haiku-4-5-20251001\"  # optional override")
        lines.append("timeout = 30")
        lines.append("")
        lines.append("# Synthesis tier - deep analysis (result summarization)")
        lines.append("[search.enhancement.synthesis]")
        lines.append("provider = \"claude-code-cli\"")
        lines.append("# model = \"claude-sonnet-4-20250514\"  # optional override")
        lines.append("timeout = 120")
        lines.append("")
        lines.append("# Provider examples:")
        lines.append("# claude-code-cli: Uses 'claude' CLI (requires: npm install -g @anthropic-ai/claude-code)")
        lines.append("# codex-cli: Uses 'codex' CLI (requires: npm install -g @openai/codex)")
        lines.append("# ollama: Uses local Ollama server (requires: ollama serve)")
        lines.append("# openai: Uses OpenAI API (requires: OPENAI_API_KEY env var)")
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

    private func requiresExplicitDimension(provider: String) -> Bool {
        // MLX, Voyage, and OpenAI require explicit dimension in config
        // Swift Embeddings auto-detects from model
        switch provider.lowercased() {
        case "mlx", "voyage", "openai":
            true
        default:
            false
        }
    }

    private func defaultModel(for provider: String) -> String? {
        switch provider.lowercased() {
        case "mlx":
            "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"
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
        // Qwen3 MLX models
        case "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ":
            return 1024
        case "mlx-community/Qwen3-Embedding-4B-4bit-DWQ":
            return 2048
        case "mlx-community/Qwen3-Embedding-8B-4bit-DWQ":
            return 4096
        // SwiftEmbeddings models
        case "all-MiniLM-L6-v2",
             "bge-small-en-v1.5":
            return 384
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
