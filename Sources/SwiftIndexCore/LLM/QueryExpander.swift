// MARK: - QueryExpander

import Foundation

/// Expands search queries using LLM to improve recall.
///
/// The query expander generates semantically related search terms,
/// alternative phrasings, and concept variations to broaden search coverage.
///
/// ## Usage
///
/// ```swift
/// let expander = QueryExpander(provider: llmProvider)
/// let expanded = try await expander.expand("swift async networking")
/// // Returns: ExpandedQuery with original + related terms
/// ```
public actor QueryExpander {
    // MARK: - Properties

    /// The LLM provider for query expansion.
    private let provider: any LLMProvider

    /// Cache of expanded queries.
    private var cache: [String: ExpandedQuery] = [:]

    /// Maximum cache size.
    private let maxCacheSize: Int

    // MARK: - Initialization

    /// Creates a query expander.
    ///
    /// - Parameters:
    ///   - provider: The LLM provider to use for expansion.
    ///   - maxCacheSize: Maximum number of cached expansions.
    public init(
        provider: any LLMProvider,
        maxCacheSize: Int = 100
    ) {
        self.provider = provider
        self.maxCacheSize = maxCacheSize
    }

    // MARK: - Public Methods

    /// Expands a search query with related terms.
    ///
    /// - Parameters:
    ///   - query: The original search query.
    ///   - timeout: Maximum time to wait for expansion.
    /// - Returns: An expanded query with related terms.
    /// - Throws: `LLMError` if expansion fails.
    public func expand(
        _ query: String,
        timeout: TimeInterval = 30
    ) async throws -> ExpandedQuery {
        // Normalize query for caching
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespaces)

        // Check cache first
        if let cached = cache[normalizedQuery] {
            return cached
        }

        // Generate expansion using LLM
        let messages: [LLMMessage] = [
            .system(SystemPrompts.queryExpansion),
            .user("Search query: \(query)"),
        ]

        let response = try await provider.complete(
            messages: messages,
            model: nil,
            timeout: timeout
        )

        // Parse the LLM response
        let expanded = parseExpansionResponse(response, originalQuery: query)

        // Cache the result (with size limit)
        if cache.count >= maxCacheSize {
            // Remove oldest entry (simple FIFO-ish behavior)
            if let firstKey = cache.keys.first {
                cache.removeValue(forKey: firstKey)
            }
        }
        cache[normalizedQuery] = expanded

        return expanded
    }

    /// Clears the expansion cache.
    public func clearCache() {
        cache.removeAll()
    }

    // MARK: - Private Methods

    private func parseExpansionResponse(
        _ response: String,
        originalQuery: String
    ) -> ExpandedQuery {
        // Parse the structured response
        // Expected format:
        // SYNONYMS: term1, term2, term3
        // RELATED: concept1, concept2
        // VARIATIONS: variation1, variation2

        var synonyms: [String] = []
        var relatedConcepts: [String] = []
        var variations: [String] = []

        let lines = response.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.uppercased().hasPrefix("SYNONYMS:") {
                let terms = extractTerms(from: trimmed, prefix: "SYNONYMS:")
                synonyms.append(contentsOf: terms)
            } else if trimmed.uppercased().hasPrefix("RELATED:") {
                let terms = extractTerms(from: trimmed, prefix: "RELATED:")
                relatedConcepts.append(contentsOf: terms)
            } else if trimmed.uppercased().hasPrefix("VARIATIONS:") {
                let terms = extractTerms(from: trimmed, prefix: "VARIATIONS:")
                variations.append(contentsOf: terms)
            }
        }

        // If parsing failed, try to extract any comma-separated terms
        if synonyms.isEmpty, relatedConcepts.isEmpty, variations.isEmpty {
            let allTerms = response
                .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.count < 100 }

            // Distribute terms across categories
            let chunks = allTerms.chunked(into: 3)
            if !chunks.isEmpty { synonyms = Array(chunks[0].prefix(5)) }
            if chunks.count > 1 { relatedConcepts = Array(chunks[1].prefix(5)) }
            if chunks.count > 2 { variations = Array(chunks[2].prefix(5)) }
        }

        return ExpandedQuery(
            originalQuery: originalQuery,
            synonyms: synonyms,
            relatedConcepts: relatedConcepts,
            variations: variations
        )
    }

    private func extractTerms(from line: String, prefix: String) -> [String] {
        let content = String(line.dropFirst(prefix.count))
        return content
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - ExpandedQuery

/// Result of query expansion.
public struct ExpandedQuery: Sendable, Equatable {
    /// The original search query.
    public let originalQuery: String

    /// Synonyms and equivalent terms.
    public let synonyms: [String]

    /// Related concepts and adjacent topics.
    public let relatedConcepts: [String]

    /// Alternative phrasings and variations.
    public let variations: [String]

    /// All expanded terms combined (for search).
    public var allTerms: [String] {
        [originalQuery] + synonyms + relatedConcepts + variations
    }

    /// Combined query string for search.
    public var combinedQuery: String {
        allTerms.joined(separator: " OR ")
    }

    /// Estimated improvement in recall.
    public var recallBoost: Float {
        let termCount = Float(allTerms.count)
        return min(1.0 + (termCount - 1) * 0.1, 2.0)
    }
}

// MARK: - System Prompts

private enum SystemPrompts {
    static let queryExpansion = """
    You are a search query expansion assistant for a code search engine.
    Given a search query, generate related terms to improve search recall.

    Output format (use exactly these labels):
    SYNONYMS: alternative terms with the same meaning (max 5)
    RELATED: related programming concepts (max 5)
    VARIATIONS: alternative phrasings or spellings (max 3)

    Rules:
    - Focus on programming and software development context
    - Include Swift-specific terminology when relevant
    - Keep terms concise (1-3 words each)
    - Avoid generic terms that would match too many results

    Example for query "async networking":
    SYNONYMS: asynchronous network, concurrent http, async url session
    RELATED: URLSession, async/await, Combine, network layer
    VARIATIONS: async net, network async, async request
    """
}
