// MARK: - Init Command

import ArgumentParser
import Foundation
import Logging
import Noora
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

        When running in an interactive terminal, the command guides you
        through configuration choices. In non-interactive environments,
        it uses defaults (or `--provider` / `--model` if provided).

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
        let ui = Noora()
        let interactiveTerminal = isInteractiveTerminal()

        // Check if config already exists
        if FileManager.default.fileExists(atPath: fullPath), !force {
            if interactiveTerminal {
                let overwrite = ui.yesOrNoChoicePrompt(
                    question: "Configuration file already exists. Overwrite it?",
                    defaultAnswer: false,
                    description: "Use --force to skip this prompt."
                )
                if !overwrite {
                    print("Configuration file already exists: \(configPath)")
                    print("Use --force to overwrite.")
                    throw ExitCode.failure
                }
            } else {
                print("Configuration file already exists: \(configPath)")
                print("Use --force to overwrite.")
                throw ExitCode.failure
            }
        }

        // Detect project type and suggest appropriate settings
        let projectInfo = detectProjectInfo()
        logger.debug("Detected project info: \(projectInfo)")

        let selections = await InitWizard(
            ui: ui,
            logger: logger,
            providerFlag: provider,
            modelFlag: model,
            interactiveTerminal: interactiveTerminal
        ).run()

        // Generate configuration content
        let configContent = generateConfigContent(
            provider: selections.embeddingProvider.configValue,
            model: selections.embeddingModel,
            llmProvider: selections.llmProvider,
            projectInfo: projectInfo
        )

        // Write configuration file
        do {
            try configContent.write(toFile: fullPath, atomically: true, encoding: .utf8)
            print("Created configuration file: \(configPath)")
            print("")
            printConfigSummary(
                provider: selections.embeddingProvider.configValue,
                model: selections.embeddingModel,
                llmProvider: selections.llmProvider
            )
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
        llmProvider: LLMProviderOption?,
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
        lines.append("# Gemini (Google AI)")
        lines.append("# provider = \"gemini\"")
        lines.append("# model = \"text-embedding-004\"")
        lines.append("")

        // Search section
        lines.append("[search]")
        lines.append("semantic_weight = 0.7")
        lines.append("rrf_k = 60")
        lines.append("multi_hop_enabled = true")
        lines.append("multi_hop_depth = 2")
        lines.append("output_format = \"toon\"  # toon (token-optimized), human, or json")
        lines.append("")
        lines.append("# Search defaults (can be overridden via CLI flags)")
        lines.append("limit = 20                      # default --limit")
        lines.append("expand_query_by_default = false # default --expand-query")
        lines.append("synthesize_by_default = false   # default --synthesize")
        lines.append("# default_extensions = [\"swift\", \"ts\"]  # default --extensions (empty = all)")
        lines.append("# default_path_filter = \"Sources/**\"     # default --path-filter (glob syntax)")
        lines.append("")
        lines.append("# LLM-powered search enhancements (query expansion, result synthesis)")
        lines.append("# Requires LLM provider access (mlx, claude-code-cli, codex-cli, ollama, or openai)")
        lines.append("[search.enhancement]")
        let llmEnabled = llmProvider != nil
        lines.append("enabled = \(llmEnabled ? "true" : "false")  # opt-in - enable for LLM-powered features")
        lines.append("")
        lines.append("# Utility tier - fast operations (query expansion, follow-ups)")
        lines.append("[search.enhancement.utility]")
        let resolvedLLMProvider = llmProvider?.configValue ?? "mlx"
        lines.append("provider = \"\(resolvedLLMProvider)\"  # mlx | claude-code-cli | codex-cli | ollama | openai")
        lines.append("# model = \"haiku\"  # default: haiku (cost-efficient for descriptions)")
        lines.append("timeout = 60")
        lines.append("")
        lines.append("# Synthesis tier - deep analysis (result summarization)")
        lines.append("[search.enhancement.synthesis]")
        lines.append("provider = \"\(resolvedLLMProvider)\"  # mlx | claude-code-cli | codex-cli | ollama | openai")
        lines.append("# model = \"claude-sonnet-4-20250514\"  # optional override")
        lines.append("timeout = 120")
        lines.append("")
        lines.append("# Provider examples:")
        lines.append("# mlx: Uses MLX for local text generation (Apple Silicon only, fully offline)")
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

        lines.append("include_extensions = [\".swift\", \".m\", \".h\", \".md\"]")
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

    private func printConfigSummary(
        provider: String?,
        model: String?,
        llmProvider: LLMProviderOption?
    ) {
        print("Configuration summary:")
        print("  Provider: \(provider ?? "auto-detect")")
        print("  Model: \(model ?? "default")")
        if let llmProvider {
            print("  LLM enhancements: enabled (\(llmProvider.configValue))")
        } else {
            print("  LLM enhancements: disabled")
        }
        print("  Index path: .swiftindex/")
    }

    private func requiresExplicitDimension(provider: String) -> Bool {
        // MLX, Voyage, and OpenAI require explicit dimension in config
        // Swift Embeddings auto-detects from model
        switch provider.lowercased() {
        case "mlx", "voyage", "openai", "gemini":
            true
        default:
            false
        }
    }

    private func suggestedModel(for provider: String) -> String {
        if let model = defaultModel(for: provider) {
            return model
        }
        switch provider.lowercased() {
        case "ollama":
            return "nomic-embed-text"
        case "voyage":
            return "voyage-large-2"
        case "openai":
            return "text-embedding-3-large"
        case "gemini":
            return "text-embedding-004"
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
        case "text-embedding-004":
            return 768
        default:
            return nil
        }
    }
}

// MARK: - Init Wizard

private struct InitWizard {
    let ui: Noora
    let logger: Logger
    let providerFlag: String?
    let modelFlag: String?
    let interactiveTerminal: Bool

    func run() async -> InitSelections {
        if !interactiveTerminal {
            return resolveDefaults()
        }

        let mode = ui.singleChoicePrompt(
            title: "SwiftIndex init",
            question: "How would you like to configure SwiftIndex?",
            options: orderedOptions(InitMode.allCases, preselected: .interactive),
            description: "You can always edit .swiftindex.toml later."
        )

        if mode == .defaults {
            return resolveDefaults()
        }

        var provider = selectEmbeddingProvider()
        provider = validateEmbeddingProvider(provider)
        let model = selectEmbeddingModel(for: provider)
        let llmProvider = selectLLMProvider()

        // Setup OAuth token if Claude Code OAuth was selected
        if llmProvider == .claudeCodeOAuth {
            await setupClaudeCodeOAuth()
        }

        return InitSelections(
            embeddingProvider: provider,
            embeddingModel: model,
            llmProvider: llmProvider
        )
    }

    private func resolveDefaults() -> InitSelections {
        let resolvedProvider = EmbeddingProviderOption.fromFlag(providerFlag) ?? .mlx
        let resolvedModel = modelFlag ?? defaultModel(for: resolvedProvider.configValue)
        let validatedProvider = validateEmbeddingProvider(resolvedProvider, allowPrompts: false)
        let finalModel = resolvedProvider == validatedProvider
            ? resolvedModel
            : defaultModel(for: validatedProvider.configValue)

        return InitSelections(
            embeddingProvider: validatedProvider,
            embeddingModel: finalModel,
            llmProvider: .mlx // Default to MLX for LLM enhancement
        )
    }

    private func selectEmbeddingProvider() -> EmbeddingProviderOption {
        let preselected = EmbeddingProviderOption.fromFlag(providerFlag)
        return ui.singleChoicePrompt(
            title: "Embeddings",
            question: "Select an embedding provider:",
            options: orderedOptions(EmbeddingProviderOption.allCases, preselected: preselected),
            description: "MLX is fastest on Apple Silicon. Cloud providers require API keys."
        )
    }

    private func selectEmbeddingModel(for provider: EmbeddingProviderOption) -> String? {
        switch provider {
        case .mlx:
            selectModel(
                title: "Embeddings",
                question: "Select an MLX embedding model:",
                options: MLXModelOption.allCases,
                customOption: .custom,
                preselectedModel: modelFlag
            ) { $0.modelName }
        case .swift:
            selectModel(
                title: "Embeddings",
                question: "Select a Swift Embeddings model:",
                options: SwiftModelOption.allCases,
                customOption: .custom,
                preselectedModel: modelFlag
            ) { $0.modelName }
        case .ollama:
            selectModel(
                title: "Embeddings",
                question: "Select an Ollama embedding model:",
                options: OllamaModelOption.allCases,
                customOption: .custom,
                preselectedModel: modelFlag
            ) { $0.modelName }
        case .voyage:
            selectModel(
                title: "Embeddings",
                question: "Select a Voyage embedding model:",
                options: VoyageModelOption.allCases,
                customOption: .custom,
                preselectedModel: modelFlag
            ) { $0.modelName }
        case .openai:
            selectModel(
                title: "Embeddings",
                question: "Select an OpenAI embedding model:",
                options: OpenAIModelOption.allCases,
                customOption: .custom,
                preselectedModel: modelFlag
            ) { $0.modelName }
        case .gemini:
            selectModel(
                title: "Embeddings",
                question: "Select a Gemini embedding model:",
                options: GeminiModelOption.allCases,
                customOption: .custom,
                preselectedModel: modelFlag
            ) { $0.modelName }
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func selectModel<Option: CaseIterable & CustomStringConvertible & Equatable>(
        title: String,
        question: String,
        options: [Option],
        customOption: Option,
        preselectedModel: String?,
        modelName: (Option) -> String?
    ) -> String? {
        var ordered = options
        var customDefault: String?

        if let preselectedModel,
           let matched = options.first(where: { modelName($0)?.lowercased() == preselectedModel.lowercased() })
        {
            ordered = orderedOptions(options, preselected: matched)
        } else if let preselectedModel {
            ordered = orderedOptions(options, preselected: customOption)
            customDefault = preselectedModel
        }

        let selection = ui.singleChoicePrompt(
            title: TerminalText(stringLiteral: title),
            question: TerminalText(stringLiteral: question),
            options: ordered,
            description: "Custom lets you provide any model identifier."
        )

        if selection == customOption {
            let descriptionText: TerminalText? = customDefault
                .map { TerminalText(stringLiteral: "Press Enter to use '\($0)'.") }
            let rules: [ValidatableRule] = customDefault == nil
                ? [NonEmptyValidationRule(error: "Model name cannot be empty.")]
                : []
            let input = ui.textPrompt(
                title: "Custom model",
                prompt: "Enter model identifier:",
                description: descriptionText,
                validationRules: rules
            )
            if input.isEmpty {
                return customDefault
            }
            return input
        }

        return modelName(selection)
    }

    private func selectLLMProvider() -> LLMProviderOption? {
        let enableLLM = ui.yesOrNoChoicePrompt(
            title: "Search enhancements",
            question: "Enable LLM-powered query expansion and synthesis?",
            defaultAnswer: false,
            description: "MLX (local), Claude Code, Codex CLI, Ollama, or OpenAI."
        )

        guard enableLLM else {
            return nil
        }

        // Default to MLX (fully local on Apple Silicon)
        var provider = ui.singleChoicePrompt(
            title: "Search enhancements",
            question: "Select an LLM provider:",
            options: orderedOptions(LLMProviderOption.allCases, preselected: .mlx),
            description: "MLX runs fully local on Apple Silicon. CLI providers require tools."
        )

        while !isLLMProviderAvailable(provider) {
            let retry = ui.yesOrNoChoicePrompt(
                question: "\(provider.description) is not available. Choose another provider?",
                defaultAnswer: true
            )
            if !retry {
                return nil
            }
            provider = ui.singleChoicePrompt(
                title: "Search enhancements",
                question: "Select an LLM provider:",
                options: orderedOptions(LLMProviderOption.allCases, preselected: provider)
            )
        }

        return provider
    }

    private func validateEmbeddingProvider(
        _ provider: EmbeddingProviderOption,
        allowPrompts: Bool = true
    ) -> EmbeddingProviderOption {
        guard provider == .mlx, !isMetalToolchainAvailable() else {
            return provider
        }

        print("MetalToolchain not found. MLX requires Metal shader tools.")

        if !allowPrompts {
            print("Falling back to Swift Embeddings defaults.")
            return .swift
        }

        let wantsFallback = ui.yesOrNoChoicePrompt(
            question: "Switch to Swift Embeddings (CPU) defaults instead?",
            defaultAnswer: true,
            description: "Requires no Metal toolchain."
        )
        if wantsFallback {
            return .swift
        }

        let chooseAnother = ui.yesOrNoChoicePrompt(
            question: "Choose another provider instead?",
            defaultAnswer: true
        )
        if chooseAnother {
            let newProvider = selectEmbeddingProvider()
            return validateEmbeddingProvider(newProvider, allowPrompts: allowPrompts)
        }

        print("Cannot continue without MetalToolchain for MLX.")
        exit(ExitCode.failure.rawValue)
    }

    private func isLLMProviderAvailable(_ provider: LLMProviderOption) -> Bool {
        switch provider {
        case .mlx:
            // MLX is always available on Apple Silicon (this product is arm64-only)
            true
        case .claudeCodeOAuth:
            // OAuth is always available on Apple platforms
            true
        case .claudeCodeCLI:
            isCommandAvailable("claude")
        case .codexCLI:
            isCommandAvailable("codex")
        case .ollama:
            true
        case .openai:
            true
        case .gemini:
            // Gemini API is always available (just needs key)
            true
        case .geminiCLI:
            isCommandAvailable("gemini")
        }
    }

    private func isCommandAvailable(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", command]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            logger.debug("Command availability check failed: \(command)")
            return false
        }
    }

    private func setupClaudeCodeOAuth() async {
        print("\\nClaude Code OAuth Setup")
        print("───────────────────────\\n")

        // Check for existing token
        if let existingToken = try? ClaudeCodeAuthManager.getToken() {
            print("✓ Already authenticated (token found in Keychain)")
            print("  Token: \\(tokenPreview(existingToken))\\n")
            return
        }

        // Try automatic flow first
        if await ClaudeCodeAuthManager.isCLIAvailable() {
            print("Running automatic OAuth flow...")
            print("A browser window will open for authentication.\\n")

            do {
                let token = try await ClaudeCodeAuthManager.setupOAuthToken()
                try ClaudeCodeAuthManager.saveToken(token)
                print("✓ OAuth token saved successfully\\n")
            } catch {
                logger.error("Automatic OAuth flow failed: \\(error.localizedDescription)")
                await manualOAuthFallback()
            }
        } else {
            print("⚠️  'claude' CLI not found")
            print("\\nTo install Claude Code CLI:")
            print("  npm install -g @anthropic-ai/claude-code\\n")
            await manualOAuthFallback()
        }
    }

    private func manualOAuthFallback() async {
        let tryManual = ui.yesOrNoChoicePrompt(
            question: "Try manual token input?",
            defaultAnswer: true,
            description: "Run 'claude setup-token' and paste the generated token."
        )

        guard tryManual else {
            print("\\nSkipping OAuth setup. You can set it up later with:")
            print("  swiftindex auth login\\n")
            return
        }

        print("\\nManual Token Input")
        print("──────────────────")
        print("1. Run: claude setup-token")
        print("2. Copy the generated OAuth token")
        print("3. Paste it below\\n")

        let token = ui.textPrompt(
            title: nil,
            prompt: "OAuth Token",
            description: "Paste your Claude Code OAuth token",
            collapseOnAnswer: true,
            renderer: Renderer(),
            validationRules: []
        )

        // Validate and save
        do {
            try ClaudeCodeAuthManager.validateTokenFormat(token)
            try ClaudeCodeAuthManager.saveToken(token)
            print("✓ OAuth token saved successfully\\n")
        } catch {
            print("✗ Failed to save token: \\(error.localizedDescription)")
            print("\\nYou can set it up later with:")
            print("  swiftindex auth login\\n")
        }
    }

    private func tokenPreview(_ token: String) -> String {
        let prefixLength = min(10, token.count)
        return String(token.prefix(prefixLength)) + "***"
    }
}
