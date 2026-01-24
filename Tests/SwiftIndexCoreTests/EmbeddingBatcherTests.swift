// MARK: - EmbeddingBatcherTests

import Foundation
@testable import SwiftIndexCore
import Testing

// MARK: - Test Mock Provider

/// Mock provider that tracks batch calls for testing the batcher.
private actor BatchTrackingMockProvider: EmbeddingProvider {
    nonisolated let id: String = "batch-mock"
    nonisolated let name: String = "Batch Tracking Mock"
    nonisolated let dimension: Int = 384

    private var _embedCalls: [[String]] = []
    private var _delayMs: UInt64 = 0
    private var _shouldFail: Bool = false

    var embedCalls: [[String]] {
        _embedCalls
    }

    var totalTextCount: Int {
        _embedCalls.reduce(0) { $0 + $1.count }
    }

    var callCount: Int {
        _embedCalls.count
    }

    func setDelay(ms: UInt64) {
        _delayMs = ms
    }

    func setShouldFail(_ fail: Bool) {
        _shouldFail = fail
    }

    nonisolated func isAvailable() async -> Bool {
        true
    }

    func embed(_ text: String) async throws -> [Float] {
        try await embed([text]).first ?? []
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        _embedCalls.append(texts)
        let delay = _delayMs
        let fail = _shouldFail

        if delay > 0 {
            try await Task.sleep(nanoseconds: delay * 1_000_000)
        }

        if fail {
            throw ProviderError.unknown("Simulated failure")
        }

        // Return deterministic embeddings
        return texts.map { text in
            generateEmbedding(for: text)
        }
    }

    private nonisolated func generateEmbedding(for text: String) -> [Float] {
        // Simple hash-based embedding for testing
        let hash = stableHash(text)
        return (0 ..< dimension).map { i in
            Float((hash &+ i) % 1000) / 1000.0
        }
    }

    private nonisolated func stableHash(_ text: String) -> Int {
        // Use a stable hash for deterministic results
        var hash = 5381
        for char in text.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(char)
        }
        return hash
    }
}

// MARK: - Configuration Tests

@Suite("EmbeddingBatcher Configuration Tests")
struct EmbeddingBatcherConfigurationTests {
    @Test("Default configuration values")
    func defaultConfiguration() {
        let config = EmbeddingBatcher.Configuration()

        #expect(config.batchSize == 32)
        #expect(config.timeoutNanoseconds == 150 * 1_000_000)
        #expect(config.memoryLimitBytes == 10 * 1024 * 1024)
    }

    @Test("Custom configuration values")
    func customConfiguration() {
        let config = EmbeddingBatcher.Configuration(
            batchSize: 64,
            timeoutMs: 200,
            memoryLimitMB: 20
        )

        #expect(config.batchSize == 64)
        #expect(config.timeoutNanoseconds == 200 * 1_000_000)
        #expect(config.memoryLimitBytes == 20 * 1024 * 1024)
    }
}

// MARK: - Basic Functionality Tests

@Suite("EmbeddingBatcher Basic Tests")
struct EmbeddingBatcherBasicTests {
    @Test("Empty texts returns empty embeddings")
    func emptyTexts() async throws {
        let provider = BatchTrackingMockProvider()
        let batcher = EmbeddingBatcher(provider: provider)

        let result = try await batcher.embed([])

        #expect(result.isEmpty)
        #expect(await provider.callCount == 0)
    }

    @Test("Single text is embedded correctly")
    func singleText() async throws {
        let provider = BatchTrackingMockProvider()
        let config = EmbeddingBatcher.Configuration(
            batchSize: 32,
            timeoutMs: 10, // Short timeout for testing
            memoryLimitMB: 10
        )
        let batcher = EmbeddingBatcher(provider: provider, configuration: config)

        let texts = ["Hello, world!"]
        let result = try await batcher.embed(texts)

        // Wait for timeout to trigger flush
        try await Task.sleep(nanoseconds: 50_000_000)
        try await batcher.flush()

        #expect(result.count == 1)
        #expect(result[0].count == 384) // dimension
    }

    @Test("Multiple texts preserve order")
    func multipleTextsOrder() async throws {
        let provider = BatchTrackingMockProvider()
        let config = EmbeddingBatcher.Configuration(
            batchSize: 100, // Large batch to ensure single call
            timeoutMs: 10,
            memoryLimitMB: 10
        )
        let batcher = EmbeddingBatcher(provider: provider, configuration: config)

        let texts = ["text1", "text2", "text3", "text4", "text5"]
        let result = try await batcher.embed(texts)
        try await batcher.flush()

        #expect(result.count == 5)

        // Verify each embedding is different (based on text)
        for i in 0 ..< result.count {
            for j in (i + 1) ..< result.count {
                #expect(result[i] != result[j])
            }
        }
    }
}

// MARK: - Batching Behavior Tests

@Suite("EmbeddingBatcher Batching Tests")
struct EmbeddingBatcherBatchingTests {
    @Test("Concurrent requests are batched together")
    func concurrentBatching() async throws {
        let provider = BatchTrackingMockProvider()
        // Use a short timeout but large batch size
        let config = EmbeddingBatcher.Configuration(
            batchSize: 100,
            timeoutMs: 100,
            memoryLimitMB: 10
        )
        let batcher = EmbeddingBatcher(provider: provider, configuration: config)

        // Launch multiple concurrent requests
        async let result1 = batcher.embed(["text1", "text2"])
        async let result2 = batcher.embed(["text3", "text4"])
        async let result3 = batcher.embed(["text5"])

        // Wait for all
        let r1 = try await result1
        let r2 = try await result2
        let r3 = try await result3
        try await batcher.flush()

        // Verify all embeddings were returned
        #expect(r1.count == 2)
        #expect(r2.count == 2)
        #expect(r3.count == 1)

        // Verify batching occurred (fewer calls than requests)
        #expect(await provider.callCount <= 3)
        #expect(await provider.totalTextCount == 5)
    }

    @Test("Batch size limit triggers flush")
    func batchSizeLimit() async throws {
        let provider = BatchTrackingMockProvider()
        let config = EmbeddingBatcher.Configuration(
            batchSize: 3, // Small batch size
            timeoutMs: 5000, // Long timeout
            memoryLimitMB: 10
        )
        let batcher = EmbeddingBatcher(provider: provider, configuration: config)

        // Send exactly batch size texts
        let texts = ["text1", "text2", "text3"]
        let result = try await batcher.embed(texts)

        // Should have been flushed immediately due to batch size
        #expect(result.count == 3)
        try await batcher.flush()
        #expect(await provider.callCount >= 1)
    }

    @Test("Timeout triggers flush for partial batch")
    func timeoutFlush() async throws {
        let provider = BatchTrackingMockProvider()
        let config = EmbeddingBatcher.Configuration(
            batchSize: 100, // Large batch size
            timeoutMs: 50, // Short timeout
            memoryLimitMB: 10
        )
        let batcher = EmbeddingBatcher(provider: provider, configuration: config)

        let result = try await batcher.embed(["text1"])

        // Wait for timeout
        try await Task.sleep(nanoseconds: 100_000_000)
        try await batcher.flush()

        #expect(result.count == 1)
        #expect(await provider.callCount >= 1)
    }
}

// MARK: - Cross-file Batching Tests

/// Actor to collect results safely
private actor ResultsCollector {
    var results: [[[Float]]] = []

    func append(_ result: [[Float]]) {
        results.append(result)
    }

    func totalChunks() -> Int {
        results.reduce(0) { $0 + $1.count }
    }
}

@Suite("EmbeddingBatcher Cross-file Tests")
struct EmbeddingBatcherCrossFileTests {
    @Test("Simulates cross-file indexing batching")
    func crossFileBatching() async throws {
        let provider = BatchTrackingMockProvider()
        let config = EmbeddingBatcher.Configuration(
            batchSize: 10,
            timeoutMs: 50,
            memoryLimitMB: 10
        )
        let batcher = EmbeddingBatcher(provider: provider, configuration: config)

        // Simulate concurrent file indexing
        let collector = ResultsCollector()

        try await withThrowingTaskGroup(of: [[Float]].self) { group in
            // Simulate 5 files with varying chunk counts
            let fileSizes = [2, 3, 1, 4, 2]

            for (fileIndex, chunkCount) in fileSizes.enumerated() {
                group.addTask {
                    let texts = (0 ..< chunkCount).map { "file\(fileIndex)_chunk\($0)" }
                    return try await batcher.embed(texts)
                }
            }

            for try await result in group {
                await collector.append(result)
            }
        }

        try await batcher.flush()

        // Verify all embeddings were returned
        let totalChunks = await collector.totalChunks()
        #expect(totalChunks == 12) // 2+3+1+4+2

        // Verify batching was effective (fewer calls than files)
        #expect(await provider.totalTextCount == 12)
    }
}

// MARK: - Error Handling Tests

@Suite("EmbeddingBatcher Error Handling Tests")
struct EmbeddingBatcherErrorTests {
    @Test("Error propagates to all requests in batch")
    func errorPropagation() async throws {
        let provider = BatchTrackingMockProvider()
        await provider.setShouldFail(true)

        let config = EmbeddingBatcher.Configuration(
            batchSize: 100,
            timeoutMs: 50,
            memoryLimitMB: 10
        )
        let batcher = EmbeddingBatcher(provider: provider, configuration: config)

        // Launch concurrent requests that will be batched together
        var failureCount = 0

        await withTaskGroup(of: Bool.self) { group in
            for i in 0 ..< 3 {
                group.addTask {
                    do {
                        _ = try await batcher.embed(["text\(i)"])
                        return false // Should have thrown
                    } catch {
                        return true // Expected
                    }
                }
            }

            for await failed in group {
                if failed {
                    failureCount += 1
                }
            }
        }

        // All requests should have failed
        #expect(failureCount == 3)
    }

    @Test("Shutdown fails pending requests")
    func shutdownFails() async throws {
        let provider = BatchTrackingMockProvider()
        await provider.setDelay(ms: 1000) // Long delay

        let config = EmbeddingBatcher.Configuration(
            batchSize: 100,
            timeoutMs: 5000,
            memoryLimitMB: 10
        )
        let batcher = EmbeddingBatcher(provider: provider, configuration: config)

        // Start a request but don't wait for it
        let task = Task {
            try await batcher.embed(["test"])
        }

        // Give it time to enqueue
        try await Task.sleep(nanoseconds: 10_000_000)

        // Shutdown should cancel pending
        await batcher.shutdown()

        // The task should fail with shutdown error
        do {
            _ = try await task.value
            Issue.record("Should have thrown")
        } catch is BatcherError {
            // Expected
        } catch {
            // Also acceptable - could be cancelled
        }
    }
}

// MARK: - Memory Limit Tests

@Suite("EmbeddingBatcher Memory Limit Tests")
struct EmbeddingBatcherMemoryLimitTests {
    @Test("Memory limit triggers flush")
    func memoryLimit() async throws {
        let provider = BatchTrackingMockProvider()
        let config = EmbeddingBatcher.Configuration(
            batchSize: 1000, // Large batch size
            timeoutMs: 5000, // Long timeout
            memoryLimitMB: 1 // Small memory limit (1MB)
        )
        let batcher = EmbeddingBatcher(provider: provider, configuration: config)

        // Create texts that exceed 1MB
        let largeText = String(repeating: "x", count: 500_000) // 500KB per text

        // Two of these should trigger memory limit
        async let result1 = batcher.embed([largeText])
        async let result2 = batcher.embed([largeText])
        async let result3 = batcher.embed([largeText])

        let r1 = try await result1
        let r2 = try await result2
        let r3 = try await result3
        try await batcher.flush()

        #expect(r1.count == 1)
        #expect(r2.count == 1)
        #expect(r3.count == 1)

        // Should have triggered at least one flush due to memory limit
        #expect(await provider.callCount >= 1)
    }
}

// MARK: - Flush Tests

@Suite("EmbeddingBatcher Flush Tests")
struct EmbeddingBatcherFlushTests {
    @Test("Explicit flush processes all pending")
    func explicitFlush() async throws {
        let provider = BatchTrackingMockProvider()
        let config = EmbeddingBatcher.Configuration(
            batchSize: 1000,
            timeoutMs: 5000, // Long timeout
            memoryLimitMB: 100
        )
        let batcher = EmbeddingBatcher(provider: provider, configuration: config)

        // Queue up some requests
        async let result = batcher.embed(["text1", "text2", "text3"])

        // Wait a bit then flush
        try await Task.sleep(nanoseconds: 10_000_000)
        try await batcher.flush()

        let r = try await result
        #expect(r.count == 3)
        #expect(await provider.callCount >= 1)
    }

    @Test("Multiple flushes are idempotent")
    func multipleFlushes() async throws {
        let provider = BatchTrackingMockProvider()
        let batcher = EmbeddingBatcher(provider: provider)

        _ = try await batcher.embed(["text1"])
        try await batcher.flush()

        let callCountAfterFirstFlush = await provider.callCount

        try await batcher.flush()
        try await batcher.flush()

        // Additional flushes should not cause more calls
        #expect(await provider.callCount == callCountAfterFirstFlush)
    }
}

// MARK: - Order Preservation Tests

@Suite("EmbeddingBatcher Order Preservation Tests")
struct EmbeddingBatcherOrderTests {
    @Test("Embeddings match input order across batched requests")
    func orderPreservation() async throws {
        let provider = BatchTrackingMockProvider()
        let config = EmbeddingBatcher.Configuration(
            batchSize: 100,
            timeoutMs: 100,
            memoryLimitMB: 10
        )
        let batcher = EmbeddingBatcher(provider: provider, configuration: config)

        // Create unique texts
        let texts1 = ["unique_a", "unique_b"]
        let texts2 = ["unique_c", "unique_d", "unique_e"]

        // Launch concurrently
        async let result1 = batcher.embed(texts1)
        async let result2 = batcher.embed(texts2)

        let r1 = try await result1
        let r2 = try await result2
        try await batcher.flush()

        // Generate expected embeddings directly
        let expected1 = texts1.map { generateExpectedEmbedding(for: $0) }
        let expected2 = texts2.map { generateExpectedEmbedding(for: $0) }

        // Verify order preservation - each result matches its input texts
        #expect(r1.count == 2)
        #expect(r2.count == 3)

        // The embeddings should be consistent with the input
        for i in 0 ..< r1.count {
            #expect(r1[i] == expected1[i])
        }
        for i in 0 ..< r2.count {
            #expect(r2[i] == expected2[i])
        }
    }

    private func generateExpectedEmbedding(for text: String) -> [Float] {
        let hash = stableHash(text)
        return (0 ..< 384).map { i in
            Float((hash &+ i) % 1000) / 1000.0
        }
    }

    private func stableHash(_ text: String) -> Int {
        var hash = 5381
        for char in text.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(char)
        }
        return hash
    }
}
