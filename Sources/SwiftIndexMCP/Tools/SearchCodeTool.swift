// MARK: - SearchCodeTool

import Foundation
import SwiftIndexCore

/// MCP tool for searching indexed code.
///
/// Performs hybrid semantic search combining BM25 keyword search
/// with vector similarity for accurate code retrieval.
public struct SearchCodeTool: MCPToolHandler, Sendable {
    public let definition: MCPTool

    public init() {
        self.definition = MCPTool(
            name: "search_code",
            description: """
                Search indexed code using hybrid semantic search.
                Combines BM25 keyword matching with vector similarity
                for accurate code retrieval. Returns ranked results
                with code snippets and metadata.
                """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object([
                        "type": "string",
                        "description": "Natural language search query"
                    ]),
                    "limit": .object([
                        "type": "integer",
                        "description": "Maximum number of results to return",
                        "default": 10,
                        "minimum": 1,
                        "maximum": 100
                    ]),
                    "path_filter": .object([
                        "type": "string",
                        "description": "Optional glob pattern to filter results by path"
                    ]),
                    "semantic_weight": .object([
                        "type": "number",
                        "description": "Weight for semantic search (0.0-1.0, default 0.7)",
                        "default": 0.7,
                        "minimum": 0.0,
                        "maximum": 1.0
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        )
    }

    public func execute(arguments: JSONValue) async throws -> ToolCallResult {
        // Extract query argument
        guard let query = arguments["query"]?.stringValue else {
            return .error("Missing required argument: query")
        }

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error("Query cannot be empty")
        }

        let limit = arguments["limit"]?.intValue ?? 10
        let pathFilter = arguments["path_filter"]?.stringValue
        let semanticWeight = arguments["semantic_weight"]?.doubleValue.map { Float($0) } ?? 0.7

        // Build search options
        let options = SearchOptions(
            limit: limit,
            semanticWeight: semanticWeight,
            pathFilter: pathFilter
        )

        // Perform search
        do {
            let results = try await performSearch(query: query, options: options)
            return .text(formatResults(results, query: query))
        } catch {
            return .error("Search failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func performSearch(
        query: String,
        options: SearchOptions
    ) async throws -> [SearchResultDTO] {
        // TODO: Integrate with actual search engine when implemented
        // For now, return placeholder results

        // Placeholder implementation showing expected output format
        return [
            SearchResultDTO(
                path: "Sources/Example/AuthService.swift",
                startLine: 45,
                endLine: 62,
                kind: "function",
                score: 0.892,
                content: """
                    func authenticate(username: String, password: String) async throws -> User {
                        let hashedPassword = try hashPassword(password)
                        guard let user = try await userStore.findByUsername(username) else {
                            throw AuthError.userNotFound
                        }
                        guard user.passwordHash == hashedPassword else {
                            throw AuthError.invalidCredentials
                        }
                        return user
                    }
                    """,
                symbols: ["authenticate(username:password:)"],
                matchType: "semantic"
            )
        ]
    }

    private func formatResults(_ results: [SearchResultDTO], query: String) -> String {
        var output = "{\n"
        output += "  \"query\": \"\(escapeJSON(query))\",\n"
        output += "  \"count\": \(results.count),\n"
        output += "  \"results\": [\n"

        for (index, result) in results.enumerated() {
            output += "    {\n"
            output += "      \"path\": \"\(escapeJSON(result.path))\",\n"
            output += "      \"start_line\": \(result.startLine),\n"
            output += "      \"end_line\": \(result.endLine),\n"
            output += "      \"kind\": \"\(result.kind)\",\n"
            output += "      \"score\": \(String(format: "%.3f", result.score)),\n"
            output += "      \"symbols\": [\(result.symbols.map { "\"\(escapeJSON($0))\"" }.joined(separator: ", "))],\n"
            output += "      \"match_type\": \"\(result.matchType)\",\n"
            output += "      \"content\": \"\(escapeJSON(result.content))\"\n"
            output += "    }"
            if index < results.count - 1 {
                output += ","
            }
            output += "\n"
        }

        output += "  ]\n"
        output += "}"

        return output
    }

    private func escapeJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - SearchResultDTO

private struct SearchResultDTO {
    let path: String
    let startLine: Int
    let endLine: Int
    let kind: String
    let score: Float
    let content: String
    let symbols: [String]
    let matchType: String
}
