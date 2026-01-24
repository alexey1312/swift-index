// MARK: - SearchCodeTool

import Foundation
import SwiftIndexCore
import ToonFormat

/// MCP tool for searching indexed Swift codebases.
///
/// Performs hybrid semantic search combining BM25 keyword matching
/// with vector similarity search using RRF fusion.
public struct SearchCodeTool: MCPToolHandler, Sendable {
    public let definition: MCPTool

    public init() {
        definition = MCPTool(
            name: "search_code",
            title: "Code Search",
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
                    "format": .object([
                        "type": "string",
                        "description": "Output format: toon (compact), json, or human",
                        "enum": .array([.string("toon"), .string("json"), .string("human")]),
                    ]),
                    "expand_query": .object([
                        "type": "boolean",
                        "description": "Use LLM to expand query with synonyms and related concepts",
                        "default": false,
                    ]),
                    "synthesize": .object([
                        "type": "boolean",
                        "description": "Generate LLM summary and follow-up suggestions",
                        "default": false,
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
        let limit = arguments["limit"]?.intValue ?? 20
        let semanticWeight = arguments["semantic_weight"]?.doubleValue.map { Float($0) } ?? 0.7
        let extensionsArg = arguments["extensions"]?.stringValue
        let pathFilter = arguments["path_filter"]?.stringValue
        let formatArg = arguments["format"]?.stringValue
        let expandQuery = arguments["expand_query"]?.boolValue ?? false
        let synthesize = arguments["synthesize"]?.boolValue ?? false

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

            // Execute search with optional query expansion
            let results: [SearchResult]
            var expandedQuery: ExpandedQuery?

            if expandQuery {
                // Get query expander (may return nil if not configured)
                let expander = try await context.getQueryExpander(config: config)
                let timeout = config.searchEnhancement.utility.timeout

                let enhancedResult = try await searchEngine.searchWithExpansion(
                    query: query,
                    options: searchOptions,
                    expander: expander,
                    timeout: timeout
                )
                results = enhancedResult.results
                expandedQuery = enhancedResult.expandedQuery
            } else {
                results = try await searchEngine.search(query: query, options: searchOptions)
            }

            // Generate synthesis and follow-ups if requested
            var synthesis: Synthesis?
            var followUps: [FollowUpSuggestion]?

            if synthesize, !results.isEmpty {
                let synthesisTimeout = config.searchEnhancement.synthesis.timeout
                let utilityTimeout = config.searchEnhancement.utility.timeout

                // Convert SearchResults to SynthesisInputs
                let synthesisInputs = results.map { result in
                    SynthesisInput(
                        filePath: result.chunk.path,
                        content: result.chunk.content,
                        kind: result.chunk.kind.rawValue,
                        breadcrumb: result.chunk.breadcrumb,
                        docComment: result.chunk.docComment
                    )
                }

                // Get synthesizer and generator (may return nil if not configured)
                if let synthesizer = try await context.getResultSynthesizer(config: config) {
                    synthesis = try? await synthesizer.synthesize(
                        query: query,
                        results: synthesisInputs,
                        timeout: synthesisTimeout
                    )
                }

                // Generate follow-ups using the synthesis summary or a default summary
                if let generator = try await context.getFollowUpGenerator(config: config) {
                    let resultSummary = synthesis?.summary ?? "Found \(results.count) code results"
                    followUps = try? await generator.generate(
                        query: query,
                        resultSummary: resultSummary,
                        timeout: utilityTimeout
                    )
                }
            }

            // Determine format: argument > config default
            let format = formatArg ?? config.outputFormat

            // Format results based on requested format
            let enhancement = EnhancementInfo(
                expandedQuery: expandedQuery,
                synthesis: synthesis,
                followUps: followUps
            )

            let output: String = switch format {
            case "json":
                formatResultsJSON(results: results, query: query, enhancement: enhancement)
            case "human":
                formatResultsHuman(results: results, query: query, enhancement: enhancement)
            default:
                formatResultsTOON(results: results, query: query, enhancement: enhancement)
            }

            return .text(output)
        } catch {
            return .error("Search failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Enhancement Info

    /// Container for LLM enhancement data.
    private struct EnhancementInfo {
        let expandedQuery: ExpandedQuery?
        let synthesis: Synthesis?
        let followUps: [FollowUpSuggestion]?

        var hasAny: Bool {
            expandedQuery != nil || synthesis != nil || followUps != nil
        }

        static let empty = EnhancementInfo(expandedQuery: nil, synthesis: nil, followUps: nil)
    }

    // MARK: - Private

    /// Formats results as TOON (Token-Optimized Object Notation).
    ///
    /// TOON is a compact format that reduces token usage by 40-60% compared to JSON,
    /// making it ideal for LLM consumption.
    private func formatResultsTOON(
        results: [SearchResult],
        query: String,
        enhancement: EnhancementInfo = .empty
    ) -> String {
        var output = "search{q,n}:\n"
        output += "  \"\(escapeString(query))\",\(results.count)\n\n"

        // Add expanded query info if available
        if let expanded = enhancement.expandedQuery {
            output += "expanded{syn,rel,var}:\n"
            let sep = "\",\""
            let synStr = expanded.synonyms.isEmpty ? "[]" : "[\"\(expanded.synonyms.joined(separator: sep))\"]"
            let relStr = expanded.relatedConcepts.isEmpty
                ? "[]" : "[\"\(expanded.relatedConcepts.joined(separator: sep))\"]"
            let varStr = expanded.variations.isEmpty ? "[]" : "[\"\(expanded.variations.joined(separator: sep))\"]"
            output += "  \(synStr),\(relStr),\(varStr)\n\n"
        }

        if results.isEmpty {
            return output
        }

        // Tabular results with rich metadata: rank, relevance%, path, lines, kind, symbols, lang, tokens
        output += "results[\(results.count)]{r,rel,p,l,k,s,lang,tok}:\n"

        for (index, result) in results.enumerated() {
            let rank = index + 1
            let relevance = result.relevancePercent
            let path = result.chunk.path
            let lines = "[\(result.chunk.startLine),\(result.chunk.endLine)]"
            let kind = result.chunk.kind.rawValue
            let symbols = result.chunk.symbols.isEmpty
                ? "[]"
                : "[\"\(result.chunk.symbols.map { escapeString($0) }.joined(separator: "\",\""))\"]"
            let lang = result.chunk.language
            let tokens = result.chunk.tokenCount

            let row = "  \(rank),\(relevance),\"\(escapeString(path))\",\(lines),"
                + "\"\(kind)\",\(symbols),\"\(lang)\",\(tokens)"
            output += row + "\n"
        }

        // Metadata section for signatures and breadcrumbs (compact)
        let hasMetadata = results.contains { $0.chunk.signature != nil || $0.chunk.breadcrumb != nil }
        if hasMetadata {
            output += "\nmeta[\(results.count)]{sig,bc}:\n"
            for result in results {
                let sig = result.chunk.signature.map { "\"\(escapeString($0))\"" } ?? "~"
                let bc = result.chunk.breadcrumb.map { "\"\(escapeString($0))\"" } ?? "~"
                output += "  \(sig),\(bc)\n"
            }
        }

        // Doc comments section (compact, truncated)
        let hasDocComments = results.contains { $0.chunk.docComment != nil }
        if hasDocComments {
            output += "\ndocs[\(results.count)]:\n"
            for result in results {
                if let doc = result.chunk.docComment {
                    let truncated = String(doc.prefix(150)).replacingOccurrences(of: "\n", with: " ")
                    let suffix = doc.count > 150 ? "..." : ""
                    output += "  \"\(escapeString(truncated))\(suffix)\"\n"
                } else {
                    output += "  ~\n"
                }
            }
        }

        // Generated descriptions section
        let hasDescriptions = results.contains { $0.chunk.generatedDescription != nil }
        if hasDescriptions {
            output += "\ndescs[\(results.count)]:\n"
            for result in results {
                if let desc = result.chunk.generatedDescription {
                    output += "  \"\(escapeString(desc))\"\n"
                } else {
                    output += "  ~\n"
                }
            }
        }

        output += "\ncode[\(results.count)]:\n"

        for result in results {
            // Truncate content for TOON output (first 15 lines max for MCP)
            let lines = result.chunk.content.split(separator: "\n", omittingEmptySubsequences: false)
            let preview = lines.prefix(15).joined(separator: "\n")
            let truncated = lines.count > 15

            output += "  ---\n"
            for line in preview.split(separator: "\n", omittingEmptySubsequences: false) {
                output += "  \(line)\n"
            }
            if truncated {
                output += "  ...\(lines.count - 15) more lines\n"
            }
        }

        // Add synthesis if available
        if let synthesis = enhancement.synthesis {
            output += "\nsynthesis{sum,insights,refs,conf}:\n"
            let summary = escapeString(synthesis.summary)
            let keyInsights = synthesis.keyInsights.isEmpty
                ? "[]"
                : "[\"\(synthesis.keyInsights.map { escapeString($0) }.joined(separator: "\",\""))\"]"
            let codeRefs = synthesis.codeReferences.isEmpty
                ? "[]"
                : "[\"\(synthesis.codeReferences.map { escapeString($0.formatted) }.joined(separator: "\",\""))\"]"
            output += "  \"\(summary)\"\n"
            output += "  \(keyInsights)\n"
            output += "  \(codeRefs)\n"
            output += "  \(synthesis.confidence)\n"
        }

        // Add follow-up suggestions if available
        if let followUps = enhancement.followUps, !followUps.isEmpty {
            output += "\nfollow_ups[\(followUps.count)]{q,cat}:\n"
            for followUp in followUps {
                output += "  \"\(escapeString(followUp.query))\",\"\(followUp.category.rawValue)\"\n"
            }
        }

        return output
    }

    private func escapeString(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func formatResultsHuman(
        results: [SearchResult],
        query: String,
        enhancement: EnhancementInfo = .empty
    ) -> String {
        var output = "Search: \"\(query)\"\n"
        output += "Found \(results.count) results\n"

        // Show expanded query info if available
        if let expanded = enhancement.expandedQuery {
            output += formatExpandedQueryHuman(expanded)
        }

        output += String(repeating: "─", count: 60) + "\n"

        if results.isEmpty {
            output += "\nNo results found.\n"
            return output
        }

        for (index, result) in results.enumerated() {
            output += formatResultItemHuman(result, index: index)
        }

        // Add synthesis if available
        if let synthesis = enhancement.synthesis {
            output += formatSynthesisHuman(synthesis)
        }

        // Add follow-up suggestions if available
        if let followUps = enhancement.followUps, !followUps.isEmpty {
            output += formatFollowUpsHuman(followUps)
        }

        return output
    }

    private func formatExpandedQueryHuman(_ expanded: ExpandedQuery) -> String {
        var output = "\nQuery Expansion:\n"
        if !expanded.synonyms.isEmpty {
            output += "  Synonyms: \(expanded.synonyms.joined(separator: ", "))\n"
        }
        if !expanded.relatedConcepts.isEmpty {
            output += "  Related: \(expanded.relatedConcepts.joined(separator: ", "))\n"
        }
        if !expanded.variations.isEmpty {
            output += "  Variations: \(expanded.variations.joined(separator: ", "))\n"
        }
        return output
    }

    private func formatResultItemHuman(_ result: SearchResult, index: Int) -> String {
        var output = "\n[\(index + 1)] \(result.chunk.path):\(result.chunk.startLine)-\(result.chunk.endLine)\n"
        output += "    Kind: \(result.chunk.kind.rawValue)\n"

        if !result.chunk.symbols.isEmpty {
            output += "    Symbols: \(result.chunk.symbols.joined(separator: ", "))\n"
        }
        if let breadcrumb = result.chunk.breadcrumb {
            output += "    Location: \(breadcrumb)\n"
        }
        if let signature = result.chunk.signature {
            output += "    Signature: \(signature)\n"
        }

        output += "    Relevance: \(result.relevancePercent)%"
        if let bm25Rank = result.bm25Rank {
            output += " (keyword rank #\(bm25Rank))"
        }
        output += "\n"

        if let description = result.chunk.generatedDescription {
            output += "    Description: \(description)\n"
        }

        if let docComment = result.chunk.docComment {
            let truncated = String(docComment.prefix(100))
            let suffix = docComment.count > 100 ? "..." : ""
            output += "    Doc: \(truncated)\(suffix)\n"
        }

        // Show code preview (first 5 lines)
        let lines = result.chunk.content.split(separator: "\n", omittingEmptySubsequences: false)
        let preview = lines.prefix(5)
        output += "    ────\n"
        for line in preview {
            output += "    \(line)\n"
        }
        if lines.count > 5 {
            output += "    ... (\(lines.count - 5) more lines)\n"
        }
        return output
    }

    private func formatSynthesisHuman(_ synthesis: Synthesis) -> String {
        var output = "\n" + String(repeating: "─", count: 60) + "\n"
        output += "Summary:\n"
        output += "  \(synthesis.summary)\n"
        if !synthesis.keyInsights.isEmpty {
            output += "\nKey Insights:\n"
            for insight in synthesis.keyInsights {
                output += "  • \(insight)\n"
            }
        }
        if !synthesis.codeReferences.isEmpty {
            output += "\nCode References:\n"
            for ref in synthesis.codeReferences {
                output += "  • \(ref.formatted)\n"
            }
        }
        output += "\nConfidence: \(Int(synthesis.confidence * 100))%\n"
        return output
    }

    private func formatFollowUpsHuman(_ followUps: [FollowUpSuggestion]) -> String {
        var output = "\n" + String(repeating: "─", count: 60) + "\n"
        output += "Suggested Follow-ups:\n"
        for (index, followUp) in followUps.enumerated() {
            var line = "  \(index + 1). \(followUp.query)"
            if let rationale = followUp.rationale {
                line += " - \(rationale)"
            }
            output += line + "\n"
        }
        return output
    }

    private func formatResultsJSON(
        results: [SearchResult],
        query: String,
        enhancement: EnhancementInfo = .empty
    ) -> String {
        var jsonResults: [[String: Any]] = []

        for result in results {
            var item: [String: Any] = [
                "id": result.chunk.id,
                "path": result.chunk.path,
                "start_line": result.chunk.startLine,
                "end_line": result.chunk.endLine,
                "kind": result.chunk.kind.rawValue,
                "symbols": result.chunk.symbols,
                "relevance_percent": result.relevancePercent,
                "content": result.chunk.content,
                "token_count": result.chunk.tokenCount,
                "language": result.chunk.language,
            ]

            // Rich metadata fields
            if let docComment = result.chunk.docComment {
                item["doc_comment"] = docComment
            }
            if let signature = result.chunk.signature {
                item["signature"] = signature
            }
            if let breadcrumb = result.chunk.breadcrumb {
                item["breadcrumb"] = breadcrumb
            }
            if let description = result.chunk.generatedDescription {
                item["generated_description"] = description
            }

            if let bm25Score = result.bm25Score {
                item["bm25_score"] = Double(bm25Score)
            }
            if let semanticScore = result.semanticScore {
                item["semantic_score"] = Double(semanticScore)
            }

            jsonResults.append(item)
        }

        var output: [String: Any] = [
            "query": query,
            "result_count": results.count,
            "results": jsonResults,
        ]

        // Add expanded query info if available
        if let expanded = enhancement.expandedQuery {
            output["expanded_query"] = [
                "original": expanded.originalQuery,
                "synonyms": expanded.synonyms,
                "related_concepts": expanded.relatedConcepts,
                "variations": expanded.variations,
            ]
        }

        // Add synthesis if available
        if let synthesis = enhancement.synthesis {
            output["synthesis"] = [
                "summary": synthesis.summary,
                "key_insights": synthesis.keyInsights,
                "code_references": synthesis.codeReferences.map { [
                    "file_path": $0.filePath,
                    "line_number": $0.lineNumber as Any,
                    "description": $0.description as Any,
                ] },
                "confidence": Double(synthesis.confidence),
            ]
        }

        // Add follow-up suggestions if available
        if let followUps = enhancement.followUps {
            output["follow_up_suggestions"] = followUps.map { [
                "query": $0.query,
                "rationale": $0.rationale as Any,
                "category": $0.category.rawValue,
            ] }
        }

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
