// MARK: - SwiftIndex CLI

import ArgumentParser
import Foundation
import SwiftIndexCore
import SwiftIndexMCP

@main
struct SwiftIndex: AsyncParsableCommand {
    // Custom version flag with -v shorthand (standard CLI convention)
    @Flag(name: [.short, .long], help: "Show version information")
    var version: Bool = false

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
          swiftindex push            Upload index to remote storage
          swiftindex pull            Download index from remote storage
          swiftindex remote config   Configure remote storage
          swiftindex remote status   Show remote sync status

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
            ParseTreeCommand.self,
            WatchCommand.self,
            PushCommand.self,
            PullCommand.self,
            RemoteCommand.self,
            ProvidersCommand.self,
            ServeCommand.self,
            InstallClaudeCodeCommand.self,
            InstallCursorCommand.self,
            InstallCodexCommand.self,
            InstallGeminiCommand.self,
        ]
        // No defaultSubcommand - running without subcommand shows help
    )

    mutating func run() async throws {
        // Start update check in background (non-blocking)
        let updateTask = Task { await checkForUpdate() }

        if version {
            print(Self.configuration.version)
        } else {
            // No subcommand - print help manually (can't use CleanExit with async)
            print(Self.helpMessage())
        }

        // Wait for update check to complete (with implicit timeout from URLSession)
        await updateTask.value
        throw ExitCode.success
    }
}
