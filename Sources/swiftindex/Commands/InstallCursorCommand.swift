// MARK: - Install Cursor Command

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

/// Command to install SwiftIndex as an MCP server for Cursor IDE.
///
/// Usage:
///   swiftindex install-cursor           # Project-local (.mcp.json)
///   swiftindex install-cursor --global  # Global (~/.cursor/mcp.json)
///   swiftindex install-cursor --dry-run
///   swiftindex install-cursor --force
struct InstallCursorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-cursor",
        abstract: "Install SwiftIndex as MCP server for Cursor IDE",
        discussion: """
        Configures SwiftIndex as a Model Context Protocol (MCP) server
        for Cursor IDE.

        By default, creates a project-local .mcp.json in the current directory.
        Use --global to add to ~/.cursor/mcp.json for global availability.

        Configuration format:
        {
          "mcpServers": {
            "swiftindex": {
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
        help: "Install globally to ~/.cursor/mcp.json instead of project-local .mcp.json"
    )
    var global: Bool = false

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
        logger.info("Installing SwiftIndex for Cursor IDE")

        // Get the executable path
        let executablePath = CommandLine.arguments[0]
        let resolvedExecutable = CLIUtils.resolvePath(executablePath)

        // Config path depends on --global flag
        let configPath: String
        let scopeDescription: String

        if global {
            configPath = ("~/.cursor/mcp.json" as NSString).expandingTildeInPath
            scopeDescription = "global"
        } else {
            configPath = FileManager.default.currentDirectoryPath + "/.mcp.json"
            scopeDescription = "project-local"
        }

        logger.debug("Target config path: \(configPath)")
        logger.debug("Executable path: \(resolvedExecutable)")
        logger.debug("Scope: \(scopeDescription)")

        // Create MCP configuration entry (Cursor does not require "type" field)
        let mcpServerConfig: [String: Any] = [
            "command": resolvedExecutable,
            "args": ["serve"],
        ]

        if dryRun {
            print("Dry run - would perform the following:")
            print("")
            print("Target: Cursor IDE (\(scopeDescription))")
            print("Config: \(configPath)")
            print("")
            print("Would add MCP server configuration:")
            let fullConfig: [String: Any] = ["mcpServers": ["swiftindex": mcpServerConfig]]
            if let jsonData = try? JSONCodec.serialize(fullConfig, options: [.prettyPrinted, .sortedKeys]),
               let jsonString = String(data: jsonData, encoding: .utf8)
            {
                print(jsonString)
            }
            return
        }

        // Check if config directory exists (for global)
        if global {
            let configDir = (configPath as NSString).deletingLastPathComponent
            let fileManager = FileManager.default

            if !fileManager.fileExists(atPath: configDir) {
                logger.info("Creating config directory: \(configDir)")
                try fileManager.createDirectory(
                    atPath: configDir,
                    withIntermediateDirectories: true
                )
            }
        }

        let fileManager = FileManager.default

        // Read existing config or create new one
        var existingConfig: [String: Any] = [:]

        if fileManager.fileExists(atPath: configPath) {
            logger.debug("Reading existing config")
            if let data = fileManager.contents(atPath: configPath),
               let json = try? JSONCodec.deserialize(data) as? [String: Any]
            {
                existingConfig = json
            }
        }

        // Get or create mcpServers section
        var mcpServers = existingConfig["mcpServers"] as? [String: Any] ?? [:]

        // Check if already installed
        if mcpServers["swiftindex"] != nil, !force {
            logger.warning("SwiftIndex is already installed for Cursor IDE")
            print("SwiftIndex is already configured for Cursor IDE")
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
        let jsonData = try JSONCodec.serialize(existingConfig, options: [.prettyPrinted, .sortedKeys])

        try jsonData.write(to: URL(fileURLWithPath: configPath))

        print("Successfully installed SwiftIndex for Cursor IDE (\(scopeDescription))")
        print("")
        print("Configuration written to: \(configPath)")
        print("")
        print("Restart Cursor IDE to enable SwiftIndex tools.")

        logger.info("Installation completed")
    }
}
