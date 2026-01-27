// MARK: - SearchDocsTool

import Foundation
import SwiftIndexCore

/// MCP tool for searching indexed documentation and info snippets.
///
/// Performs BM25 full-text search on standalone documentation content
/// such as Markdown files, README sections, and API documentation.
public struct SearchDocsTool: MCPToolHandler, Sendable {
    public let definition: MCPTool

    public init() {
        definition = MCPTool(
            name: "search_docs",
            title: "Documentation Search",
            description: """
            Search indexed documentation using full-text search.
            Searches Markdown files, README sections, and other documentation
            content for relevant information.
            """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object([
                        "type": "string",
                        "description": "Natural language search query",
                    ]),
                    "path": .object([
                        "type": "string",
                        "description": "Path to the indexed codebase (default: current directory)",
                        "default": ".",
                    ]),
                    "limit": .object([
                        "type": "integer",
                        "description": "Maximum number of results to return",
                        "default": 10,
                    ]),
                    "path_filter": .object([
                        "type": "string",
                        "description": "Filter by path pattern (glob syntax)",
                    ]),
                    "format": .object([
                        "type": "string",
                        "description": "Output format: toon (compact), json, or human",
                        "enum": .array([.string("toon"), .string("json"), .string("human")]),
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
        // Extract arguments
        guard let query = arguments["query"]?.stringValue else {
            return .error("Missing required argument: query")
        }

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error("Query cannot be empty")
        }

        let path = arguments["path"]?.stringValue ?? "."
        let limit = arguments["limit"]?.intValue ?? 10
        let pathFilter = arguments["path_filter"]?.stringValue
        let formatArg = arguments["format"]?.stringValue

        // Validate arguments
        guard limit > 0 else {
            return .error("Limit must be greater than 0")
        }

        // Perform search
        do {
            // Get context and configuration
            let context = MCPContext.shared
            let config: Config
            do {
                config = try await context.getConfig(for: path)
            } catch ConfigError.notInitialized {
                return .error("""
                Project not initialized. No .swiftindex.toml found.

                Run 'swiftindex init' in the project directory first.
                """)
            }

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

            // Execute search for info snippets
            let results = try await searchEngine.searchInfoSnippets(
                query: query,
                limit: limit,
                pathFilter: pathFilter
            )

            // Determine format: argument > config default
            let format = formatArg ?? config.outputFormat

            // Format results based on requested format
            let output: String = switch format {
            case "json":
                formatResultsJSON(results: results, query: query)
            case "human":
                formatResultsHuman(results: results, query: query)
            default:
                formatResultsTOON(results: results, query: query)
            }

            return .text(output)
        } catch {
            return .error("Search failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    /// Formats results as TOON (Token-Optimized Object Notation).
    private func formatResultsTOON(results: [InfoSnippetSearchResult], query: String) -> String {
        var output = "docs_search{q,n}:\n"
        output += "  \"\(escapeString(query))\",\(results.count)\n\n"

        if results.isEmpty {
            return output
        }

        // Tabular results: rank, relevance%, path, lines, kind, breadcrumb, lang, tokens
        output += "snippets[\(results.count)]{r,rel,p,l,k,bc,lang,tok}:\n"

        for (index, result) in results.enumerated() {
            let rank = index + 1
            let relevance = result.relevancePercent
            let path = result.snippet.path
            let lines = "[\(result.snippet.startLine),\(result.snippet.endLine)]"
            let kind = result.snippet.kind.rawValue
            let bc = result.snippet.breadcrumb.map { "\"\(escapeString($0))\"" } ?? "~"
            let lang = result.snippet.language
            let tokens = result.snippet.tokenCount

            let row = "  \(rank),\(relevance),\"\(escapeString(path))\",\(lines),"
                + "\"\(kind)\",\(bc),\"\(lang)\",\(tokens)"
            output += row + "\n"
        }

        output += "\ncontent[\(results.count)]:\n"

        for result in results {
            // Truncate content for TOON output (first 20 lines max)
            let lines = result.snippet.content.split(separator: "\n", omittingEmptySubsequences: false)
            let preview = lines.prefix(20).joined(separator: "\n")
            let truncated = lines.count > 20

            output += "  ---\n"
            for line in preview.split(separator: "\n", omittingEmptySubsequences: false) {
                output += "  \(line)\n"
            }
            if truncated {
                output += "  ...\(lines.count - 20) more lines\n"
            }
        }

        return output
    }

    private func escapeString(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func formatResultsHuman(results: [InfoSnippetSearchResult], query: String) -> String {
        var output = "Documentation Search: \"\(query)\"\n"
        output += "Found \(results.count) results\n"
        output += String(repeating: "─", count: 60) + "\n"

        if results.isEmpty {
            output += "\nNo documentation found.\n"
            return output
        }

        for (index, result) in results.enumerated() {
            output += "\n[\(index + 1)] \(result.snippet.path):\(result.snippet.startLine)-\(result.snippet.endLine)\n"
            output += "    Kind: \(result.snippet.kind.rawValue)\n"

            // Show breadcrumb if available
            if let breadcrumb = result.snippet.breadcrumb {
                output += "    Location: \(breadcrumb)\n"
            }

            output += "    Relevance: \(result.relevancePercent)%\n"

            // Show content preview (first 10 lines)
            let lines = result.snippet.content.split(separator: "\n", omittingEmptySubsequences: false)
            let preview = lines.prefix(10)
            output += "    ────\n"
            for line in preview {
                output += "    \(line)\n"
            }
            if lines.count > 10 {
                output += "    ... (\(lines.count - 10) more lines)\n"
            }
        }

        return output
    }

    private func formatResultsJSON(results: [InfoSnippetSearchResult], query: String) -> String {
        var jsonResults: [[String: Any]] = []

        for result in results {
            var item: [String: Any] = [
                "id": result.snippet.id,
                "path": result.snippet.path,
                "start_line": result.snippet.startLine,
                "end_line": result.snippet.endLine,
                "kind": result.snippet.kind.rawValue,
                "content": result.snippet.content,
                "token_count": result.snippet.tokenCount,
                "language": result.snippet.language,
                "relevance_percent": result.relevancePercent,
            ]

            if let breadcrumb = result.snippet.breadcrumb {
                item["breadcrumb"] = breadcrumb
            }

            if let chunkId = result.snippet.chunkId {
                item["chunk_id"] = chunkId
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
        guard let data = try? JSONCodec.serialize(dict, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}
