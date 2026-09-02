// MARK: - CodeGraphTool

import Foundation
import SwiftIndexCore

/// MCP tool for structural questions about the codebase.
///
/// Deliberately one tool with a `relation` enum rather than several near-synonyms.
/// Tool schemas are re-sent every turn, so five separate graph tools would roughly
/// double this server's permanent context cost for a capability used in a minority of
/// turns — and a single enum is easier for a model to choose correctly than five
/// overlapping names.
public struct CodeGraphTool: MCPToolHandler, Sendable {
    public let definition: MCPTool

    public init() {
        definition = MCPTool(
            name: "code_graph",
            title: "Code Graph",
            description: """
            Answer structural questions using the pre-built symbol graph: who calls a
            symbol, what it calls, the blast radius of changing it, and how one symbol
            reaches another. Follows dynamic-dispatch hops (protocol requirements to
            their conforming implementations) that text search cannot.

            Each edge reports how it was derived: 'syn' means resolved from syntax,
            'heu' means inferred by a rule such as protocol-witness fanout. Treat 'heu'
            edges as strong hints rather than facts.

            Shorthand: si (e.g., "use si to find callers" means use this swiftindex tool)
            """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "symbol": .object([
                        "type": "string",
                        "description": "Symbol name or qualified name, e.g. 'IndexManager.save'",
                    ]),
                    "relation": .object([
                        "type": "string",
                        "description": """
                        callers: what calls this. callees: what this calls.
                        impact: everything that could break if it changes.
                        paths: how 'symbol' reaches 'target'.
                        neighborhood: both directions at once.
                        """,
                        "enum": .array([
                            .string("callers"), .string("callees"), .string("impact"),
                            .string("paths"), .string("neighborhood"),
                        ]),
                        "default": "neighborhood",
                    ]),
                    "target": .object([
                        "type": "string",
                        "description": "Destination symbol, required when relation is 'paths'",
                    ]),
                    "depth": .object([
                        "type": "integer",
                        "description": "Traversal depth (1-5)",
                        "default": 2,
                    ]),
                    "path": .object([
                        "type": "string",
                        "description": "Path to the indexed codebase (default: current directory)",
                        "default": ".",
                    ]),
                    "min_confidence": .object([
                        "type": "number",
                        "description": "Minimum edge confidence, 0-1 (default: 0.3)",
                    ]),
                    "limit": .object([
                        "type": "integer",
                        "description": "Maximum symbols to return",
                        "default": 40,
                    ]),
                    "format": .object([
                        "type": "string",
                        "description": "Output format: toon (compact) or human",
                        "enum": .array([.string("toon"), .string("human")]),
                    ]),
                ]),
                "required": .array([.string("symbol")]),
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
        guard let symbolQuery = arguments["symbol"]?.stringValue,
              !symbolQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .error("Missing required argument: symbol")
        }

        let path = arguments["path"]?.stringValue ?? "."
        let relationName = arguments["relation"]?.stringValue ?? "neighborhood"
        guard let relation = GraphRelation(rawValue: relationName) else {
            let valid = GraphRelation.allCases.map(\.rawValue).joined(separator: ", ")
            return .error("Unknown relation '\(relationName)'. Valid: \(valid)")
        }

        let depth = min(max(arguments["depth"]?.intValue ?? 2, 1), 5)
        let limit = arguments["limit"]?.intValue ?? 40
        let minConfidence = arguments["min_confidence"]?.doubleValue
        let format = arguments["format"]?.stringValue ?? "toon"

        do {
            let context = MCPContext.shared
            let config = try await context.getConfig(for: path)

            guard config.graph.enabled else {
                return .error("The symbol graph is disabled ([graph] enabled = false).")
            }

            guard await context.indexExists(for: path, config: config) else {
                return .error(
                    """
                    No index found for path: \(path)
                    Run 'index_codebase' tool first to create the index.
                    """
                )
            }

            let indexManager = try await context.getIndexManager(for: path, config: config)
            let engine = await GraphQueryEngine(
                chunkStore: indexManager.chunkStore,
                config: config.graph
            )

            let matches = try await engine.resolveSymbols(query: symbolQuery, limit: 5)
            guard let root = matches.first else {
                return .error(
                    """
                    No symbol matching '\(symbolQuery)' in the graph.
                    The graph indexes Swift declarations; try search_code for text matches.
                    """
                )
            }

            var target: SymbolNode?
            if relation == .paths {
                guard let targetQuery = arguments["target"]?.stringValue else {
                    return .error("relation 'paths' requires a 'target' symbol")
                }
                target = try await engine.resolveSymbols(query: targetQuery, limit: 1).first
                guard target != nil else {
                    return .error("No symbol matching '\(targetQuery)' in the graph.")
                }
            }

            let result = try await engine.query(
                symbol: root,
                relation: relation,
                depth: depth,
                minConfidence: minConfidence,
                target: target,
                limit: limit
            )

            let text = format == "human"
                ? GraphTOONFormatter.formatHuman(result)
                : GraphTOONFormatter.format(result)

            return ToolCallResult(content: [.text(TextContent(text: text))])
        } catch {
            return .error("Graph query failed: \(error.localizedDescription)")
        }
    }
}
