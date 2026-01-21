// MARK: - Install Command

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

/// Target platforms for installation.
enum InstallTarget: String, ExpressibleByArgument, CaseIterable {
    case claudeCode = "claude-code"
    case cursor
    case codex

    var description: String {
        switch self {
        case .claudeCode:
            return "Claude Code (Anthropic)"
        case .cursor:
            return "Cursor IDE"
        case .codex:
            return "OpenAI Codex"
        }
    }

    var configPath: String {
        switch self {
        case .claudeCode:
            return "~/.config/claude-code/mcp.json"
        case .cursor:
            return "~/.config/cursor/mcp.json"
        case .codex:
            return "~/.config/codex/mcp.json"
        }
    }
}

/// Command to install SwiftIndex as an MCP server for AI assistants.
///
/// Usage:
///   swiftindex install-claude-code
///   swiftindex install-claude-code claude-code
///   swiftindex install-claude-code cursor
struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-claude-code",
        abstract: "Install SwiftIndex as MCP server for AI assistants",
        discussion: """
            Configures SwiftIndex as a Model Context Protocol (MCP) server
            for the specified AI assistant platform.

            Supported targets:
            - claude-code: Claude Code by Anthropic
            - cursor: Cursor IDE
            - codex: OpenAI Codex

            This command modifies the MCP configuration file to add
            SwiftIndex as an available tool provider.
            """
    )

    // MARK: - Arguments

    @Argument(
        help: "Target platform to install for"
    )
    var target: InstallTarget = .claudeCode

    // MARK: - Options

    @Flag(
        name: .shortAndLong,
        help: "Enable verbose debug output"
    )
    var verbose: Bool = false

    @Flag(
        name: .long,
        help: "Show what would be done without making changes"
    )
    var dryRun: Bool = false

    // MARK: - Execution

    mutating func run() throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        logger.info("Installing SwiftIndex for \(target.description)")

        // Get the executable path
        let executablePath = CommandLine.arguments[0]
        let resolvedExecutable = CLIUtils.resolvePath(executablePath)

        // Resolve config path
        let configPath = (target.configPath as NSString)
            .expandingTildeInPath

        logger.debug("Target config path: \(configPath)")
        logger.debug("Executable path: \(resolvedExecutable)")

        // Create MCP configuration entry
        let mcpConfig: [String: Any] = [
            "swiftindex": [
                "command": resolvedExecutable,
                "args": ["serve"],
                "env": [:] as [String: String],
            ]
        ]

        if dryRun {
            print("Dry run - would perform the following:")
            print("")
            print("Target: \(target.description)")
            print("Config: \(configPath)")
            print("")
            print("Would add MCP server configuration:")
            if let jsonData = try? JSONSerialization.data(
                withJSONObject: mcpConfig,
                options: [.prettyPrinted, .sortedKeys]
            ),
                let jsonString = String(data: jsonData, encoding: .utf8)
            {
                print(jsonString)
            }
            return
        }

        // Check if config directory exists
        let configDir = (configPath as NSString).deletingLastPathComponent
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: configDir) {
            logger.info("Creating config directory: \(configDir)")
            try fileManager.createDirectory(
                atPath: configDir,
                withIntermediateDirectories: true
            )
        }

        // Read existing config or create new one
        var existingConfig: [String: Any] = [:]

        if fileManager.fileExists(atPath: configPath) {
            logger.debug("Reading existing config")
            if let data = fileManager.contents(atPath: configPath),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                existingConfig = json
            }
        }

        // Get or create mcpServers section
        var mcpServers = existingConfig["mcpServers"] as? [String: Any] ?? [:]

        // Check if already installed
        if mcpServers["swiftindex"] != nil {
            logger.warning("SwiftIndex is already installed for \(target.description)")
            print("SwiftIndex is already configured for \(target.description)")
            print("Config: \(configPath)")
            return
        }

        // Add swiftindex configuration
        mcpServers["swiftindex"] = mcpConfig["swiftindex"]
        existingConfig["mcpServers"] = mcpServers

        // Write updated config
        logger.info("Writing updated config")
        let jsonData = try JSONSerialization.data(
            withJSONObject: existingConfig,
            options: [.prettyPrinted, .sortedKeys]
        )

        try jsonData.write(to: URL(fileURLWithPath: configPath))

        print("Successfully installed SwiftIndex for \(target.description)")
        print("")
        print("Configuration written to: \(configPath)")
        print("")
        print("Restart \(target.description) to enable SwiftIndex tools.")

        logger.info("Installation completed")
    }
}
