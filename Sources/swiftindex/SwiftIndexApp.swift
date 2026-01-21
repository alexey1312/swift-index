// MARK: - SwiftIndex CLI

import ArgumentParser
import Foundation
import SwiftIndexCore
import SwiftIndexMCP

@main
struct SwiftIndex: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftindex",
        abstract: "Semantic code search for Swift codebases",
        discussion: """
            SwiftIndex provides AI-powered semantic search for Swift projects.
            It combines BM25 keyword matching with vector similarity search
            using local embedding models.

            Quick start:
              swiftindex index           Index current directory
              swiftindex search "query"  Search the index
              swiftindex watch           Watch for changes

            For AI assistant integration:
              swiftindex install-claude-code  Configure for Claude Code
              swiftindex serve                Start MCP server
            """,
        version: "0.1.0",
        subcommands: [
            IndexCommand.self,
            SearchCommand.self,
            WatchCommand.self,
            ProvidersCommand.self,
            ServeCommand.self,
            InstallCommand.self,
        ],
        defaultSubcommand: IndexCommand.self
    )
}
