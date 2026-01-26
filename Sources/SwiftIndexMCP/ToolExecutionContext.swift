// MARK: - Tool Execution Context

import Foundation

/// Context for tool execution with progress reporting and cancellation support.
///
/// This actor provides a thread-safe way for long-running tools to:
/// - Report progress updates via `statusMessage` in the Tasks API
/// - Check for cancellation requests
///
/// ## Usage
///
/// ```swift
/// func execute(arguments: JSONValue, context: ToolExecutionContext?) async throws -> ToolCallResult {
///     for (index, file) in files.enumerated() {
///         try await context?.checkCancellation()
///         await context?.reportProgress(
///             current: index + 1,
///             total: files.count,
///             message: "Processing \(file.lastPathComponent)"
///         )
///         // Process file...
///     }
/// }
/// ```
public actor ToolExecutionContext {
    // MARK: - Properties

    /// The task ID associated with this execution, if running as a task.
    public let taskId: String?

    /// The task manager for updating task status.
    private let taskManager: TaskManager

    /// Cancellation token for cooperative cancellation.
    private let cancellationToken: CancellationToken?

    // MARK: - Initialization

    /// Creates a new tool execution context.
    ///
    /// - Parameters:
    ///   - taskId: The task ID if running as a task-augmented call.
    ///   - taskManager: The task manager for status updates.
    ///   - cancellationToken: Token for cancellation checking.
    public init(
        taskId: String?,
        taskManager: TaskManager,
        cancellationToken: CancellationToken?
    ) {
        self.taskId = taskId
        self.taskManager = taskManager
        self.cancellationToken = cancellationToken
    }

    // MARK: - Progress Reporting

    /// Reports progress for the current operation.
    ///
    /// Updates the task's `statusMessage` with a formatted progress string.
    /// Does nothing if not running as a task.
    ///
    /// - Parameters:
    ///   - current: Current item number (1-based recommended).
    ///   - total: Total number of items.
    ///   - message: Optional descriptive message (e.g., "Indexing: User.swift").
    public func reportProgress(
        current: Int,
        total: Int,
        message: String? = nil
    ) async {
        guard let taskId else { return }

        let percent = total > 0 ? (current * 100) / total : 0
        let status = if let message {
            "\(message) (\(current)/\(total), \(percent)%)"
        } else {
            "Processing \(current)/\(total) (\(percent)%)"
        }

        await taskManager.updateStatus(taskId, status: .working, message: status)
    }

    /// Reports a status message without numeric progress.
    ///
    /// - Parameter message: Status message to display.
    public func reportStatus(_ message: String) async {
        guard let taskId else { return }
        await taskManager.updateStatus(taskId, status: .working, message: message)
    }

    // MARK: - Cancellation

    /// Checks if the operation has been cancelled.
    ///
    /// - Throws: `CancellationError` if the operation was cancelled.
    public func checkCancellation() async throws {
        try await cancellationToken?.checkCancellationAsync()
    }

    /// Returns whether cancellation has been requested.
    public var isCancelled: Bool {
        cancellationToken?.isCancelled ?? false
    }
}
