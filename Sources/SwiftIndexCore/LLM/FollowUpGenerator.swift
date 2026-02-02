// MARK: - FollowUpGenerator

import Foundation

/// Generates suggested follow-up queries based on search results.
///
/// The generator analyzes the current query and results to suggest
/// related queries that might help the user explore further.
///
/// ## Usage
///
/// ```swift
/// let generator = FollowUpGenerator(provider: llmProvider)
/// let suggestions = try await generator.generate(
///     query: "swift async networking",
///     resultSummary: "Found URLSession async methods..."
/// )
/// ```
public actor FollowUpGenerator {
    // MARK: - Properties

    /// The LLM provider for generation.
    private let provider: any LLMProvider

    /// Cache of generated follow-ups.
    private var cache: [String: [FollowUpSuggestion]] = [:]

    /// Access order for LRU eviction (most recently used at the end).
    private var accessOrder: [String] = []

    /// Maximum cache size.
    private let maxCacheSize: Int

    // MARK: - Initialization

    /// Creates a follow-up generator.
    ///
    /// - Parameters:
    ///   - provider: The LLM provider to use.
    ///   - maxCacheSize: Maximum cached suggestions.
    public init(
        provider: any LLMProvider,
        maxCacheSize: Int = 50
    ) {
        self.provider = provider
        self.maxCacheSize = maxCacheSize
    }

    // MARK: - Public Methods

    /// Generates follow-up query suggestions.
    ///
    /// - Parameters:
    ///   - query: The original search query.
    ///   - resultSummary: Brief summary of what was found.
    ///   - timeout: Maximum time for generation.
    /// - Returns: Array of follow-up suggestions.
    /// - Throws: `LLMError` if generation fails.
    public func generate(
        query: String,
        resultSummary: String,
        timeout: TimeInterval = 30
    ) async throws -> [FollowUpSuggestion] {
        // Create cache key
        let cacheKey = "\(query.lowercased())|\(resultSummary.prefix(100))"

        // Check cache
        if let cached = cache[cacheKey] {
            // Move to end of access order (mark as recently used)
            if let index = accessOrder.firstIndex(of: cacheKey) {
                accessOrder.remove(at: index)
            }
            accessOrder.append(cacheKey)
            return cached
        }

        // Generate suggestions using LLM
        let messages: [LLMMessage] = [
            .system(SystemPrompts.followUpGeneration),
            .user("""
            Original query: \(query)

            Results summary: \(resultSummary)

            Generate 3-5 follow-up query suggestions.
            """),
        ]

        let response = try await provider.complete(
            messages: messages,
            model: nil,
            timeout: timeout
        )

        // Parse the response
        let suggestions = parseFollowUpResponse(response)

        // Cache results with LRU eviction
        if cache.count >= maxCacheSize, !accessOrder.isEmpty {
            let lruKey = accessOrder.removeFirst()
            cache.removeValue(forKey: lruKey)
        }
        cache[cacheKey] = suggestions
        accessOrder.append(cacheKey)

        return suggestions
    }

    /// Clears the suggestion cache.
    public func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    // MARK: - Private Methods

    private func parseFollowUpResponse(
        _ response: String
    ) -> [FollowUpSuggestion] {
        var suggestions: [FollowUpSuggestion] = []

        let lines = response.components(separatedBy: .newlines)

        for line in lines {
            var trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and labels
            guard !trimmed.isEmpty else { continue }
            guard !trimmed.uppercased().hasPrefix("SUGGESTIONS:") else { continue }

            // Remove list markers
            if trimmed.hasPrefix("-") || trimmed.hasPrefix("•") ||
                trimmed.hasPrefix("*")
            {
                trimmed = String(trimmed.dropFirst())
                    .trimmingCharacters(in: .whitespaces)
            }

            // Remove numbered list markers (e.g., "1.", "2)")
            if let match = trimmed.range(
                of: #"^\d+[\.\)]\s*"#,
                options: .regularExpression
            ) {
                trimmed = String(trimmed[match.upperBound...])
            }

            guard !trimmed.isEmpty else { continue }

            // Parse query and rationale
            // Expected format: "query text" - rationale
            // or: query text | rationale
            // or: just query text
            let (query, rationale) = parseQueryAndRationale(trimmed)

            // Categorize the suggestion
            let category = categorize(query: query)

            suggestions.append(FollowUpSuggestion(
                query: query,
                rationale: rationale,
                category: category
            ))
        }

        // Limit to reasonable number
        return Array(suggestions.prefix(5))
    }

    private func parseQueryAndRationale(
        _ text: String
    ) -> (query: String, rationale: String?) {
        // Try different separators
        let separators = [" - ", " | ", ": "]

        for separator in separators {
            if let range = text.range(of: separator) {
                let query = String(text[..<range.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                let rationale = String(text[range.upperBound...])
                    .trimmingCharacters(in: .whitespaces)

                if !query.isEmpty {
                    return (query, rationale.isEmpty ? nil : rationale)
                }
            }
        }

        // No separator found, whole thing is the query
        let query = text
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return (query, nil)
    }

    // MARK: - Regex Patterns

    // Pre-compiled regex patterns for categorization (case-insensitive)
    private static let howToRegex: NSRegularExpression = // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "how|usage|example", options: .caseInsensitive)

    private static let deeperUnderstandingRegex: NSRegularExpression = // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "why|reason", options: .caseInsensitive)

    private static let testingRegex: NSRegularExpression = // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "test|spec", options: .caseInsensitive)

    private static let relatedCodeRegex: NSRegularExpression = // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "similar|related|like", options: .caseInsensitive)

    private static let configurationRegex: NSRegularExpression = // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "config|setup|init", options: .caseInsensitive)

    private func categorize(query: String) -> FollowUpCategory {
        // Use regex matching to avoid multiple string traversals and lowercasing allocations
        let range = NSRange(query.startIndex ..< query.endIndex, in: query)

        if Self.howToRegex.firstMatch(in: query, options: [], range: range) != nil {
            return .howTo
        } else if Self.deeperUnderstandingRegex.firstMatch(in: query, options: [], range: range) != nil {
            return .deeperUnderstanding
        } else if Self.testingRegex.firstMatch(in: query, options: [], range: range) != nil {
            return .testing
        } else if Self.relatedCodeRegex.firstMatch(in: query, options: [], range: range) != nil {
            return .relatedCode
        } else if Self.configurationRegex.firstMatch(in: query, options: [], range: range) != nil {
            return .configuration
        }

        return .exploration
    }
}

// MARK: - FollowUpSuggestion

/// A suggested follow-up query.
public struct FollowUpSuggestion: Sendable, Equatable {
    /// The suggested query text.
    public let query: String

    /// Brief explanation of why this might be useful.
    public let rationale: String?

    /// Category of the suggestion.
    public let category: FollowUpCategory
}

// MARK: - FollowUpCategory

/// Category of follow-up suggestion.
public enum FollowUpCategory: String, Sendable, CaseIterable {
    case deeperUnderstanding = "deeper_understanding"
    case relatedCode = "related_code"
    case howTo = "how_to"
    case testing
    case configuration
    case exploration
}

// MARK: - System Prompts

private enum SystemPrompts {
    static let followUpGeneration = """
    You are a code search assistant. Based on the user's query and what was found, suggest follow-up queries.

    Output format (one suggestion per line):
    - "query text" - brief rationale

    Suggestion categories to consider:
    1. Deeper understanding: Why something works a certain way
    2. Related code: Similar implementations or patterns
    3. How-to: Usage examples or implementation guides
    4. Testing: Test files or test patterns
    5. Configuration: Setup or initialization code

    Rules:
    - Keep queries concise (2-5 words typically)
    - Focus on what would naturally follow from the current results
    - Suggest queries that explore different aspects
    - Be specific to the codebase context
    """
}
