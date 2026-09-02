// MARK: - GraphCommand

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore

/// Explores the symbol graph from the terminal.
///
/// Shipped ahead of the MCP tool so the traversal and its output can be exercised
/// directly rather than only through an agent.
struct GraphCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "graph",
        abstract: "Explore callers, callees and impact in the symbol graph",
        discussion: """
        Examples:
          swiftindex graph IndexManager.save --callers
          swiftindex graph SearchEngine.run --callees --depth 3
          swiftindex graph ChunkStore.search --impact
          swiftindex graph SearchEngine.run --to ChunkStore.search
          swiftindex graph --status
        """
    )

    @Argument(help: "Symbol name or qualified name.")
    var symbol: String?

    @Flag(name: .long, help: "Show what calls this symbol.")
    var callers = false

    @Flag(name: .long, help: "Show what this symbol calls.")
    var callees = false

    @Flag(name: .long, help: "Show the blast radius of changing this symbol.")
    var impact = false

    @Option(name: .long, help: "Find call paths to this symbol.")
    var to: String?

    @Option(name: .long, help: "Traversal depth (1-5).")
    var depth = 2

    @Option(name: .long, help: "Minimum edge confidence (0-1).")
    var minConfidence: Double?

    @Option(name: .long, help: "Maximum symbols to return.")
    var limit = 40

    @Option(name: .long, help: "Output format: toon or human.")
    var format = "human"

    @Flag(name: .long, help: "Show graph statistics instead of running a query.")
    var status = false

    @Option(name: .long, help: "Project path.")
    var path = "."

    @Flag(name: .long, help: "Enable verbose logging.")
    var verbose = false

    func run() async throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        let resolvedPath = FileCollector.canonicalPath(CLIUtils.resolvePath(path))
        let configuration = try CLIUtils.loadConfig(
            from: nil,
            projectDirectory: resolvedPath,
            logger: logger
        )

        let indexPath = (resolvedPath as NSString).appendingPathComponent(configuration.indexPath)
        guard FileManager.default.fileExists(
            atPath: (indexPath as NSString).appendingPathComponent("chunks.db")
        ) else {
            throw ValidationError("No index found at \(indexPath). Run 'swiftindex index' first.")
        }

        let store = try GRDBChunkStore(
            path: (indexPath as NSString).appendingPathComponent("chunks.db")
        )

        if status {
            try await printStatus(store: store)
            return
        }

        guard let symbolQuery = symbol else {
            throw ValidationError("Provide a symbol, or use --status.")
        }

        let engine = GraphQueryEngine(
            chunkStore: store,
            config: configuration.graph,
            logger: logger
        )

        let matches = try await engine.resolveSymbols(query: symbolQuery, limit: 5)
        guard let root = matches.first else {
            throw ValidationError("No symbol matching '\(symbolQuery)' in the graph.")
        }
        if matches.count > 1 {
            print("Multiple matches; using \(root.qualifiedName) (\(root.path):\(root.startLine))")
            print("")
        }

        var target: SymbolNode?
        if let to {
            target = try await engine.resolveSymbols(query: to, limit: 1).first
            guard target != nil else {
                throw ValidationError("No symbol matching '\(to)' in the graph.")
            }
        }

        let result = try await engine.query(
            symbol: root,
            relation: selectedRelation,
            depth: min(max(depth, 1), 5),
            minConfidence: minConfidence,
            target: target,
            limit: limit
        )

        switch format.lowercased() {
        case "toon":
            print(GraphTOONFormatter.format(result))
        case "human":
            print(GraphTOONFormatter.formatHuman(result))
        default:
            throw ValidationError("Unknown format '\(format)'. Valid: toon, human.")
        }
    }

    private var selectedRelation: GraphRelation {
        if to != nil {
            return .paths
        }
        if callers {
            return .callers
        }
        if callees {
            return .callees
        }
        if impact {
            return .impact
        }
        return .neighborhood
    }

    private func printStatus(store: GRDBChunkStore) async throws {
        let stats = try await store.graphStatistics()
        let dirty = try await store.graphMetaValue("dirty")

        print("Symbol graph")
        print("  symbols:  \(stats.symbols)")
        print("  edges:    \(stats.edges)")
        let percentage = stats.edges > 0 ? stats.resolved * 100 / stats.edges : 0
        print("  resolved: \(stats.resolved) (\(percentage)%)")
        if dirty == "1" {
            print("  state:    incomplete — a resolution pass did not finish")
        }
    }
}
