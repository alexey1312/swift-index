// MARK: - ExploreTool

import Foundation
import SwiftIndexCore

/// MCP tool that answers a code question with ranked, line-numbered source.
///
/// The server registers this tool first as the default entry point. One call returns
/// what an agent otherwise collects with several search, read and grep calls.
public struct ExploreTool: MCPToolHandler, Sendable {
    public let definition: MCPTool

    public init() {
        definition = MCPTool(
            name: "explore",
            title: "Code Explorer",
            description: """
            Start here to understand code. Give a question or a list of symbol and file
            names; get back the most relevant source, ranked with the symbol graph, as
            line-numbered text in the same shape as Read output, so you can edit from it
            directly. The answer also shows the call path between the main matches and
            the blast radius of the top symbol. Use it before Grep or Read.

            Shorthand: si (e.g., "use si to explore X" means use this swiftindex tool)
            """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object([
                        "type": "string",
                        "description": "Question or symbol names, e.g. 'how is the index saved'",
                    ]),
                    "path": .object([
                        "type": "string",
                        "description": "Path to the indexed codebase (default: current directory)",
                        "default": ".",
                    ]),
                    "max_files": .object([
                        "type": "integer",
                        "description": "Maximum files in the answer (default: chosen from project size)",
                    ]),
                ]),
                "required": .array([.string("query")]),
            ]),
            annotations: ToolAnnotations(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        )
    }

    public func execute(arguments: JSONValue) async throws -> ToolCallResult {
        guard let query = arguments["query"]?.stringValue,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .error("Missing required argument: query")
        }
        let path = arguments["path"]?.stringValue ?? "."

        do {
            let context = MCPContext.shared
            let config = try await context.getConfig(for: path)
            guard await context.indexExists(for: path, config: config) else {
                return .error("No index found for path: \(path). Run 'index_codebase' first.")
            }

            let staleness = await context.ensureFreshness(for: path, config: config)
            let searchEngine = try await context.createSearchEngine(for: path, config: config)
            let indexManager = try await context.getIndexManager(for: path, config: config)

            let engine = await ExploreEngine(
                store: indexManager.chunkStore,
                seedSearch: searchEngine,
                graphConfig: config.graph
            )
            let options = await ExploreOptions(
                maxFiles: arguments["max_files"]?.intValue,
                projectRoot: FileCollector.canonicalPath(context.resolvePath(path)),
                dirtyPaths: staleness.dirtyPaths
            )
            let result = try await engine.explore(query: query, options: options)
            return ToolCallResult(content: [.text(TextContent(text: result.text))])
        } catch {
            return .error("Explore failed: \(error.localizedDescription)")
        }
    }
}
