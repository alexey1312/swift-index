// MARK: - SearchCodeTool

import Foundation
import SwiftIndexCore

/// MCP tool for searching indexed Swift codebases.
///
/// Performs hybrid semantic search combining BM25 keyword matching
/// with vector similarity search using RRF fusion.
public struct SearchCodeTool: MCPToolHandler, Sendable {
    public let definition: MCPTool

    public init() {
        definition = MCPTool(
            name: "search_code",
            description: """
            Search indexed Swift codebases using hybrid semantic search.
            Combines BM25 keyword matching with vector similarity search
            using RRF (Reciprocal Rank Fusion) for optimal results.
            """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object([
                        "type": "string",
                        "description": "Natural language search query or code pattern",
                    ]),
                    "path": .object([
                        "type": "string",
                        "description": "Path to the indexed codebase (default: current directory)",
                        "default": ".",
                    ]),
                    "limit": .object([
                        "type": "integer",
                        "description": "Maximum number of results to return",
                        "default": 20,
                    ]),
                    "semantic_weight": .object([
                        "type": "number",
                        "description": "Weight for semantic search (0.0 = BM25 only, 1.0 = semantic only)",
                        "default": 0.7,
                    ]),
                    "extensions": .object([
                        "type": "string",
                        "description": "Filter by file extensions (comma-separated, e.g., 'swift,ts')",
                    ]),
                    "path_filter": .object([
                        "type": "string",
                        "description": "Filter by path pattern (glob syntax)",
                    ]),
                ]),
                "required": .array([.string("query")]),
            ])
        )
    }

    public func execute(arguments: JSONValue) async throws -> ToolCallResult {
        // Extract arguments
        guard let query = arguments["query"]?.stringValue else {
            return .error("Missing required argument: query")
        }

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error("Query cannot be empty")
        }

        let path = arguments["path"]?.stringValue ?? "."
        let limit = arguments["limit"]?.intValue ?? 20
        let semanticWeight = arguments["semantic_weight"]?.doubleValue.map { Float($0) } ?? 0.7
        let extensionsArg = arguments["extensions"]?.stringValue
        let pathFilter = arguments["path_filter"]?.stringValue

        // Validate arguments
        guard limit > 0 else {
            return .error("Limit must be greater than 0")
        }

        guard semanticWeight >= 0, semanticWeight <= 1 else {
            return .error("Semantic weight must be between 0.0 and 1.0")
        }

        // Perform search
        do {
            // Get context and configuration
            let context = MCPContext.shared
            let config = try await context.getConfig(for: path)

            // Check if index exists
            guard await context.indexExists(for: path, config: config) else {
                return .error(
                    """
                    No index found for path: \(path)
                    Run 'index_codebase' tool first to create the index.
                    """
                )
            }

            // Create search engine
            let searchEngine = try await context.createSearchEngine(for: path, config: config)

            // Build search options
            var extensionFilter: Set<String>?
            if let extensions = extensionsArg {
                extensionFilter = Set(extensions.split(separator: ",").map { String($0).lowercased() })
            }

            let searchOptions = SearchOptions(
                limit: limit,
                semanticWeight: semanticWeight,
                pathFilter: pathFilter,
                extensionFilter: extensionFilter,
                rrfK: config.rrfK
            )

            // Execute search
            let results = try await searchEngine.search(query: query, options: searchOptions)

            // Format results
            return .text(formatResults(results: results, query: query))
        } catch {
            return .error("Search failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func formatResults(results: [SearchResult], query: String) -> String {
        var jsonResults: [[String: Any]] = []

        for result in results {
            var item: [String: Any] = [
                "id": result.chunk.id,
                "path": result.chunk.path,
                "start_line": result.chunk.startLine,
                "end_line": result.chunk.endLine,
                "kind": result.chunk.kind.rawValue,
                "symbols": result.chunk.symbols,
                "score": Double(result.score),
                "content": result.chunk.content,
            ]

            if let bm25Score = result.bm25Score {
                item["bm25_score"] = Double(bm25Score)
            }
            if let semanticScore = result.semanticScore {
                item["semantic_score"] = Double(semanticScore)
            }

            jsonResults.append(item)
        }

        let output: [String: Any] = [
            "query": query,
            "result_count": results.count,
            "results": jsonResults,
        ]

        return formatJSON(output)
    }

    private func formatJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        ),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}
