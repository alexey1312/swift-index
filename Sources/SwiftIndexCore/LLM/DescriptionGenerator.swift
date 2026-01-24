// MARK: - DescriptionProgressCallback

import Foundation

/// Progress callback for description generation.
///
/// Called after each batch completion to report intermediate progress.
///
/// - Parameters:
///   - completed: Number of chunks with descriptions generated so far.
///   - total: Total number of chunks being processed.
///   - currentFile: Relative path of the file being processed.
public typealias DescriptionProgressCallback = @Sendable (
    _ completed: Int,
    _ total: Int,
    _ currentFile: String
) async -> Void

// MARK: - DescriptionGenerator

/// Generates concise descriptions for code chunks using an LLM.
///
/// The description generator creates human-readable summaries of code chunks
/// that explain their purpose and functionality. These descriptions can be
/// used to enhance search results and improve code understanding.
///
/// ## Usage
///
/// ```swift
/// let generator = DescriptionGenerator(provider: llmProvider)
/// let description = try await generator.generate(for: chunk)
/// // Returns: "Authenticates users via OAuth2 and stores tokens securely"
/// ```
public actor DescriptionGenerator {
    // MARK: - Properties

    /// The LLM provider for description generation.
    private let provider: any LLMProvider

    /// Human-readable provider name (for diagnostics).
    public nonisolated let providerName: String

    /// Provider identifier (for diagnostics).
    public nonisolated let providerId: String

    /// Batch size for parallel processing.
    private let batchSize: Int

    /// Timeout for each generation request.
    private let timeout: TimeInterval

    // MARK: - Initialization

    /// Creates a description generator.
    ///
    /// - Parameters:
    ///   - provider: The LLM provider to use for generation.
    ///   - batchSize: Number of chunks to process in parallel.
    ///   - timeout: Maximum time per generation request (seconds).
    public init(
        provider: any LLMProvider,
        batchSize: Int = 5,
        timeout: TimeInterval = 30
    ) {
        self.provider = provider
        providerName = provider.name
        providerId = provider.id
        self.batchSize = batchSize
        self.timeout = timeout
    }

    // MARK: - Public Methods

    /// Generates a description for a single code chunk.
    ///
    /// - Parameter chunk: The code chunk to describe.
    /// - Returns: A concise description of the chunk's purpose.
    /// - Throws: `LLMError` if generation fails.
    public func generate(for chunk: CodeChunk) async throws -> String {
        let messages: [LLMMessage] = [
            .system(SystemPrompts.descriptionGeneration),
            .user(formatChunkForPrompt(chunk)),
        ]

        let response = try await provider.complete(
            messages: messages,
            model: nil,
            timeout: timeout
        )

        return parseDescriptionResponse(response)
    }

    /// Generates descriptions for multiple chunks in batches.
    ///
    /// Processes chunks in parallel batches for efficiency.
    /// Chunks that fail generation will be counted as failures.
    ///
    /// - Parameters:
    ///   - chunks: The code chunks to describe.
    ///   - file: Relative path of the file being processed (for progress reporting).
    ///   - onProgress: Optional callback invoked after each batch completion.
    /// - Returns: Result containing descriptions and failure details.
    public func generateBatch(
        for chunks: [CodeChunk],
        file: String = "",
        onProgress: DescriptionProgressCallback? = nil
    ) async -> DescriptionBatchResult {
        var results: [String: String] = [:]
        var failures = 0
        var firstError: String?

        // Process in batches
        for batchStart in stride(from: 0, to: chunks.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, chunks.count)
            let batch = Array(chunks[batchStart ..< batchEnd])

            // Process batch in parallel
            let batchResults = await withTaskGroup(
                of: (String, String?, String?).self,
                returning: [(String, String?, String?)].self
            ) { group in
                for chunk in batch {
                    group.addTask {
                        do {
                            let description = try await self.generate(for: chunk)
                            return (chunk.id, description, nil)
                        } catch {
                            // Skip chunks that fail - don't halt the batch
                            return (chunk.id, nil, error.localizedDescription)
                        }
                    }
                }

                var collected: [(String, String?, String?)] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            // Collect results from batch
            for (chunkId, description, error) in batchResults {
                if let description {
                    results[chunkId] = description
                } else {
                    failures += 1
                    if firstError == nil, let error {
                        firstError = error
                    }
                }
            }

            // Report progress after each batch
            await onProgress?(results.count, chunks.count, file)
        }

        return DescriptionBatchResult(
            descriptions: results,
            failures: failures,
            firstError: firstError
        )
    }

    /// Checks if description generation is available.
    ///
    /// - Returns: `true` if the provider is available.
    public func isAvailable() async -> Bool {
        await provider.isAvailable()
    }

    // MARK: - Private Methods

    private func formatChunkForPrompt(_ chunk: CodeChunk) -> String {
        var prompt = """
        Language: \(chunk.language)
        Kind: \(chunk.kind.rawValue)
        """

        if let signature = chunk.signature {
            prompt += "\nSignature: \(signature)"
        }

        if let breadcrumb = chunk.breadcrumb {
            prompt += "\nLocation: \(breadcrumb)"
        }

        if let docComment = chunk.docComment, !docComment.isEmpty {
            prompt += "\nDocumentation:\n\(docComment)"
        }

        prompt += "\n\nCode:\n\(chunk.content)"

        return prompt
    }

    private func parseDescriptionResponse(_ response: String) -> String {
        // Clean up the response
        var description = response
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove common LLM prefixes
        let prefixesToRemove = [
            "This code ",
            "This function ",
            "This method ",
            "This class ",
            "This struct ",
            "This enum ",
            "This protocol ",
            "Description: ",
            "Summary: ",
        ]

        for prefix in prefixesToRemove {
            if description.hasPrefix(prefix) {
                description = String(description.dropFirst(prefix.count))
                break
            }
        }

        // Capitalize first letter
        if let first = description.first {
            description = first.uppercased() + description.dropFirst()
        }

        // Ensure it ends with a period
        if !description.hasSuffix("."), !description.hasSuffix("!"), !description.hasSuffix("?") {
            description += "."
        }

        // Truncate if too long (max ~200 chars)
        if description.count > 250 {
            // Find a good break point
            if let lastSentence = description.prefix(250).lastIndex(of: ".") {
                description = String(description[...lastSentence])
            } else if let lastSpace = description.prefix(250).lastIndex(of: " ") {
                description = String(description[..<lastSpace]) + "..."
            }
        }

        return description
    }
}

// MARK: - DescriptionBatchResult

public struct DescriptionBatchResult: Sendable {
    public let descriptions: [String: String]
    public let failures: Int
    public let firstError: String?
}

// MARK: - System Prompts

private enum SystemPrompts {
    static let descriptionGeneration = """
    You are a code documentation assistant. Generate a concise, one-sentence description
    of the given code's purpose and functionality.

    Rules:
    - Use clear, technical language appropriate for developers
    - Focus on WHAT the code does and WHY, not HOW
    - Keep descriptions under 150 characters when possible
    - Use active voice (e.g., "Validates user credentials" not "User credentials are validated")
    - Don't repeat the function/class name in the description
    - Include key behaviors like error handling, caching, or async operations if relevant

    Examples:
    - "Authenticates users via OAuth2 and stores refresh tokens securely."
    - "Parses JSON responses into strongly-typed models with error recovery."
    - "Manages concurrent database connections with automatic retry logic."

    Respond with ONLY the description, no additional text or formatting.
    """
}
