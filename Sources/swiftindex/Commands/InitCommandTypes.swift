// MARK: - Init Command Types

import Foundation

// MARK: - Supporting Types

struct InitSelections {
    let embeddingProvider: EmbeddingProviderOption
    let embeddingModel: String?
    let llmProvider: LLMProviderOption?
}

struct ProjectInfo {
    var isSPM: Bool = false
    var hasXcodeProject: Bool = false
    var hasXcodeWorkspace: Bool = false
    var hasCocoaPods: Bool = false
    var hasCarthage: Bool = false
}

// MARK: - Init Wizard Enums

enum InitMode: CaseIterable, CustomStringConvertible {
    case interactive
    case defaults

    var description: String {
        switch self {
        case .interactive:
            "Configure interactively"
        case .defaults:
            "Use defaults (MLX + MLX LLM enhancement)"
        }
    }
}

enum EmbeddingProviderOption: CaseIterable, CustomStringConvertible, Equatable {
    case mlx
    case swift
    case ollama
    case voyage
    case openai
    case gemini

    var description: String {
        switch self {
        case .mlx:
            "MLX (Apple Silicon, fastest)"
        case .swift:
            "Swift Embeddings (CPU, no Metal required)"
        case .ollama:
            "Ollama (local server)"
        case .voyage:
            "Voyage (cloud API)"
        case .openai:
            "OpenAI (cloud API)"
        case .gemini:
            "Gemini (Google AI API)"
        }
    }

    var configValue: String {
        switch self {
        case .mlx:
            "mlx"
        case .swift:
            "swift"
        case .ollama:
            "ollama"
        case .voyage:
            "voyage"
        case .openai:
            "openai"
        case .gemini:
            "gemini"
        }
    }

    static func fromFlag(_ value: String?) -> EmbeddingProviderOption? {
        guard let value = value?.lowercased() else {
            return nil
        }
        switch value {
        case "mlx":
            return .mlx
        case "swift", "swift-embeddings", "swiftembeddings":
            return .swift
        case "ollama":
            return .ollama
        case "voyage":
            return .voyage
        case "openai":
            return .openai
        case "gemini":
            return .gemini
        default:
            return nil
        }
    }
}

enum LLMProviderOption: CaseIterable, CustomStringConvertible, Equatable {
    case mlx
    case claudeCodeOAuth
    case claudeCodeCLI
    case codexCLI
    case ollama
    case openai
    case gemini
    case geminiCLI

    var description: String {
        switch self {
        case .mlx:
            "MLX (Apple Silicon, fully local)"
        case .claudeCodeOAuth:
            "Claude Code OAuth (Pro/Max, automatic)"
        case .claudeCodeCLI:
            "Claude Code (claude CLI)"
        case .codexCLI:
            "Codex CLI (codex)"
        case .ollama:
            "Ollama (local server)"
        case .openai:
            "OpenAI (cloud API)"
        case .gemini:
            "Gemini API (Google AI)"
        case .geminiCLI:
            "Gemini CLI (gemini command)"
        }
    }

    var configValue: String {
        switch self {
        case .mlx:
            "mlx"
        case .claudeCodeOAuth:
            "anthropic" // OAuth tokens use AnthropicLLMProvider
        case .claudeCodeCLI:
            "claude-code-cli"
        case .codexCLI:
            "codex-cli"
        case .ollama:
            "ollama"
        case .openai:
            "openai"
        case .gemini:
            "gemini"
        case .geminiCLI:
            "gemini-cli"
        }
    }
}

enum MLXModelOption: CaseIterable, CustomStringConvertible, Equatable {
    case qwenSmall
    case qwenMedium
    case qwenLarge
    case custom

    var modelName: String? {
        switch self {
        case .qwenSmall:
            "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"
        case .qwenMedium:
            "mlx-community/Qwen3-Embedding-4B-4bit-DWQ"
        case .qwenLarge:
            "mlx-community/Qwen3-Embedding-8B-4bit-DWQ"
        case .custom:
            nil
        }
    }

    var description: String {
        switch self {
        case .qwenSmall:
            "Qwen3 0.6B (4-bit)"
        case .qwenMedium:
            "Qwen3 4B (4-bit)"
        case .qwenLarge:
            "Qwen3 8B (4-bit)"
        case .custom:
            "Custom..."
        }
    }
}

enum SwiftModelOption: CaseIterable, CustomStringConvertible, Equatable {
    case miniLM
    case bgeSmall
    case custom

    var modelName: String? {
        switch self {
        case .miniLM:
            "all-MiniLM-L6-v2"
        case .bgeSmall:
            "bge-small-en-v1.5"
        case .custom:
            nil
        }
    }

    var description: String {
        switch self {
        case .miniLM:
            "all-MiniLM-L6-v2"
        case .bgeSmall:
            "bge-small-en-v1.5"
        case .custom:
            "Custom..."
        }
    }
}

enum OllamaModelOption: CaseIterable, CustomStringConvertible, Equatable {
    case nomic
    case bgeSmall
    case custom

    var modelName: String? {
        switch self {
        case .nomic:
            "nomic-embed-text"
        case .bgeSmall:
            "bge-small"
        case .custom:
            nil
        }
    }

    var description: String {
        switch self {
        case .nomic:
            "nomic-embed-text"
        case .bgeSmall:
            "bge-small"
        case .custom:
            "Custom..."
        }
    }
}

enum VoyageModelOption: CaseIterable, CustomStringConvertible, Equatable {
    case large
    case standard
    case custom

    var modelName: String? {
        switch self {
        case .large:
            "voyage-large-2"
        case .standard:
            "voyage-2"
        case .custom:
            nil
        }
    }

    var description: String {
        switch self {
        case .large:
            "voyage-large-2"
        case .standard:
            "voyage-2"
        case .custom:
            "Custom..."
        }
    }
}

enum OpenAIModelOption: CaseIterable, CustomStringConvertible, Equatable {
    case small
    case large
    case custom

    var modelName: String? {
        switch self {
        case .small:
            "text-embedding-3-small"
        case .large:
            "text-embedding-3-large"
        case .custom:
            nil
        }
    }

    var description: String {
        switch self {
        case .small:
            "text-embedding-3-small"
        case .large:
            "text-embedding-3-large"
        case .custom:
            "Custom..."
        }
    }
}

enum GeminiModelOption: CaseIterable, CustomStringConvertible, Equatable {
    case embedding004
    case custom

    var modelName: String? {
        switch self {
        case .embedding004:
            "text-embedding-004"
        case .custom:
            nil
        }
    }

    var description: String {
        switch self {
        case .embedding004:
            "text-embedding-004"
        case .custom:
            "Custom..."
        }
    }
}

// MARK: - Helper Functions

func orderedOptions<T: Equatable>(_ options: [T], preselected: T?) -> [T] {
    guard let preselected else {
        return options
    }
    var ordered = options.filter { $0 != preselected }
    ordered.insert(preselected, at: 0)
    return ordered
}

func defaultModel(for provider: String) -> String? {
    switch provider.lowercased() {
    case "mlx":
        "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"
    case "swift", "swift-embeddings", "swiftembeddings":
        "all-MiniLM-L6-v2"
    default:
        nil
    }
}

func isMetalToolchainAvailable() -> Bool {
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

func isInteractiveTerminal() -> Bool {
    if let override = ProcessInfo.processInfo.environment["SWIFTINDEX_TTY_OVERRIDE"]?.lowercased() {
        switch override {
        case "interactive":
            return true
        case "noninteractive":
            return false
        default:
            break
        }
    }

    return isatty(STDIN_FILENO) == 1
}
