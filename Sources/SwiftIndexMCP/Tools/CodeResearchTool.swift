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
        // Extract query argument
        guard let query = arguments["query"]?.stringValue else {
            return .error("Missing required argument: query")
        }

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error("Query cannot be empty")
        }

        let path = arguments["path"]?.stringValue ?? "."
        let depth = arguments["depth"]?.intValue ?? 2
        let focus = arguments["focus"]?.stringValue

        // Validate depth
        guard depth >= 1, depth <= 5 else {
            return .error("Depth must be between 1 and 5")
        }

        // Perform research
        do {
            let result = try await performResearch(
                query: query,
                path: path,
                depth: depth,
                focus: focus
            )
            return .text(formatResult(result))
        } catch {
            return .error("Research failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func performResearch(
        query: String,
        path: String,
        depth: Int,
        focus: String?
    ) async throws -> ResearchResult {
        let context = MCPContext.shared
        let config = try await context.getConfig(for: path)

        // Check if index exists
        guard await context.indexExists(for: path, config: config) else {
            throw MCPError.executionFailed(
                "No index found for path: \(path). Run 'index_codebase' first."
            )
        }

        // Create search engine
        let searchEngine = try await context.createSearchEngine(for: path, config: config)

        // Build search options with multi-hop enabled
        let searchOptions = SearchOptions(
            limit: 20,
            semanticWeight: 0.7,
            rrfK: config.rrfK,
            multiHop: true,
            multiHopDepth: depth
        )

        // Execute initial search
        let initialResults = try await searchEngine.search(query: query, options: searchOptions)

        // Collect references from results
        var references: [CodeReference] = []
        var seenPaths = Set<String>()

        for result in initialResults {
            if !seenPaths.contains(result.chunk.path) {
                seenPaths.insert(result.chunk.path)

                // Add main result as reference
                for symbol in result.chunk.symbols {
                    references.append(CodeReference(
                        path: result.chunk.path,
                        symbol: symbol,
                        kind: result.chunk.kind.rawValue,
                        relationship: result.isMultiHop ? "referenced" : "direct_match",
                        hopLevel: result.hopDepth
                    ))
                }

                // Add chunk's references if available
                for ref in result.chunk.references {
                    references.append(CodeReference(
                        path: result.chunk.path,
                        symbol: ref,
                        kind: "reference",
                        relationship: "uses",
                        hopLevel: result.hopDepth + 1
                    ))
                }
            }
        }

        // Limit references to reasonable count
        let limitedReferences = Array(references.prefix(50))

        // Generate analysis
        let analysis = generateAnalysis(
            query: query,
            focus: focus,
            results: initialResults,
            references: limitedReferences
        )

        // Extract related topics from results
        let relatedTopics = extractRelatedTopics(from: initialResults)

        return ResearchResult(
            query: query,
            depth: depth,
            focus: focus,
            analysis: analysis,
            resultCount: initialResults.count,
            references: limitedReferences,
            relatedTopics: relatedTopics
        )
    }

    private func generateAnalysis(
        query: String,
        focus: String?,
        results: [SearchResult],
        references: [CodeReference]
    ) -> String {
        let focusContext = focus.map { " with focus on \($0)" } ?? ""

        guard !results.isEmpty else {
            return "No code found matching \"\(query)\"\(focusContext)."
        }

        var analysis = "Analysis of \"\(query)\"\(focusContext):\n\n"

        // Count kinds
        var kindCounts: [String: Int] = [:]
        for result in results {
            let kind = result.chunk.kind.rawValue
            kindCounts[kind, default: 0] += 1
        }

        analysis += "Found \(results.count) code chunks:\n"
        for (kind, count) in kindCounts.sorted(by: { $0.value > $1.value }) {
            analysis += "- \(count) \(kind)(s)\n"
        }

        // Count unique files
        let uniqueFiles = Set(results.map(\.chunk.path))
        analysis += "\nAcross \(uniqueFiles.count) file(s):\n"
        for file in uniqueFiles.prefix(10) {
            analysis += "- \(file)\n"
        }
        if uniqueFiles.count > 10 {
            analysis += "- ... and \(uniqueFiles.count - 10) more\n"
        }

        // Multi-hop stats
        let multiHopResults = results.filter(\.isMultiHop)
        if !multiHopResults.isEmpty {
            analysis += "\nMulti-hop references: \(multiHopResults.count) results from following references\n"
        }

        // Key symbols
        let symbols = results.flatMap(\.chunk.symbols)
        if !symbols.isEmpty {
            let uniqueSymbols = Array(Set(symbols)).prefix(10)
            analysis += "\nKey symbols:\n"
            for symbol in uniqueSymbols {
                analysis += "- \(symbol)\n"
            }
        }

        return analysis
    }

    private func extractRelatedTopics(from results: [SearchResult]) -> [String] {
        var topics = Set<String>()

        for result in results {
            // Add chunk kind as topic
            topics.insert("\(result.chunk.kind.rawValue) implementation")

            // Add symbols as topics
            for symbol in result.chunk.symbols.prefix(2) {
                topics.insert(symbol)
            }
        }

        return Array(topics).sorted().prefix(10).map(\.self)
    }

    private func formatResult(_ result: ResearchResult) -> String {
        var output: [String: Any] = [
            "query": result.query,
            "depth": result.depth,
            "result_count": result.resultCount,
            "analysis": result.analysis,
            "references": result.references.map { ref in
                [
                    "path": ref.path,
                    "symbol": ref.symbol,
                    "kind": ref.kind,
                    "relationship": ref.relationship,
                    "hop_level": ref.hopLevel,
                ] as [String: Any]
            },
            "related_topics": result.relatedTopics,
        ]

        if let focus = result.focus {
            output["focus"] = focus
        }

        guard let data = try? JSONCodec.serialize(output, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}

// MARK: - Research Result Types

private struct ResearchResult {
    let query: String
    let depth: Int
    let focus: String?
    let analysis: String
    let resultCount: Int
    let references: [CodeReference]
    let relatedTopics: [String]
}

private struct CodeReference {
    let path: String
    let symbol: String
    let kind: String
    let relationship: String
    let hopLevel: Int
}
