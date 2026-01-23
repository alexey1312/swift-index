// MARK: - ResultSynthesizer

import Foundation

/// Synthesizes search results into a coherent summary using LLM.
///
/// The synthesizer analyzes multiple search results and produces
/// a unified summary that answers the user's query.
///
/// ## Usage
///
/// ```swift
/// let synthesizer = ResultSynthesizer(provider: llmProvider)
/// let summary = try await synthesizer.synthesize(
///     query: "how does authentication work",
///     results: searchResults
/// )
/// ```
public actor ResultSynthesizer {
    // MARK: - Properties

    /// The LLM provider for synthesis.
    private let provider: any LLMProvider

    /// Maximum number of results to include in synthesis.
    private let maxResults: Int

    /// Maximum tokens to include from each result.
    private let maxTokensPerResult: Int

    // MARK: - Initialization

    /// Creates a result synthesizer.
    ///
    /// - Parameters:
    ///   - provider: The LLM provider to use for synthesis.
    ///   - maxResults: Maximum results to synthesize.
    ///   - maxTokensPerResult: Maximum tokens per result.
    public init(
        provider: any LLMProvider,
        maxResults: Int = 10,
        maxTokensPerResult: Int = 500
    ) {
        self.provider = provider
        self.maxResults = maxResults
        self.maxTokensPerResult = maxTokensPerResult
    }

    // MARK: - Public Methods

    /// Synthesizes search results into a summary.
    ///
    /// - Parameters:
    ///   - query: The original search query.
    ///   - results: Search results to synthesize.
    ///   - timeout: Maximum time for synthesis.
    /// - Returns: A synthesis containing the summary and insights.
    /// - Throws: `LLMError` if synthesis fails.
    public func synthesize(
        query: String,
        results: [SynthesisInput],
        timeout: TimeInterval = 120
    ) async throws -> Synthesis {
        guard !results.isEmpty else {
            return Synthesis(
                summary: "No results found for the query.",
                keyInsights: [],
                codeReferences: [],
                confidence: 0.0
            )
        }

        // Prepare context from results
        let context = prepareContext(results: Array(results.prefix(maxResults)))

        // Generate synthesis using LLM
        let messages: [LLMMessage] = [
            .system(SystemPrompts.resultSynthesis),
            .user("""
            Query: \(query)

            Search Results:
            \(context)
            """),
        ]

        let response = try await provider.complete(
            messages: messages,
            model: nil,
            timeout: timeout
        )

        // Parse the response
        return parseSynthesisResponse(response, resultCount: results.count)
    }

    // MARK: - Private Methods

    private func prepareContext(results: [SynthesisInput]) -> String {
        results.enumerated().map { index, result in
            let truncatedContent = truncateToTokens(
                result.content,
                maxTokens: maxTokensPerResult
            )

            return """
            --- Result \(index + 1) ---
            File: \(result.filePath)
            Type: \(result.kind)
            \(result.breadcrumb.map { "Location: \($0)" } ?? "")
            \(result.docComment.map { "Documentation: \($0)" } ?? "")

            Code:
            \(truncatedContent)
            """
        }.joined(separator: "\n\n")
    }

    private func truncateToTokens(_ text: String, maxTokens: Int) -> String {
        let estimatedChars = maxTokens * 4
        if text.count <= estimatedChars {
            return text
        }
        return String(text.prefix(estimatedChars)) + "..."
    }

    private func parseSynthesisResponse(
        _ response: String,
        resultCount: Int
    ) -> Synthesis {
        // Parse the structured response
        var summary = ""
        var keyInsights: [String] = []
        var codeReferences: [CodeReference] = []
        var confidence: Float = 0.7 // Default confidence

        let lines = response.components(separatedBy: .newlines)
        var currentSection = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.uppercased().hasPrefix("SUMMARY:") {
                currentSection = "summary"
                let content = String(trimmed.dropFirst("SUMMARY:".count))
                    .trimmingCharacters(in: .whitespaces)
                if !content.isEmpty {
                    summary = content
                }
            } else if trimmed.uppercased().hasPrefix("INSIGHTS:") {
                currentSection = "insights"
            } else if trimmed.uppercased().hasPrefix("REFERENCES:") {
                currentSection = "references"
            } else if trimmed.uppercased().hasPrefix("CONFIDENCE:") {
                let value = String(trimmed.dropFirst("CONFIDENCE:".count))
                    .trimmingCharacters(in: .whitespaces)
                if let parsed = Float(value.replacingOccurrences(of: "%", with: "")) {
                    confidence = parsed / 100.0
                }
            } else if !trimmed.isEmpty {
                switch currentSection {
                case "summary":
                    summary += (summary.isEmpty ? "" : " ") + trimmed
                case "insights":
                    if trimmed.hasPrefix("-") || trimmed.hasPrefix("•") {
                        let insight = String(trimmed.dropFirst())
                            .trimmingCharacters(in: .whitespaces)
                        if !insight.isEmpty {
                            keyInsights.append(insight)
                        }
                    }
                case "references":
                    if let reference = parseCodeReference(trimmed) {
                        codeReferences.append(reference)
                    }
                default:
                    // If no section detected, treat as summary
                    if summary.isEmpty {
                        summary = trimmed
                    }
                }
            }
        }

        // If structured parsing failed, use the whole response as summary
        if summary.isEmpty {
            summary = response.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return Synthesis(
            summary: summary,
            keyInsights: keyInsights,
            codeReferences: codeReferences,
            confidence: min(max(confidence, 0.0), 1.0)
        )
    }

    private func parseCodeReference(_ line: String) -> CodeReference? {
        // Expected format: "- file.swift:123 - description"
        let trimmed = line.hasPrefix("-") || line.hasPrefix("•")
            ? String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            : line

        let parts = trimmed.components(separatedBy: " - ")
        guard parts.count >= 1 else { return nil }

        let locationPart = parts[0]
        let description = parts.count > 1 ? parts[1] : nil

        // Parse file:line format
        let locationParts = locationPart.components(separatedBy: ":")
        let filePath = locationParts[0]
        let lineNumber = locationParts.count > 1 ? Int(locationParts[1]) : nil

        guard !filePath.isEmpty else { return nil }

        return CodeReference(
            filePath: filePath,
            lineNumber: lineNumber,
            description: description
        )
    }
}

// MARK: - SynthesisInput

/// Input for result synthesis.
public struct SynthesisInput: Sendable {
    public let filePath: String
    public let content: String
    public let kind: String
    public let breadcrumb: String?
    public let docComment: String?

    public init(
        filePath: String,
        content: String,
        kind: String,
        breadcrumb: String? = nil,
        docComment: String? = nil
    ) {
        self.filePath = filePath
        self.content = content
        self.kind = kind
        self.breadcrumb = breadcrumb
        self.docComment = docComment
    }
}

// MARK: - Synthesis

/// Result of synthesis operation.
public struct Synthesis: Sendable, Equatable {
    /// High-level summary answering the query.
    public let summary: String

    /// Key insights from the search results.
    public let keyInsights: [String]

    /// References to relevant code locations.
    public let codeReferences: [CodeReference]

    /// Confidence score (0.0 to 1.0).
    public let confidence: Float
}

// MARK: - CodeReference

/// Reference to a code location.
public struct CodeReference: Sendable, Equatable {
    public let filePath: String
    public let lineNumber: Int?
    public let description: String?

    /// Formatted reference string.
    public var formatted: String {
        var result = filePath
        if let line = lineNumber {
            result += ":\(line)"
        }
        if let desc = description {
            result += " - \(desc)"
        }
        return result
    }
}

// MARK: - System Prompts

private enum SystemPrompts {
    static let resultSynthesis = """
    You are a code search result synthesizer. Analyze the search results and provide a coherent summary.

    Output format (use exactly these labels):
    SUMMARY: A clear, concise answer to the query based on the code found (2-4 sentences)

    INSIGHTS:
    - Key insight 1
    - Key insight 2
    - Key insight 3 (max 5 insights)

    REFERENCES:
    - file.swift:123 - brief description
    - other-file.swift:45 - brief description

    CONFIDENCE: 85%

    Rules:
    - Focus on answering the user's query directly
    - Reference specific files and line numbers when relevant
    - Highlight important patterns, APIs, or implementation details
    - Be concise but informative
    - Set confidence based on how well the results answer the query
    """
}
