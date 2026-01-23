// MARK: - Install Codex Command

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

/// Command to install SwiftIndex as an MCP server for OpenAI Codex.
///
/// Usage:
///   swiftindex install-codex           # Project-local (.mcp.json)
///   swiftindex install-codex --global  # Global (~/.codex/config.toml)
///   swiftindex install-codex --dry-run
///   swiftindex install-codex --force
struct InstallCodexCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-codex",
        abstract: "Install SwiftIndex as MCP server for OpenAI Codex",
        discussion: """
        Configures SwiftIndex as a Model Context Protocol (MCP) server
        for OpenAI Codex.

        By default, creates a project-local .mcp.json in the current directory.
        Use --global to add to ~/.codex/config.toml for global availability.

        Global configuration format (TOML):
        [mcp_servers.swiftindex]
        command = "/path/to/swiftindex"
        args = ["serve"]
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
        help: "Install globally to ~/.codex/config.toml instead of project-local .mcp.json"
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
        logger.info("Installing SwiftIndex for OpenAI Codex")

        // Get the executable path
        let executablePath = CommandLine.arguments[0]
        let resolvedExecutable = CLIUtils.resolvePath(executablePath)

        let fileManager = FileManager.default

        if global {
            try installGlobal(
                executable: resolvedExecutable,
                fileManager: fileManager,
                logger: logger
            )
        } else {
            try installLocal(
                executable: resolvedExecutable,
                fileManager: fileManager,
                logger: logger
            )
        }
    }

    // MARK: - Private Helpers

    private func installLocal(
        executable: String,
        fileManager: FileManager,
        logger: Logger
    ) throws {
        let configPath = fileManager.currentDirectoryPath + "/.mcp.json"
        let scopeDescription = "project-local"

        logger.debug("Target config path: \(configPath)")
        logger.debug("Executable path: \(executable)")
        logger.debug("Scope: \(scopeDescription)")

        // Create MCP configuration entry
        let mcpServerConfig: [String: Any] = [
            "command": executable,
            "args": ["serve"],
        ]

        if dryRun {
            print("Dry run - would perform the following:")
            print("")
            print("Target: OpenAI Codex (\(scopeDescription))")
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
            logger.warning("SwiftIndex is already installed for OpenAI Codex")
            print("SwiftIndex is already configured for OpenAI Codex")
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

        print("Successfully installed SwiftIndex for OpenAI Codex (\(scopeDescription))")
        print("")
        print("Configuration written to: \(configPath)")
        print("")
        print("Restart Codex to enable SwiftIndex tools.")

        logger.info("Installation completed")
    }

    private func installGlobal(
        executable: String,
        fileManager: FileManager,
        logger: Logger
    ) throws {
        // Config path: ~/.codex/config.toml
        let configPath = ("~/.codex/config.toml" as NSString).expandingTildeInPath
        let scopeDescription = "global"

        logger.debug("Target config path: \(configPath)")
        logger.debug("Executable path: \(executable)")
        logger.debug("Scope: \(scopeDescription)")

        // Create TOML configuration section
        let tomlSection = """
        [mcp_servers.swiftindex]
        command = "\(executable)"
        args = ["serve"]
        """

        if dryRun {
            print("Dry run - would perform the following:")
            print("")
            print("Target: OpenAI Codex (\(scopeDescription))")
            print("Config: \(configPath)")
            print("")
            print("Would add MCP server configuration:")
            print(tomlSection)
            return
        }

        // Check if config directory exists
        let configDir = (configPath as NSString).deletingLastPathComponent

        if !fileManager.fileExists(atPath: configDir) {
            logger.info("Creating config directory: \(configDir)")
            try fileManager.createDirectory(
                atPath: configDir,
                withIntermediateDirectories: true
            )
        }

        // Read existing config or create new one
        var existingContent = ""

        if fileManager.fileExists(atPath: configPath) {
            logger.debug("Reading existing config")
            if let data = fileManager.contents(atPath: configPath),
               let content = String(data: data, encoding: .utf8)
            {
                existingContent = content
            }
        }

        // Check if already installed
        if existingContent.contains("[mcp_servers.swiftindex]"), !force {
            logger.warning("SwiftIndex is already installed for OpenAI Codex")
            print("SwiftIndex is already configured for OpenAI Codex")
            print("Config: \(configPath)")
            print("")
            print("Use --force to overwrite existing configuration")
            return
        }

        // If force and already exists, remove old section
        if force, existingContent.contains("[mcp_servers.swiftindex]") {
            existingContent = removeSwiftIndexSection(from: existingContent)
        }

        // Add swiftindex configuration
        var updatedContent = existingContent
        if !updatedContent.isEmpty, !updatedContent.hasSuffix("\n") {
            updatedContent += "\n"
        }
        if !updatedContent.isEmpty {
            updatedContent += "\n"
        }
        updatedContent += tomlSection
        updatedContent += "\n"

        // Write updated config
        logger.info("Writing updated config")
        try updatedContent.write(
            to: URL(fileURLWithPath: configPath),
            atomically: true,
            encoding: .utf8
        )

        print("Successfully installed SwiftIndex for OpenAI Codex (\(scopeDescription))")
        print("")
        print("Configuration written to: \(configPath)")
        print("")
        print("Restart Codex to enable SwiftIndex tools.")

        logger.info("Installation completed")
    }

    /// Removes existing [mcp_servers.swiftindex] section from TOML content.
    private func removeSwiftIndexSection(from content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var inSwiftIndexSection = false

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == "[mcp_servers.swiftindex]" {
                inSwiftIndexSection = true
                continue
            }

            // End of section when we hit another section header
            if inSwiftIndexSection, line.hasPrefix("[") {
                inSwiftIndexSection = false
            }

            if !inSwiftIndexSection {
                result.append(line)
            }
        }

        // Remove trailing empty lines
        while result.last?.isEmpty == true {
            result.removeLast()
        }

        return result.joined(separator: "\n")
    }
}
