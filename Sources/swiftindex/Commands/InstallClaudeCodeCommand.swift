// MARK: - Install Claude Code Command

import ArgumentParser
import Foundation
import Logging

/// Command to install SwiftIndex as an MCP server for Claude Code.
///
/// Usage:
///   swiftindex install-claude-code
///   swiftindex install-claude-code --dry-run
///   swiftindex install-claude-code --force
struct InstallClaudeCodeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-claude-code",
        abstract: "Install SwiftIndex as MCP server for Claude Code",
        discussion: """
        Configures SwiftIndex as a Model Context Protocol (MCP) server
        for Claude Code by Anthropic.

        This command modifies ~/.claude.json to add SwiftIndex
        as an available MCP tool provider.

        Configuration format:
        {
          "mcpServers": {
            "swiftindex": {
              "type": "stdio",
              "command": "/path/to/swiftindex",
              "args": ["serve"]
            }
          }
        }
        """
    )

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

    @Flag(
        name: .long,
        help: "Overwrite existing configuration"
    )
    var force: Bool = false

    // MARK: - Execution

    mutating func run() throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        logger.info("Installing SwiftIndex for Claude Code")

        // Get the executable path
        let executablePath = CommandLine.arguments[0]
        let resolvedExecutable = CLIUtils.resolvePath(executablePath)

        // Config path: ~/.claude.json
        let configPath = ("~/.claude.json" as NSString).expandingTildeInPath

        logger.debug("Target config path: \(configPath)")
        logger.debug("Executable path: \(resolvedExecutable)")

        // Create MCP configuration entry (Claude Code requires "type": "stdio")
        let mcpServerConfig: [String: Any] = [
            "type": "stdio",
            "command": resolvedExecutable,
            "args": ["serve"],
        ]

        if dryRun {
            print("Dry run - would perform the following:")
            print("")
            print("Target: Claude Code")
            print("Config: \(configPath)")
            print("")
            print("Would add MCP server configuration:")
            let fullConfig: [String: Any] = ["mcpServers": ["swiftindex": mcpServerConfig]]
            if let jsonData = try? JSONSerialization.data(
                withJSONObject: fullConfig,
                options: [.prettyPrinted, .sortedKeys]
            ),
                let jsonString = String(data: jsonData, encoding: .utf8)
            {
                print(jsonString)
            }
            return
        }

        let fileManager = FileManager.default

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
        if mcpServers["swiftindex"] != nil, !force {
            logger.warning("SwiftIndex is already installed for Claude Code")
            print("SwiftIndex is already configured for Claude Code")
            print("Config: \(configPath)")
            print("")
            print("Use --force to overwrite existing configuration")
            return
        }

        // Add swiftindex configuration
        mcpServers["swiftindex"] = mcpServerConfig
        existingConfig["mcpServers"] = mcpServers

        // Write updated config
        logger.info("Writing updated config")
        let jsonData = try JSONSerialization.data(
            withJSONObject: existingConfig,
            options: [.prettyPrinted, .sortedKeys]
        )

        try jsonData.write(to: URL(fileURLWithPath: configPath))

        print("Successfully installed SwiftIndex for Claude Code")
        print("")
        print("Configuration written to: \(configPath)")
        print("")
        print("Restart Claude Code to enable SwiftIndex tools.")

        logger.info("Installation completed")
    }
}
