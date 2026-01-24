// MARK: - EmbeddingBatcher

import Foundation

/// Batches embedding requests across files to maximize GPU/MLX utilization.
///
/// The batcher collects chunk embedding requests from concurrent indexing tasks
/// and returns embeddings asynchronously. It flushes batches when:
/// - Batch size limit is reached
/// - Idle timeout expires (no new requests)
/// - Memory limit is exceeded
/// - Explicit flush is called
///
/// ## Usage
///
/// ```swift
/// let batcher = EmbeddingBatcher(provider: embeddingProvider)
///
/// // In concurrent indexing tasks:
/// let embeddings = try await batcher.embed(chunksToEmbed.map(\.content))
///
/// // After indexing completes:
/// try await batcher.flush()
/// ```
///
/// ## Thread Safety
///
/// The batcher is an actor to safely coordinate between concurrent indexing tasks.
public actor EmbeddingBatcher {
    // MARK: - Types

    /// Configuration for the embedding batcher.
    public struct Configuration: Sendable {
        /// Maximum number of texts per embedding call.
        public var batchSize: Int

        /// Idle timeout before flushing pending requests (nanoseconds).
        public var timeoutNanoseconds: UInt64

        /// Memory limit for pending chunks (bytes).
        public var memoryLimitBytes: Int

        public init(
            batchSize: Int = 32,
            timeoutMs: Int = 150,
            memoryLimitMB: Int = 10
        ) {
            self.batchSize = batchSize
            timeoutNanoseconds = UInt64(timeoutMs) * 1_000_000
            memoryLimitBytes = memoryLimitMB * 1024 * 1024
        }

        /// Default configuration.
        public static let `default` = Configuration()
    }

    /// A pending embedding request.
    private struct PendingRequest: Sendable {
        let texts: [String]
        let continuation: CheckedContinuation<[[Float]], any Error>
    }

    // MARK: - Properties

    private let provider: any EmbeddingProvider
    private let config: Configuration

    /// Pending requests waiting to be batched.
    private var pendingRequests: [PendingRequest] = []

    /// Total byte size of pending texts (for memory limit).
    private var pendingByteSize: Int = 0

    /// Total text count across all pending requests.
    private var pendingTextCount: Int = 0

    /// Task handling the idle timeout flush.
    private var timeoutTask: Task<Void, Never>?

    /// Whether the batcher is shutting down.
    private var isShuttingDown = false

    // MARK: - Initialization

    /// Creates a new embedding batcher.
    ///
    /// - Parameters:
    ///   - provider: The embedding provider to use for batch operations.
    ///   - configuration: Batching configuration (batch size, timeout, memory limit).
    public init(
        provider: any EmbeddingProvider,
        configuration: Configuration = .default
    ) {
        self.provider = provider
        config = configuration
    }

    // MARK: - Public API

    /// Embeds texts, potentially batching with other concurrent requests.
    ///
    /// The returned embeddings correspond to the input texts in order.
    ///
    /// - Parameter texts: Array of texts to embed.
    /// - Returns: Array of embedding vectors, one per input text.
    /// - Throws: `ProviderError` if embedding fails.
    public func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else {
            return []
        }

        // If shutting down, fall through directly to provider
        if isShuttingDown {
            return try await provider.embed(texts)
        }

        // Calculate byte size of this request
        let requestByteSize = texts.reduce(0) { $0 + $1.utf8.count }

        return try await withCheckedThrowingContinuation { continuation in
            let request = PendingRequest(texts: texts, continuation: continuation)
            enqueueRequest(request, byteSize: requestByteSize)
        }
    }

    /// Flushes all pending requests immediately.
    ///
    /// Call this after indexing completes to ensure all requests are processed.
    public func flush() async throws {
        isShuttingDown = true
        cancelTimeoutTask()
        try await processPendingBatch()
    }

    /// Shuts down the batcher, cancelling any pending operations.
    public func shutdown() {
        isShuttingDown = true
        cancelTimeoutTask()

        // Fail all pending requests
        let error = BatcherError.shutdown
        for request in pendingRequests {
            request.continuation.resume(throwing: error)
        }
        pendingRequests.removeAll()
        pendingByteSize = 0
        pendingTextCount = 0
    }

    // MARK: - Private Methods

    private func enqueueRequest(_ request: PendingRequest, byteSize: Int) {
        pendingRequests.append(request)
        pendingByteSize += byteSize
        pendingTextCount += request.texts.count

        // Check if we should flush immediately
        let shouldFlush = pendingTextCount >= config.batchSize ||
            pendingByteSize >= config.memoryLimitBytes

        if shouldFlush {
            cancelTimeoutTask()
            // Schedule flush on next actor hop to avoid reentrancy
            Task { [weak self] in
                try? await self?.processPendingBatch()
            }
        } else {
            // Start or reset the timeout task
            restartTimeoutTask()
        }
    }

    private func restartTimeoutTask() {
        cancelTimeoutTask()

        let timeoutNs = config.timeoutNanoseconds
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeoutNs)
                // Timeout expired, flush the batch
                try? await self?.processPendingBatch()
            } catch {
                // Task was cancelled, ignore
            }
        }
    }

    private func cancelTimeoutTask() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func processPendingBatch() async throws {
        guard !pendingRequests.isEmpty else {
            return
        }

        // Take the pending requests
        let requests = pendingRequests
        pendingRequests = []
        pendingByteSize = 0
        pendingTextCount = 0

        // Combine all texts
        var allTexts: [String] = []
        var requestRanges: [(request: PendingRequest, range: Range<Int>)] = []

        for request in requests {
            let startIndex = allTexts.count
            allTexts.append(contentsOf: request.texts)
            let endIndex = allTexts.count
            requestRanges.append((request, startIndex ..< endIndex))
        }

        // Call the provider once for all texts
        do {
            let allEmbeddings = try await provider.embed(allTexts)

            // Distribute embeddings back to each request
            for (request, range) in requestRanges {
                let embeddings = Array(allEmbeddings[range])
                request.continuation.resume(returning: embeddings)
            }
        } catch {
            // Propagate error to all requests in this batch
            for (request, _) in requestRanges {
                request.continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Errors

/// Errors specific to the embedding batcher.
public enum BatcherError: Error, Sendable {
    /// The batcher was shut down before the request could be processed.
    case shutdown
}
