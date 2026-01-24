// MARK: - Cancellation Token

import Foundation

/// Token for cooperative cancellation of long-running operations (2025-11-25 spec).
///
/// This provides a simple, actor-isolated mechanism for checking cancellation status
/// during async operations like indexing. Tools can periodically call `checkCancellation()`
/// to throw if the request was cancelled.
///
/// Example usage:
/// ```swift
/// func performLongOperation(token: CancellationToken) async throws {
///     for item in items {
///         try await token.checkCancellation()
///         await processItem(item)
///     }
/// }
/// ```
public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false

    public init() {}

    /// Cancels the token.
    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        _isCancelled = true
    }

    /// Returns whether the token has been cancelled.
    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    /// Throws `CancellationError` if the token has been cancelled.
    public func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }

    /// Async version that also checks Swift's task cancellation.
    public func checkCancellationAsync() async throws {
        try Task.checkCancellation()
        if isCancelled {
            throw CancellationError()
        }
    }
}
