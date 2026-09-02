// MARK: - AgentTarget

import Foundation

/// How an agent stores its MCP server configuration.
enum MCPConfigFormat: Sendable {
    /// A JSON file with an `mcpServers` object.
    case mcpServersJSON
    /// Codex's `config.toml`, which uses `[mcp_servers.<name>]` sections.
    case codexTOML
}

/// Where the configuration is written.
enum InstallScope: Sendable {
    case project
    case global
}

/// An agent SwiftIndex can register itself with.
///
/// The four original install commands were roughly 80% identical; describing each
/// agent as data rather than a command means adding another is a single literal
/// instead of another near-copy that can drift. (`InstallGeminiCommand`, for
/// instance, had lost its already-installed guard and silently overwrote.)
struct AgentTarget: Sendable {
    let id: String
    let displayName: String
    let format: MCPConfigFormat

    /// Project-scoped config path for a working directory, or nil if unsupported.
    let projectConfigPath: @Sendable (String) -> String?

    /// Global config path.
    let globalConfigPath: @Sendable () -> String

    /// Whether Codex-style `cwd` should be recorded for project scope.
    let includesCwd: Bool

    /// Filesystem markers indicating the agent is installed.
    let detectionPaths: @Sendable () -> [String]

    /// Executable name to look for on PATH, if any.
    let detectionExecutable: String?

    func configPath(scope: InstallScope, workingDirectory: String) -> String? {
        switch scope {
        case .project: projectConfigPath(workingDirectory)
        case .global: globalConfigPath()
        }
    }

    /// Whether this agent appears to be installed on the machine.
    func isDetected() -> Bool {
        let fileManager = FileManager.default
        if detectionPaths().contains(where: { fileManager.fileExists(atPath: $0) }) {
            return true
        }
        guard let executable = detectionExecutable else { return false }
        return CLIUtils.isExecutableOnPath(executable)
    }
}

// MARK: - Registry

/// Every agent SwiftIndex knows how to configure.
enum AgentRegistry {
    static var all: [AgentTarget] {
        [claudeCode, cursor, codex, gemini, claudeDesktop, vsCode, windsurf]
    }

    static func target(id: String) -> AgentTarget? {
        all.first { $0.id == id }
    }

    private static var home: String {
        NSHomeDirectory()
    }

    static let claudeCode = AgentTarget(
        id: "claude-code",
        displayName: "Claude Code",
        format: .mcpServersJSON,
        projectConfigPath: { "\($0)/.mcp.json" },
        globalConfigPath: { "\(NSHomeDirectory())/.claude.json" },
        includesCwd: false,
        detectionPaths: { ["\(NSHomeDirectory())/.claude.json", "\(NSHomeDirectory())/.claude"] },
        detectionExecutable: "claude"
    )

    static let cursor = AgentTarget(
        id: "cursor",
        displayName: "Cursor",
        format: .mcpServersJSON,
        projectConfigPath: { "\($0)/.cursor/mcp.json" },
        globalConfigPath: { "\(NSHomeDirectory())/.cursor/mcp.json" },
        includesCwd: false,
        detectionPaths: { ["\(NSHomeDirectory())/.cursor", "/Applications/Cursor.app"] },
        detectionExecutable: nil
    )

    static let codex = AgentTarget(
        id: "codex",
        displayName: "Codex CLI",
        format: .codexTOML,
        projectConfigPath: { _ in nil },
        globalConfigPath: { "\(NSHomeDirectory())/.codex/config.toml" },
        includesCwd: true,
        detectionPaths: { ["\(NSHomeDirectory())/.codex"] },
        detectionExecutable: "codex"
    )

    static let gemini = AgentTarget(
        id: "gemini",
        displayName: "Gemini CLI",
        format: .mcpServersJSON,
        projectConfigPath: { "\($0)/.gemini.json" },
        globalConfigPath: { "\(NSHomeDirectory())/.gemini.json" },
        includesCwd: false,
        detectionPaths: { ["\(NSHomeDirectory())/.gemini", "\(NSHomeDirectory())/.gemini.json"] },
        detectionExecutable: "gemini"
    )

    static let claudeDesktop = AgentTarget(
        id: "claude-desktop",
        displayName: "Claude Desktop",
        format: .mcpServersJSON,
        projectConfigPath: { _ in nil },
        globalConfigPath: {
            "\(NSHomeDirectory())/Library/Application Support/Claude/claude_desktop_config.json"
        },
        includesCwd: false,
        detectionPaths: { ["\(NSHomeDirectory())/Library/Application Support/Claude"] },
        detectionExecutable: nil
    )

    static let vsCode = AgentTarget(
        id: "vscode",
        displayName: "VS Code",
        format: .mcpServersJSON,
        projectConfigPath: { "\($0)/.vscode/mcp.json" },
        globalConfigPath: { "\(NSHomeDirectory())/.vscode/mcp.json" },
        includesCwd: false,
        detectionPaths: { ["\(NSHomeDirectory())/Library/Application Support/Code"] },
        detectionExecutable: nil
    )

    static let windsurf = AgentTarget(
        id: "windsurf",
        displayName: "Windsurf",
        format: .mcpServersJSON,
        projectConfigPath: { _ in nil },
        globalConfigPath: { "\(NSHomeDirectory())/.codeium/windsurf/mcp_config.json" },
        includesCwd: false,
        detectionPaths: { ["\(NSHomeDirectory())/.codeium/windsurf"] },
        detectionExecutable: nil
    )
}
