// MARK: - CodeResearchTool

import Foundation
import SwiftIndexCore

/// MCP tool for multi-hop code research.
///
/// Performs deep architectural analysis by following references
/// across the codebase, building a comprehensive understanding
/// of code relationships and patterns.
public struct CodeResearchTool: MCPToolHandler, Sendable {
    public let definition: MCPTool

    public init() {
        definition = MCPTool(
            name: "code_research",
            title: "Code Research",
            description: """
            Perform multi-hop code research and architectural analysis.
            Follows references across the codebase to understand
            relationships, dependencies, and patterns. Returns
            comprehensive analysis with cross-references.
            """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object([
                        "type": "string",
                        "description": "Research query or topic to investigate",
                    ]),
                    "path": .object([
                        "type": "string",
                        "description": "Path to the indexed codebase (default: current directory)",
                        "default": ".",
                    ]),
                    "depth": .object([
                        "type": "integer",
                        "description": "Maximum depth for reference following (1-5)",
                        "default": 2,
                        "minimum": 1,
                        "maximum": 5,
                    ]),
                    "focus": .object([
                        "type": "string",
                        "description": "Optional focus area: 'architecture', 'dependencies', 'patterns', 'flow'",
                        "enum": .array([
                            .string("architecture"),
                            .string("dependencies"),
                            .string("patterns"),
                            .string("flow"),
                        ]),
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
        try await execute(arguments: arguments, context: nil)
    }

    public func execute(arguments: JSONValue, context: ToolExecutionContext?) async throws -> ToolCallResult {
        guard let query = arguments["query"]?.stringValue,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .error("Missing or empty required argument: query")
        }

        let path = arguments["path"]?.stringValue ?? "."
        let depth = arguments["depth"]?.intValue ?? 2
        let focus = arguments["focus"]?.stringValue

        guard (1 ... 5).contains(depth) else {
            return .error("Depth must be between 1 and 5")
        }

        do {
            let result = try await performResearch(
                query: query,
                path: path,
                depth: depth,
                focus: focus,
                context: context
            )
            return .text(formatResult(result))
        } catch is CancellationError {
            return .error("Research was cancelled")
        } catch {
            return .error("Research failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func performResearch(
        query: String,
        path: String,
        depth: Int,
        focus: String?,
        context: ToolExecutionContext?
    ) async throws -> ResearchResult {
        let mcpContext = MCPContext.shared

        await context?.reportStatus("Loading configuration...")
        let config = try await mcpContext.getConfig(for: path)
        try await context?.checkCancellation()

        guard await mcpContext.indexExists(for: path, config: config) else {
            throw MCPError.executionFailed(
                "No index found for path: \(path). Run 'index_codebase' first."
            )
        }

        await context?.reportStatus("Initializing search engine...")
        let searchEngine = try await mcpContext.createSearchEngine(for: path, config: config)
        try await context?.checkCancellation()

        let searchOptions = SearchOptions(
            limit: 20,
            semanticWeight: 0.7,
            rrfK: config.rrfK,
            multiHop: true,
            multiHopDepth: depth
        )

        await context?.reportProgress(current: 1, total: depth + 1, message: "Searching")
        let results = try await searchEngine.search(query: query, options: searchOptions)
        try await context?.checkCancellation()

        await context?.reportProgress(current: depth, total: depth + 1, message: "Analyzing references")
        let references = collectReferences(from: results)

        await context?.reportProgress(current: depth + 1, total: depth + 1, message: "Generating analysis")
        let analysis = generateAnalysis(query: query, focus: focus, results: results)

        return ResearchResult(
            query: query,
            depth: depth,
            focus: focus,
            analysis: analysis,
            resultCount: results.count,
            references: references,
            relatedTopics: extractRelatedTopics(from: results)
        )
    }

    private func collectReferences(from results: [SearchResult]) -> [CodeReference] {
        var references: [CodeReference] = []
        var seenPaths = Set<String>()

        for result in results where seenPaths.insert(result.chunk.path).inserted {
            let chunk = result.chunk
            let relationship = result.isMultiHop ? "referenced" : "direct_match"

            // Add symbols from this chunk
            for symbol in chunk.symbols {
                references.append(CodeReference(
                    path: chunk.path,
                    symbol: symbol,
                    kind: chunk.kind.rawValue,
                    relationship: relationship,
                    hopLevel: result.hopDepth
                ))
            }

            // Add chunk's outgoing references
            for ref in chunk.references {
                references.append(CodeReference(
                    path: chunk.path,
                    symbol: ref,
                    kind: "reference",
                    relationship: "uses",
                    hopLevel: result.hopDepth + 1
                ))
            }
        }

        return Array(references.prefix(50))
    }

    private func generateAnalysis(
        query: String,
        focus: String?,
        results: [SearchResult]
    ) -> String {
        let focusContext = focus.map { " with focus on \($0)" } ?? ""

        guard !results.isEmpty else {
            return "No code found matching \"\(query)\"\(focusContext)."
        }

        var lines: [String] = ["Analysis of \"\(query)\"\(focusContext):", ""]

        // Count by kind
        var kindCounts: [String: Int] = [:]
        for result in results {
            kindCounts[result.chunk.kind.rawValue, default: 0] += 1
        }

        lines.append("Found \(results.count) code chunks:")
        for (kind, count) in kindCounts.sorted(by: { $0.value > $1.value }) {
            lines.append("- \(count) \(kind)(s)")
        }

        // Unique files
        let uniqueFiles = Set(results.map(\.chunk.path))
        lines.append("")
        lines.append("Across \(uniqueFiles.count) file(s):")
        for file in uniqueFiles.prefix(10) {
            lines.append("- \(file)")
        }
        if uniqueFiles.count > 10 {
            lines.append("- ... and \(uniqueFiles.count - 10) more")
        }

        // Multi-hop stats
        let multiHopCount = results.filter(\.isMultiHop).count
        if multiHopCount > 0 {
            lines.append("")
            lines.append("Multi-hop references: \(multiHopCount) results from following references")
        }

        // Key symbols
        let symbols = Set(results.flatMap(\.chunk.symbols))
        if !symbols.isEmpty {
            lines.append("")
            lines.append("Key symbols:")
            for symbol in symbols.prefix(10) {
                lines.append("- \(symbol)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func extractRelatedTopics(from results: [SearchResult]) -> [String] {
        var topics = Set<String>()

        for result in results {
            topics.insert("\(result.chunk.kind.rawValue) implementation")
            for symbol in result.chunk.symbols.prefix(2) {
                topics.insert(symbol)
            }
        }

        return Array(topics.sorted().prefix(10))
    }

    private func formatResult(_ result: ResearchResult) -> String {
        guard let data = try? JSONCodec.encodePrettySorted(result),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}

// MARK: - Research Result Types

private struct ResearchResult: Encodable {
    let query: String
    let depth: Int
    let focus: String?
    let analysis: String
    let resultCount: Int
    let references: [CodeReference]
    let relatedTopics: [String]

    private enum CodingKeys: String, CodingKey {
        case query, depth, focus, analysis
        case resultCount = "result_count"
        case references
        case relatedTopics = "related_topics"
    }
}

private struct CodeReference: Encodable {
    let path: String
    let symbol: String
    let kind: String
    let relationship: String
    let hopLevel: Int

    private enum CodingKeys: String, CodingKey {
        case path, symbol, kind, relationship
        case hopLevel = "hop_level"
    }
}
