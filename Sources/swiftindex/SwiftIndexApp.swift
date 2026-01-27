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
          swiftindex init            Initialize configuration
          swiftindex index           Index current directory
          swiftindex search "query"  Search the index
          swiftindex search-docs "q" Search documentation
          swiftindex watch           Watch for changes

        Authentication (for search enhancement):
          swiftindex auth status     Check authentication status
          swiftindex auth login      Authenticate with Claude Code OAuth

        For AI assistant integration:
          swiftindex install-claude-code  Configure for Claude Code
          swiftindex serve                Start MCP server
        """,
        version: "VERSION_PLACEHOLDER",
        subcommands: [
            InitCommand.self,
            AuthCommand.self,
            ConfigCommand.self,
            FmtCommand.self,
            IndexCommand.self,
            SearchCommand.self,
            SearchDocsCommand.self,
            WatchCommand.self,
            ProvidersCommand.self,
            ServeCommand.self,
            InstallClaudeCodeCommand.self,
            InstallCursorCommand.self,
            InstallCodexCommand.self,
            InstallGeminiCommand.self,
        ],
        defaultSubcommand: IndexCommand.self
    )
}
