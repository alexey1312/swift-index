// MARK: - Search Command

import ArgumentParser
import Foundation
import Logging
import SwiftIndexCore
import ToonFormat

/// Output format for search results.
enum OutputFormat: String, ExpressibleByArgument, CaseIterable, Sendable {
    case human
    case json
    case toon

    static var defaultValueDescription: String { "human" }
}

/// Command to search the indexed codebase.
///
/// Usage:
///   swiftindex search "authentication flow"
///   swiftindex search "error handling" --limit 10
///   swiftindex search "async patterns" --format toon
struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search the indexed codebase",
        discussion: """
        Performs hybrid semantic search combining BM25 keyword matching
        with vector similarity search using RRF (Reciprocal Rank Fusion).

        Results include code chunks with context, file paths, and
        relevance scores.
        """
    )

    // MARK: - Arguments

    @Argument(
        help: "Search query (natural language or code pattern)"
    )
    var query: String

    // MARK: - Options

    @Option(
        name: .shortAndLong,
        help: "Maximum number of results to return"
    )
    var limit: Int = 20

    @Option(
        name: .long,
        help: "Output format: human, json, or toon (token-optimized). Default from config."
    )
    var format: OutputFormat?

    @Flag(
        name: .long,
        help: "Output results as JSON (deprecated, use --format json)"
    )
    var json: Bool = false

    @Option(
        name: .shortAndLong,
        help: "Path to configuration file"
    )
    var config: String?

    @Option(
        name: .shortAndLong,
        help: "Path to the indexed codebase (default: current directory)"
    )
    var path: String = "."

    @Option(
        name: .long,
        help: "Semantic weight (0.0 = BM25 only, 1.0 = semantic only)"
    )
    var semanticWeight: Float = 0.7

    @Option(
        name: .long,
        help: "Filter by file extension (comma-separated, e.g., swift,ts)"
    )
    var extensions: String?

    @Option(
        name: .long,
        help: "Filter by path pattern (glob syntax)"
    )
    var pathFilter: String?

    @Flag(
        name: .long,
        help: "Enable multi-hop reference following"
    )
    var multiHop: Bool = false

    @Flag(
        name: .shortAndLong,
        help: "Enable verbose debug output"
    )
    var verbose: Bool = false

    @Flag(
        name: .long,
        help: "Use LLM to expand query with related terms (requires search.enhancement config)"
    )
    var expandQuery: Bool = false

    @Flag(
        name: .long,
        help: "Generate LLM summary and follow-up suggestions (requires search.enhancement config)"
    )
    var synthesize: Bool = false

    // MARK: - Execution

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func run() async throws {
        let logger = CLIUtils.makeLogger(verbose: verbose)
        logger.info("Starting search", metadata: ["query": "\(query)"])

        // Resolve path
        let resolvedPath = CLIUtils.resolvePath(path)
        logger.debug("Resolved path: \(resolvedPath)")

        // Load configuration
        let configuration = try CLIUtils.loadConfig(from: config, projectDirectory: resolvedPath, logger: logger)

        // Validate limit
        guard limit > 0 else {
            throw ValidationError("Limit must be greater than 0")
        }

        // Validate semantic weight
        guard semanticWeight >= 0, semanticWeight <= 1 else {
            throw ValidationError("Semantic weight must be between 0.0 and 1.0")
        }

        logger.debug("Search configuration", metadata: [
            "limit": "\(limit)",
            "semanticWeight": "\(semanticWeight)",
            "rrfK": "\(configuration.rrfK)",
        ])

        // Determine index path
        let indexPath = (resolvedPath as NSString).appendingPathComponent(configuration.indexPath)

        // Check if index exists
        guard FileManager.default.fileExists(atPath: indexPath) else {
            throw ValidationError(
                """
                Index not found at: \(indexPath)
                Run 'swiftindex index' first to create the index.
                """
            )
        }

        // Create embedding provider chain
        let embeddingProvider = createEmbeddingProvider(config: configuration, logger: logger)

        // Check provider availability
        guard await embeddingProvider.isAvailable() else {
            throw ValidationError("No embedding provider available. Check your configuration.")
        }

        // Create index manager and load index
        let indexManager = try IndexManager(
            directory: indexPath,
            dimension: embeddingProvider.dimension
        )
        try await indexManager.load()

        // Verify index has data
        let stats = try await indexManager.statistics()
        guard stats.chunkCount > 0 else {
            throw ValidationError(
                """
                Index is empty. No chunks to search.
                Run 'swiftindex index' first to populate the index.
                """
            )
        }

        if !json {
            print("Searching: \"\(query)\"")
            print("Index: \(stats.chunkCount) chunks from \(stats.fileCount) files")
            print("Limit: \(limit)")
        }

        // Create search engine using stores from index manager
        let chunkStore = await indexManager.chunkStore
        let vectorStore = await indexManager.vectorStore
        let searchEngine = HybridSearchEngine(
            chunkStore: chunkStore,
            vectorStore: vectorStore,
            embeddingProvider: embeddingProvider,
            rrfK: configuration.rrfK
        )

        // Build search options
        var extensionFilter: Set<String>?
        if let extensions {
            extensionFilter = Set(extensions.split(separator: ",").map { String($0).lowercased() })
        }

        let searchOptions = SearchOptions(
            limit: limit,
            semanticWeight: semanticWeight,
            pathFilter: pathFilter,
            extensionFilter: extensionFilter,
            rrfK: configuration.rrfK,
            multiHop: multiHop,
            multiHopDepth: multiHop ? 2 : 0
        )

        // Create LLM components if needed
        var queryExpander: QueryExpander?
        var resultSynthesizer: ResultSynthesizer?
        var followUpGenerator: FollowUpGenerator?
        var expandedQuery: ExpandedQuery?

        if expandQuery || synthesize, configuration.searchEnhancement.enabled {
            // Create utility provider for query expansion and follow-ups
            if expandQuery || synthesize {
                do {
                    let utilityProvider = try LLMProviderFactory.createProvider(
                        from: configuration.searchEnhancement.utility,
                        openAIKey: configuration.openAIAPIKey
                    )
                    if expandQuery {
                        queryExpander = QueryExpander(provider: utilityProvider)
                        logger.debug(
                            "Query expansion enabled with provider: \(configuration.searchEnhancement.utility.provider)"
                        )
                    }
                    if synthesize {
                        followUpGenerator = FollowUpGenerator(provider: utilityProvider)
                    }
                } catch {
                    logger.warning("Failed to create utility LLM provider: \(error)")
                }
            }

            // Create synthesis provider for result summarization
            if synthesize {
                do {
                    let synthesisProvider = try LLMProviderFactory.createProvider(
                        from: configuration.searchEnhancement.synthesis,
                        openAIKey: configuration.openAIAPIKey
                    )
                    resultSynthesizer = ResultSynthesizer(provider: synthesisProvider)
                    logger.debug(
                        "Result synthesis enabled with provider: \(configuration.searchEnhancement.synthesis.provider)"
                    )
                } catch {
                    logger.warning("Failed to create synthesis LLM provider: \(error)")
                }
            }
        } else if expandQuery || synthesize, !configuration.searchEnhancement.enabled {
            logger.warning("LLM features requested but search.enhancement.enabled is false in config")
        }

        // Execute search (with optional expansion)
        let startTime = Date()
        let results: [SearchResult]

        if let expander = queryExpander {
            let enhancedResult = try await searchEngine.searchWithExpansion(
                query: query,
                options: searchOptions,
                expander: expander,
                timeout: configuration.searchEnhancement.utility.timeout
            )
            results = enhancedResult.results
            expandedQuery = enhancedResult.expandedQuery

            if let expanded = expandedQuery {
                logger.info("Query expanded with \(expanded.allTerms.count) terms")
                if !json, format != .json {
                    print("Expanded query: \(expanded.allTerms.joined(separator: ", "))")
                }
            }
        } else {
            results = try await searchEngine.search(query: query, options: searchOptions)
        }

        // Generate synthesis and follow-ups if requested
        var synthesis: Synthesis?
        var followUps: [FollowUpSuggestion]?

        if synthesize, !results.isEmpty {
            // Convert results to synthesis inputs
            let synthesisInputs = results.map { result in
                SynthesisInput(
                    filePath: result.chunk.path,
                    content: result.chunk.content,
                    kind: result.chunk.kind.rawValue,
                    breadcrumb: result.chunk.breadcrumb,
                    docComment: result.chunk.docComment
                )
            }

            // Generate synthesis
            if let synthesizer = resultSynthesizer {
                do {
                    synthesis = try await synthesizer.synthesize(
                        query: query,
                        results: synthesisInputs,
                        timeout: configuration.searchEnhancement.synthesis.timeout
                    )
                    logger.info("Generated synthesis with confidence: \(synthesis?.confidence ?? 0)")
                } catch {
                    logger.warning("Synthesis failed: \(error)")
                }
            }

            // Generate follow-up suggestions
            if let generator = followUpGenerator {
                do {
                    let resultSummary = synthesis?.summary ?? "Found \(results.count) code results"
                    followUps = try await generator.generate(
                        query: query,
                        resultSummary: resultSummary,
                        timeout: configuration.searchEnhancement.utility.timeout
                    )
                    logger.info("Generated \(followUps?.count ?? 0) follow-up suggestions")
                } catch {
                    logger.warning("Follow-up generation failed: \(error)")
                }
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)

        logger.info("Search completed", metadata: [
            "results": "\(results.count)",
            "elapsed": "\(String(format: "%.3f", elapsed))s",
        ])

        // Determine effective format:
        // 1. --json flag takes precedence (backwards compatibility)
        // 2. --format option if explicitly provided
        // 3. Config file default
        let effectiveFormat: OutputFormat = if json {
            .json
        } else if let explicitFormat = format {
            explicitFormat
        } else {
            OutputFormat(rawValue: configuration.outputFormat) ?? .human
        }

        // Output results
        switch effectiveFormat {
        case .human:
            outputHumanReadable(
                results: results,
                elapsed: elapsed,
                synthesis: synthesis,
                followUps: followUps
            )
        case .json:
            try outputJSON(
                results: results,
                query: query,
                elapsed: elapsed,
                expandedQuery: expandedQuery,
                synthesis: synthesis,
                followUps: followUps
            )
        case .toon:
            try outputTOON(
                results: results,
                query: query,
                elapsed: elapsed,
                expandedQuery: expandedQuery,
                synthesis: synthesis,
                followUps: followUps
            )
        }
    }

    // MARK: - Private Helpers

    private func createEmbeddingProvider(
        config: Config,
        logger: Logger
    ) -> EmbeddingProviderChain {
        switch config.embeddingProvider.lowercased() {
        case "mock":
            logger.debug("Using mock embedding provider")
            return EmbeddingProviderChain(
                providers: [MockEmbeddingProvider()],
                id: "mock-chain",
                name: "Mock Embeddings"
            )

        case "mlx":
            logger.debug("Using MLX embedding provider")
            return EmbeddingProviderChain(
                providers: [
                    MLXEmbeddingProvider(
                        huggingFaceId: config.embeddingModel,
                        dimension: config.embeddingDimension
                    ),
                    SwiftEmbeddingsProvider(),
                ],
                id: "mlx-chain",
                name: "MLX with Swift Embeddings fallback"
            )

        case "swift-embeddings", "swift", "swiftembeddings":
            logger.debug("Using Swift Embeddings provider")
            return EmbeddingProviderChain.softwareOnly

        case "ollama":
            logger.debug("Using Ollama embedding provider")
            return EmbeddingProviderChain(
                providers: [
                    OllamaEmbeddingProvider(
                        modelName: config.embeddingModel,
                        dimension: config.embeddingDimension
                    ),
                    SwiftEmbeddingsProvider(),
                ],
                id: "ollama-chain",
                name: "Ollama with fallback"
            )

        case "voyage":
            logger.debug("Using Voyage AI embedding provider")
            if let apiKey = config.voyageAPIKey {
                return EmbeddingProviderChain(
                    providers: [
                        VoyageProvider(
                            apiKey: apiKey,
                            modelName: config.embeddingModel,
                            dimension: config.embeddingDimension
                        ),
                        SwiftEmbeddingsProvider(),
                    ],
                    id: "voyage-chain",
                    name: "Voyage AI with fallback"
                )
            } else {
                logger.warning("VOYAGE_API_KEY not set, falling back to local provider")
                return EmbeddingProviderChain.default
            }

        case "openai":
            logger.debug("Using OpenAI embedding provider")
            if let apiKey = config.openAIAPIKey {
                return EmbeddingProviderChain(
                    providers: [
                        OpenAIProvider(apiKey: apiKey),
                        SwiftEmbeddingsProvider(),
                    ],
                    id: "openai-chain",
                    name: "OpenAI with fallback"
                )
            } else {
                logger.warning("OPENAI_API_KEY not set, falling back to local provider")
                return EmbeddingProviderChain.default
            }

        case "auto":
            logger.debug("Using auto provider selection")
            return EmbeddingProviderChain.default

        default:
            logger.debug("Unknown provider '\(config.embeddingProvider)', using default chain")
            return EmbeddingProviderChain.default
        }
    }

    private func outputJSON(
        results: [SearchResult],
        query: String,
        elapsed: TimeInterval,
        expandedQuery: ExpandedQuery?,
        synthesis: Synthesis? = nil,
        followUps: [FollowUpSuggestion]? = nil
    ) throws {
        var jsonResults: [[String: Any]] = []

        for result in results {
            var item: [String: Any] = [
                "id": result.chunk.id,
                "path": result.chunk.path,
                "startLine": result.chunk.startLine,
                "endLine": result.chunk.endLine,
                "kind": result.chunk.kind.rawValue,
                "symbols": result.chunk.symbols,
                "score": Double(result.score),
                "content": result.chunk.content,
                "tokenCount": result.chunk.tokenCount,
                "language": result.chunk.language,
            ]

            // Rich metadata fields
            if let docComment = result.chunk.docComment {
                item["docComment"] = docComment
            }
            if let signature = result.chunk.signature {
                item["signature"] = signature
            }
            if let breadcrumb = result.chunk.breadcrumb {
                item["breadcrumb"] = breadcrumb
            }

            if let bm25Score = result.bm25Score {
                item["bm25Score"] = Double(bm25Score)
            }
            if let semanticScore = result.semanticScore {
                item["semanticScore"] = Double(semanticScore)
            }
            if let bm25Rank = result.bm25Rank {
                item["bm25Rank"] = bm25Rank
            }
            if let semanticRank = result.semanticRank {
                item["semanticRank"] = semanticRank
            }
            if result.isMultiHop {
                item["isMultiHop"] = true
                item["hopDepth"] = result.hopDepth
            }

            jsonResults.append(item)
        }

        var output: [String: Any] = [
            "query": query,
            "resultCount": results.count,
            "elapsedSeconds": elapsed,
            "results": jsonResults,
        ]

        // Add expanded query info if available
        if let expanded = expandedQuery {
            output["queryExpansion"] = [
                "originalQuery": expanded.originalQuery,
                "synonyms": expanded.synonyms,
                "relatedConcepts": expanded.relatedConcepts,
                "variations": expanded.variations,
                "recallBoost": expanded.recallBoost,
            ]
        }

        // Add synthesis if available
        if let synthesis {
            output["synthesis"] = [
                "summary": synthesis.summary,
                "keyInsights": synthesis.keyInsights,
                "codeReferences": synthesis.codeReferences.map { [
                    "filePath": $0.filePath,
                    "lineNumber": $0.lineNumber as Any,
                    "description": $0.description as Any,
                ] },
                "confidence": Double(synthesis.confidence),
            ]
        }

        // Add follow-up suggestions if available
        if let followUps {
            output["followUpSuggestions"] = followUps.map { [
                "query": $0.query,
                "rationale": $0.rationale as Any,
                "category": $0.category.rawValue,
            ] }
        }

        if let jsonData = try? JSONCodec.serialize(output, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            print(jsonString)
        }
    }

    private func outputHumanReadable(
        results: [SearchResult],
        elapsed: TimeInterval,
        synthesis: Synthesis? = nil,
        followUps: [FollowUpSuggestion]? = nil
    ) {
        print("")

        if results.isEmpty {
            print("No results found.")
            return
        }

        print("Found \(results.count) results in \(String(format: "%.3f", elapsed))s")
        print(String(repeating: "─", count: 60))

        for (index, result) in results.enumerated() {
            let hopIndicator = result.isMultiHop ? " [hop \(result.hopDepth)]" : ""

            print("\n[\(index + 1)] \(result.chunk.path):\(result.chunk.startLine)-\(result.chunk.endLine)")
            print("    Kind: \(result.chunk.kind.rawValue)\(hopIndicator)")

            if !result.chunk.symbols.isEmpty {
                print("    Symbols: \(result.chunk.symbols.joined(separator: ", "))")
            }

            // Show breadcrumb if available
            if let breadcrumb = result.chunk.breadcrumb {
                print("    Location: \(breadcrumb)")
            }

            // Show signature if available
            if let signature = result.chunk.signature {
                print("    Signature: \(signature)")
            }

            // Show relevance percentage as primary metric
            print("    Relevance: \(result.relevancePercent)%", terminator: "")

            // Add keyword rank info if available
            if let bm25Rank = result.bm25Rank {
                print(" (keyword rank #\(bm25Rank))")
            } else {
                print("")
            }

            // Show doc comment if available (truncated)
            if let docComment = result.chunk.docComment {
                let truncated = docComment.prefix(100)
                let suffix = docComment.count > 100 ? "..." : ""
                print("    Doc: \(truncated)\(suffix)")
            }

            // Show code preview (first 5 lines)
            let lines = result.chunk.content.split(separator: "\n", omittingEmptySubsequences: false)
            let preview = lines.prefix(5).joined(separator: "\n")
            print("    ────")
            for line in preview.split(separator: "\n", omittingEmptySubsequences: false) {
                print("    \(line)")
            }
            if lines.count > 5 {
                print("    ... (\(lines.count - 5) more lines)")
            }
        }

        // Show synthesis if available
        if let synthesis {
            print("\n" + String(repeating: "─", count: 60))
            print("Summary:")
            print("  \(synthesis.summary)")

            if !synthesis.keyInsights.isEmpty {
                print("\nKey Insights:")
                for insight in synthesis.keyInsights {
                    print("  • \(insight)")
                }
            }

            if !synthesis.codeReferences.isEmpty {
                print("\nCode References:")
                for ref in synthesis.codeReferences {
                    print("  • \(ref.formatted)")
                }
            }

            print("\nConfidence: \(Int(synthesis.confidence * 100))%")
        }

        // Show follow-up suggestions if available
        if let followUps, !followUps.isEmpty {
            print("\n" + String(repeating: "─", count: 60))
            print("Suggested Follow-ups:")
            for (index, followUp) in followUps.enumerated() {
                var line = "  \(index + 1). \(followUp.query)"
                if let rationale = followUp.rationale {
                    line += " - \(rationale)"
                }
                print(line)
            }
        }

        print("")
    }

    // MARK: - TOON Output

    private func outputTOON(
        results: [SearchResult],
        query: String,
        elapsed: TimeInterval,
        expandedQuery: ExpandedQuery?,
        synthesis: Synthesis? = nil,
        followUps: [FollowUpSuggestion]? = nil
    ) throws {
        // TOON format is a compact, token-efficient representation
        // Format: search{q,n,ms}: followed by tabular results
        let elapsedMs = Int(elapsed * 1000)

        var output = "search{q,n,ms}:\n"
        output += "  \"\(escapeString(query))\",\(results.count),\(elapsedMs)\n"

        // Add query expansion info if available
        if let expanded = expandedQuery {
            output += "\nexpanded{syn,rel,var}:\n"
            let sep = "\",\""
            let syns = expanded.synonyms.isEmpty ? "~" : "[\"\(expanded.synonyms.joined(separator: sep))\"]"
            let rels = expanded.relatedConcepts.isEmpty
                ? "~" : "[\"\(expanded.relatedConcepts.joined(separator: sep))\"]"
            let vars = expanded.variations.isEmpty ? "~" : "[\"\(expanded.variations.joined(separator: sep))\"]"
            output += "  \(syns),\(rels),\(vars)\n"
        }

        output += "\n"

        if results.isEmpty {
            print(output)
            return
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

        output += "\ncode[\(results.count)]:\n"

        for result in results {
            // Truncate content for TOON output (first 10 lines max)
            let lines = result.chunk.content.split(separator: "\n", omittingEmptySubsequences: false)
            let preview = lines.prefix(10).joined(separator: "\n")
            let truncated = lines.count > 10

            output += "  ---\n"
            for line in preview.split(separator: "\n", omittingEmptySubsequences: false) {
                output += "  \(line)\n"
            }
            if truncated {
                output += "  ...\(lines.count - 10) more lines\n"
            }
        }

        // Add synthesis if available
        if let synthesis {
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
        if let followUps, !followUps.isEmpty {
            output += "\nfollow_ups[\(followUps.count)]{q,cat}:\n"
            for followUp in followUps {
                output += "  \"\(escapeString(followUp.query))\",\"\(followUp.category.rawValue)\"\n"
            }
        }

        print(output)
    }

    private func escapeString(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
