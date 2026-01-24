// MARK: - Serve Command

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore
import SwiftIndexMCP

/// Command to start the MCP server for AI assistant integration.
///
/// Usage:
///   swiftindex serve
///   swiftindex serve --config path/to/config.toml
struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start MCP server for AI assistant integration",
        discussion: """
        Starts a Model Context Protocol (MCP) server that communicates
        via stdin/stdout. This allows AI assistants like Claude to use
        SwiftIndex tools for semantic code search.

        Available MCP tools:
        - index_codebase: Index a Swift project
        - search_code: Hybrid semantic search
        - code_research: Multi-hop architectural analysis
        - watch_codebase: Watch for file changes
        """
    )

    // MARK: - Options

    @Option(
        name: .shortAndLong,
        help: "Path to configuration file"
    )
    var config: String?

    @Flag(
        name: .shortAndLong,
        help: "Enable verbose debug output"
    )
    var verbose: Bool = false

    // MARK: - Execution

    mutating func run() async throws {
        // Capture verbose flag before escaping closure
        let verboseFlag = verbose

        // Configure logging to stderr (stdout is reserved for JSON-RPC)
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = verboseFlag ? .debug : .info
            return handler
        }

        let logger = CLIUtils.makeLogger(verbose: verbose)
        logger.info("Starting SwiftIndex MCP server")

        // Load configuration
        _ = try CLIUtils.loadConfig(from: config, logger: logger)
        logger.debug("Configuration loaded for MCP server")

        // Output startup info to stderr
        FileHandle.standardError.write(
            Data("SwiftIndex MCP Server v\(MCPServer.serverInfo.version)\n".utf8)
        )
        FileHandle.standardError.write(
            Data("Protocol: \(MCPServer.supportedProtocolVersions.first ?? "unknown")\n".utf8)
        )
        FileHandle.standardError.write(
            Data("Listening on stdin/stdout\n".utf8)
        )

        // Create and run MCP server
        let server = MCPServer(logger: logger)

        // Log available tools
        logger.info("Available tools: index_codebase, search_code, code_research, watch_codebase")

        // Run the server (blocks until stdin closes or error)
        await server.run()

        logger.info("MCP server stopped")
    }
}
