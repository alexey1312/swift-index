// MARK: - Install Gemini Command

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

/// Command to install SwiftIndex as an MCP server for Gemini CLI.
///
/// Usage:
///   swiftindex install-gemini           # Project-local (.gemini.json)
///   swiftindex install-gemini --global  # Global (~/.gemini.json)
struct InstallGeminiCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-gemini",
        abstract: "Install SwiftIndex as MCP server for Gemini CLI",
        discussion: """
        Configures SwiftIndex as a Model Context Protocol (MCP) server
        for Gemini CLI tools.

        By default, creates a project-local .gemini.json in the current directory.
        Use --global to add to ~/.gemini.json for global availability.
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
        help: "Install globally to ~/.gemini.json instead of project-local .gemini.json"
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

    @Option(
        name: .long,
        help: "Path to swiftindex binary (auto-detected if not specified)"
    )
    var binaryPath: String?

    // MARK: - Execution

    mutating func run() throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        logger.info("Installing SwiftIndex for Gemini CLI")

        // Get the executable path
        let pathResult = CLIUtils.resolveExecutablePath(explicitPath: binaryPath)

        if pathResult.isDevelopmentBuild {
            logger.warning("Development build detected: \(pathResult.path)")
            print("Warning: Using development build path. Use --binary-path to override.")
        }

        logger.debug("Binary path: \(pathResult.path) (source: \(pathResult.source.rawValue))")

        // Config path depends on --global flag
        let configPath: String
        let scopeDescription: String

        if global {
            configPath = ("~/.gemini.json" as NSString).expandingTildeInPath
            scopeDescription = "global"
        } else {
            configPath = FileManager.default.currentDirectoryPath + "/.gemini.json"
            scopeDescription = "project-local"
        }

        // Create MCP configuration entry
        let mcpServerConfig: [String: Any] = [
            "type": "stdio",
            "command": pathResult.path,
            "args": ["serve"],
        ]

        if dryRun {
            print("Dry run - would add MCP server configuration to \(configPath)")
            return
        }

        let fileManager = FileManager.default
        var existingConfig: [String: Any] = [:]

        if fileManager.fileExists(atPath: configPath) {
            if let data = fileManager.contents(atPath: configPath),
               let json = try? JSONCodec.deserialize(data) as? [String: Any]
            {
                existingConfig = json
            }
        }

        var mcpServers = existingConfig["mcpServers"] as? [String: Any] ?? [:]
        mcpServers["swiftindex"] = mcpServerConfig
        existingConfig["mcpServers"] = mcpServers

        let jsonData = try JSONCodec.serialize(existingConfig, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: URL(fileURLWithPath: configPath))

        print("Successfully installed SwiftIndex for Gemini CLI (\(scopeDescription))")
        print("Config: \(configPath)")
    }
}
