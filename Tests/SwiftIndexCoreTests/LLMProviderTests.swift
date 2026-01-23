// MARK: - LLM Provider Tests

import Foundation
@testable import SwiftIndexCore
import Testing

// MARK: - LLMMessage Tests

@Suite("LLMMessage")
struct LLMMessageTests {
    @Test("Create system message")
    func systemMessage() {
        let message = LLMMessage.system("You are helpful")
        #expect(message.role == .system)
        #expect(message.content == "You are helpful")
    }

    @Test("Create user message")
    func userMessage() {
        let message = LLMMessage.user("Hello")
        #expect(message.role == .user)
        #expect(message.content == "Hello")
    }

    @Test("Create assistant message")
    func assistantMessage() {
        let message = LLMMessage.assistant("Hi there")
        #expect(message.role == .assistant)
        #expect(message.content == "Hi there")
    }

    @Test("Message array token estimation")
    func tokenEstimation() {
        let messages: [LLMMessage] = [
            .system("Instructions"), // 12 chars
            .user("Question"), // 8 chars
        ]
        // Total: 20 chars / 4 = 5 tokens
        #expect(messages.estimatedTokenCount == 5)
    }

    @Test("Conversation helper")
    func conversationHelper() {
        let messages: [LLMMessage] = .conversation(
            system: "Be helpful",
            user: "Hello"
        )
        #expect(messages.count == 2)
        #expect(messages[0].role == .system)
        #expect(messages[1].role == .user)
    }

    @Test("Message codable")
    func codable() throws {
        let original = LLMMessage.user("Test content")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LLMMessage.self, from: encoded)
        #expect(decoded == original)
    }
}

// MARK: - LLMError Tests

@Suite("LLMError")
struct LLMErrorTests {
    @Test("Error descriptions")
    func errorDescriptions() {
        let errors: [LLMError] = [
            .notAvailable(reason: "test"),
            .cliNotFound(tool: "claude"),
            .apiKeyMissing(provider: "openai"),
            .timeout(seconds: 30),
            .rateLimited(retryAfter: 60),
            .modelNotFound(name: "gpt-5"),
        ]

        for error in errors {
            // All errors should have descriptions
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("Timeout error includes seconds")
    func timeoutError() {
        let error = LLMError.timeout(seconds: 45)
        #expect(error.errorDescription?.contains("45") == true)
    }
}

// MARK: - LLMProviderChain Tests

@Suite("LLMProviderChain")
struct LLMProviderChainTests {
    @Test("Empty chain returns no providers")
    func emptyChain() async {
        let chain = LLMProviderChain(providers: [])
        #expect(chain.allProviders.isEmpty)
        #expect(await chain.isAvailable() == false)
    }

    @Test("Chain with single provider")
    func singleProvider() async {
        let mockProvider = MockLLMProvider(available: true)
        let chain = LLMProviderChain.single(mockProvider)

        #expect(chain.allProviders.count == 1)
        #expect(await chain.isAvailable() == true)
    }

    @Test("Chain with unavailable provider")
    func unavailableProvider() async {
        let mockProvider = MockLLMProvider(available: false)
        let chain = LLMProviderChain.single(mockProvider)

        #expect(await chain.isAvailable() == false)
    }

    @Test("Chain builder pattern")
    func testBuilder() {
        let chain = LLMProviderChain.build { builder in
            builder
                .add(MockLLMProvider(id: "mock1", available: true))
                .add(MockLLMProvider(id: "mock2", available: true))
                .id("test-chain")
                .name("Test Chain")
        }

        #expect(chain.id == "test-chain")
        #expect(chain.name == "Test Chain")
        #expect(chain.allProviders.count == 2)
    }

    @Test("Chain uses first available provider")
    func firstAvailable() async throws {
        let unavailable = MockLLMProvider(id: "unavailable", available: false)
        let available = MockLLMProvider(id: "available", available: true, response: "Hello")

        let chain = LLMProviderChain(providers: [unavailable, available])

        let result = try await chain.complete(messages: [.user("Hi")])
        #expect(result == "Hello")
    }

    @Test("Chain throws when all fail")
    func allFail() async {
        let provider1 = MockLLMProvider(id: "p1", available: false)
        let provider2 = MockLLMProvider(id: "p2", available: false)

        let chain = LLMProviderChain(providers: [provider1, provider2])

        await #expect(throws: LLMError.self) {
            _ = try await chain.complete(messages: [.user("Hi")])
        }
    }
}

// MARK: - ExpandedQuery Tests

@Suite("ExpandedQuery")
struct ExpandedQueryTests {
    @Test("All terms combines original and expanded")
    func testAllTerms() {
        let expanded = ExpandedQuery(
            originalQuery: "swift async",
            synonyms: ["asynchronous", "concurrent"],
            relatedConcepts: ["Task", "await"],
            variations: ["async swift"]
        )

        #expect(expanded.allTerms.count == 6)
        #expect(expanded.allTerms.contains("swift async"))
        #expect(expanded.allTerms.contains("asynchronous"))
        #expect(expanded.allTerms.contains("Task"))
    }

    @Test("Combined query uses OR")
    func testCombinedQuery() {
        let expanded = ExpandedQuery(
            originalQuery: "test",
            synonyms: ["check"],
            relatedConcepts: [],
            variations: []
        )

        #expect(expanded.combinedQuery == "test OR check")
    }

    @Test("Recall boost calculation")
    func testRecallBoost() {
        let noExpansion = ExpandedQuery(
            originalQuery: "test",
            synonyms: [],
            relatedConcepts: [],
            variations: []
        )
        #expect(noExpansion.recallBoost == 1.0)

        let withExpansion = ExpandedQuery(
            originalQuery: "test",
            synonyms: ["a", "b", "c", "d", "e"],
            relatedConcepts: ["x", "y", "z"],
            variations: ["v1"]
        )
        // 10 terms total, boost capped at 2.0
        #expect(withExpansion.recallBoost == 2.0)
    }
}

// MARK: - LLMProviderFactory Tests

@Suite("LLMProviderFactory")
struct LLMProviderFactoryTests {
    @Test("Create provider from tier config - Claude Code CLI")
    func claudeCodeCLI() throws {
        let config = LLMTierConfig(provider: "claude-code-cli")
        let provider = try LLMProviderFactory.createProvider(from: config)
        #expect(provider.id == "claude-code-cli")
    }

    @Test("Create provider from tier config - Codex CLI")
    func codexCLI() throws {
        let config = LLMTierConfig(provider: "codex-cli")
        let provider = try LLMProviderFactory.createProvider(from: config)
        #expect(provider.id == "codex-cli")
    }

    @Test("Create provider from tier config - Ollama")
    func ollama() throws {
        let config = LLMTierConfig(provider: "ollama")
        let provider = try LLMProviderFactory.createProvider(from: config)
        #expect(provider.id == "ollama")
    }

    @Test("Create provider from tier config - OpenAI")
    func openAI() throws {
        let config = LLMTierConfig(provider: "openai")
        let provider = try LLMProviderFactory.createProvider(from: config, openAIKey: "test-key")
        #expect(provider.id == "openai")
    }

    @Test("Unknown provider throws error")
    func unknownProvider() {
        let config = LLMTierConfig(provider: "unknown-provider")
        #expect(throws: LLMError.self) {
            _ = try LLMProviderFactory.createProvider(from: config)
        }
    }
}

// MARK: - SearchEnhancementConfig Tests

@Suite("SearchEnhancementConfig")
struct SearchEnhancementConfigTests {
    @Test("Default config is disabled")
    func defaultDisabled() {
        let config = SearchEnhancementConfig.default
        #expect(config.enabled == false)
    }

    @Test("Default utility tier uses claude-code-cli")
    func defaultUtilityProvider() {
        let config = SearchEnhancementConfig.default
        #expect(config.utility.provider == "claude-code-cli")
        #expect(config.utility.timeout == 30)
    }

    @Test("Default synthesis tier uses claude-code-cli")
    func defaultSynthesisProvider() {
        let config = SearchEnhancementConfig.default
        #expect(config.synthesis.provider == "claude-code-cli")
        #expect(config.synthesis.timeout == 120)
    }
}

// MARK: - SynthesisInput Tests

@Suite("SynthesisInput")
struct SynthesisInputTests {
    @Test("Create synthesis input")
    func createInput() {
        let input = SynthesisInput(
            filePath: "test.swift",
            content: "func test() { }",
            kind: "function",
            breadcrumb: "TestClass > test()",
            docComment: "Test function"
        )

        #expect(input.filePath == "test.swift")
        #expect(input.content == "func test() { }")
        #expect(input.kind == "function")
        #expect(input.breadcrumb == "TestClass > test()")
        #expect(input.docComment == "Test function")
    }

    @Test("Create input without optional fields")
    func createInputMinimal() {
        let input = SynthesisInput(
            filePath: "test.swift",
            content: "let x = 1",
            kind: "variable"
        )

        #expect(input.filePath == "test.swift")
        #expect(input.breadcrumb == nil)
        #expect(input.docComment == nil)
    }
}

// MARK: - Synthesis Tests

@Suite("Synthesis")
struct SynthesisTests {
    @Test("Synthesis equality")
    func equality() {
        let s1 = Synthesis(
            summary: "Test summary",
            keyInsights: ["Insight 1"],
            codeReferences: [],
            confidence: 0.8
        )
        let s2 = Synthesis(
            summary: "Test summary",
            keyInsights: ["Insight 1"],
            codeReferences: [],
            confidence: 0.8
        )

        #expect(s1 == s2)
    }

    @Test("Code reference formatting")
    func codeReferenceFormatting() {
        let ref1 = CodeReference(
            filePath: "test.swift",
            lineNumber: 42,
            description: "Main function"
        )
        #expect(ref1.formatted == "test.swift:42 - Main function")

        let ref2 = CodeReference(
            filePath: "test.swift",
            lineNumber: nil,
            description: nil
        )
        #expect(ref2.formatted == "test.swift")

        let ref3 = CodeReference(
            filePath: "test.swift",
            lineNumber: 10,
            description: nil
        )
        #expect(ref3.formatted == "test.swift:10")
    }
}

// MARK: - FollowUpSuggestion Tests

@Suite("FollowUpSuggestion")
struct FollowUpSuggestionTests {
    @Test("Create suggestion")
    func createSuggestion() {
        let suggestion = FollowUpSuggestion(
            query: "how to test async code",
            rationale: "Related testing pattern",
            category: .testing
        )

        #expect(suggestion.query == "how to test async code")
        #expect(suggestion.rationale == "Related testing pattern")
        #expect(suggestion.category == .testing)
    }

    @Test("All categories have raw values")
    func categoryRawValues() {
        for category in FollowUpCategory.allCases {
            #expect(!category.rawValue.isEmpty)
        }
    }
}

// MARK: - ResultSynthesizer Tests

@Suite("ResultSynthesizer")
struct ResultSynthesizerTests {
    @Test("Synthesize empty results")
    func synthesizeEmpty() async throws {
        let provider = MockLLMProvider(response: "Test response")
        let synthesizer = ResultSynthesizer(provider: provider)

        let result = try await synthesizer.synthesize(
            query: "test query",
            results: [],
            timeout: 5
        )

        #expect(result.summary.contains("No results"))
        #expect(result.keyInsights.isEmpty)
        #expect(result.confidence == 0.0)
    }

    @Test("Synthesize with structured response")
    func synthesizeStructured() async throws {
        let structuredResponse = """
        SUMMARY: This is a test summary about the code.

        INSIGHTS:
        - First insight about the implementation
        - Second insight about patterns used

        REFERENCES:
        - test.swift:42 - main function
        - helper.swift:10 - utility

        CONFIDENCE: 85%
        """

        let provider = MockLLMProvider(response: structuredResponse)
        let synthesizer = ResultSynthesizer(provider: provider)

        let inputs = [
            SynthesisInput(
                filePath: "test.swift",
                content: "func test() {}",
                kind: "function"
            ),
        ]

        let result = try await synthesizer.synthesize(
            query: "test query",
            results: inputs,
            timeout: 5
        )

        #expect(result.summary.contains("test summary"))
        #expect(result.keyInsights.count == 2)
        #expect(result.codeReferences.count == 2)
        #expect(result.confidence >= 0.8 && result.confidence <= 0.9)
    }

    @Test("Synthesize with unstructured response")
    func synthesizeUnstructured() async throws {
        let unstructuredResponse = "This is just a plain text response without structure."

        let provider = MockLLMProvider(response: unstructuredResponse)
        let synthesizer = ResultSynthesizer(provider: provider)

        let inputs = [
            SynthesisInput(
                filePath: "test.swift",
                content: "func test() {}",
                kind: "function"
            ),
        ]

        let result = try await synthesizer.synthesize(
            query: "test query",
            results: inputs,
            timeout: 5
        )

        // Unstructured response should be used as summary
        #expect(result.summary.contains("plain text response"))
    }
}

// MARK: - FollowUpGenerator Tests

@Suite("FollowUpGenerator")
struct FollowUpGeneratorTests {
    @Test("Generate follow-ups")
    func generateFollowUps() async throws {
        let response = """
        1. how to test async functions - related testing pattern
        2. error handling patterns - understand error flow
        3. similar implementations
        """

        let provider = MockLLMProvider(response: response)
        let generator = FollowUpGenerator(provider: provider)

        let suggestions = try await generator.generate(
            query: "async networking",
            resultSummary: "Found URLSession async methods",
            timeout: 5
        )

        #expect(suggestions.count >= 2)
        #expect(suggestions[0].query.contains("test") || suggestions[0].query.contains("how"))
    }

    @Test("Generator caches results")
    func caching() async throws {
        var callCount = 0

        let provider = CountingMockProvider { callCount += 1 }
        let generator = FollowUpGenerator(provider: provider)

        // First call
        _ = try await generator.generate(
            query: "test query",
            resultSummary: "test summary",
            timeout: 5
        )

        // Second call with same query - should use cache
        _ = try await generator.generate(
            query: "test query",
            resultSummary: "test summary",
            timeout: 5
        )

        #expect(callCount == 1) // Only one actual LLM call
    }

    @Test("Clear cache")
    func testClearCache() async throws {
        var callCount = 0

        let provider = CountingMockProvider { callCount += 1 }
        let generator = FollowUpGenerator(provider: provider)

        _ = try await generator.generate(
            query: "test query",
            resultSummary: "test summary",
            timeout: 5
        )

        await generator.clearCache()

        _ = try await generator.generate(
            query: "test query",
            resultSummary: "test summary",
            timeout: 5
        )

        #expect(callCount == 2) // Two calls after cache cleared
    }
}

// MARK: - Mock LLM Provider

/// Mock LLM provider for testing.
private struct MockLLMProvider: LLMProvider {
    let id: String
    let name: String
    let available: Bool
    let response: String

    init(
        id: String = "mock",
        available: Bool = true,
        response: String = "Mock response"
    ) {
        self.id = id
        name = "Mock LLM Provider"
        self.available = available
        self.response = response
    }

    func isAvailable() async -> Bool {
        available
    }

    func complete(
        messages: [LLMMessage],
        model: String?,
        timeout: TimeInterval
    ) async throws -> String {
        guard available else {
            throw LLMError.notAvailable(reason: "Mock not available")
        }
        return response
    }
}

/// Mock provider that counts calls.
private final class CountingMockProvider: LLMProvider, @unchecked Sendable {
    let id: String = "counting-mock"
    let name: String = "Counting Mock Provider"
    private let onCall: () -> Void

    init(onCall: @escaping () -> Void) {
        self.onCall = onCall
    }

    func isAvailable() async -> Bool {
        true
    }

    func complete(
        messages: [LLMMessage],
        model: String?,
        timeout: TimeInterval
    ) async throws -> String {
        onCall()
        return "1. test query - rationale"
    }
}
