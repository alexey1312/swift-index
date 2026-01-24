// MARK: - MCP Tasks API (2025-11-25 spec)

import Foundation

// MARK: - Task Status

/// Status of an MCP task.
public enum TaskStatus: String, Codable, Sendable {
    case working
    case inputRequired = "input_required"
    case completed
    case failed
    case cancelled
}

// MARK: - Task Types

/// MCP task representation.
public struct MCPTask: Codable, Sendable {
    public let taskId: String
    public var status: TaskStatus
    public var statusMessage: String?
    public let createdAt: String
    public var lastUpdatedAt: String
    public var ttl: Int?
    public var pollInterval: Int?

    public init(
        taskId: String,
        status: TaskStatus = .working,
        statusMessage: String? = nil,
        createdAt: String? = nil,
        lastUpdatedAt: String? = nil,
        ttl: Int? = nil,
        pollInterval: Int? = nil
    ) {
        self.taskId = taskId
        self.status = status
        self.statusMessage = statusMessage
        let now = ISO8601DateFormatter().string(from: Date())
        self.createdAt = createdAt ?? now
        self.lastUpdatedAt = lastUpdatedAt ?? now
        self.ttl = ttl
        self.pollInterval = pollInterval
    }
}

/// Result of creating a task.
public struct CreateTaskResult: Codable, Sendable {
    public let task: MCPTask

    public init(task: MCPTask) {
        self.task = task
    }
}

/// Result of listing tasks.
public struct TasksListResult: Codable, Sendable {
    public let tasks: [MCPTask]
    public let nextCursor: String?

    public init(tasks: [MCPTask], nextCursor: String? = nil) {
        self.tasks = tasks
        self.nextCursor = nextCursor
    }
}

/// Result of getting a single task.
public struct TaskGetResult: Codable, Sendable {
    public let task: MCPTask

    public init(task: MCPTask) {
        self.task = task
    }
}

/// Result of getting task result (blocking).
public struct TaskResultResponse: Codable, Sendable {
    public let task: MCPTask
    public let result: ToolCallResult?

    public init(task: MCPTask, result: ToolCallResult? = nil) {
        self.task = task
        self.result = result
    }
}

/// Result of cancelling a task.
public struct TaskCancelResult: Codable, Sendable {
    public let task: MCPTask

    public init(task: MCPTask) {
        self.task = task
    }
}

// MARK: - Task Parameters

/// Parameters for task-augmented tool calls.
public struct TaskParams: Codable, Sendable {
    /// Time-to-live in milliseconds before task auto-cancels.
    public let ttl: Int?

    /// Suggested poll interval in milliseconds.
    public let pollInterval: Int?

    public init(ttl: Int? = nil, pollInterval: Int? = nil) {
        self.ttl = ttl
        self.pollInterval = pollInterval
    }
}

// MARK: - Task Capabilities

/// Tasks capability for server capabilities.
public struct TasksCapability: Codable, Sendable {
    public let list: TasksListCapability?
    public let cancel: TasksCancelCapability?
    public let requests: TaskRequestsCapability?

    public init(
        list: TasksListCapability? = nil,
        cancel: TasksCancelCapability? = nil,
        requests: TaskRequestsCapability? = nil
    ) {
        self.list = list
        self.cancel = cancel
        self.requests = requests
    }
}

/// Capability to list tasks.
public struct TasksListCapability: Codable, Sendable {
    public init() {}
}

/// Capability to cancel tasks.
public struct TasksCancelCapability: Codable, Sendable {
    public init() {}
}

/// Capability for task-augmented requests.
public struct TaskRequestsCapability: Codable, Sendable {
    public let tools: ToolsCallTaskCapability?

    public init(tools: ToolsCallTaskCapability? = nil) {
        self.tools = tools
    }
}

/// Capability for task-augmented tool calls.
public struct ToolsCallTaskCapability: Codable, Sendable {
    public let call: Bool

    public init(call: Bool = true) {
        self.call = call
    }
}

// MARK: - Task Manager

/// Actor managing task state for the MCP server.
public actor TaskManager {
    private var tasks: [String: MCPTask] = [:]
    private var taskResults: [String: ToolCallResult] = [:]
    private var taskContinuations: [String: CheckedContinuation<ToolCallResult, Error>] = [:]
    private var cancellationTokens: [String: CancellationToken] = [:]
    private var backgroundTasks: [String: Task<Void, Never>] = [:]

    public init() {}

    /// Creates a new task.
    public func createTask(ttl: Int? = nil, pollInterval: Int? = nil) -> MCPTask {
        let taskId = UUID().uuidString
        let task = MCPTask(
            taskId: taskId,
            status: .working,
            ttl: ttl,
            pollInterval: pollInterval ?? 1000 // Default 1 second
        )
        tasks[taskId] = task

        // Create cancellation token
        cancellationTokens[taskId] = CancellationToken()

        // Schedule TTL expiration if set
        if let ttl {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(ttl) * 1_000_000)
                await self?.expireTask(taskId)
            }
        }

        return task
    }

    /// Registers a background Swift Task associated with an MCP task.
    public func registerBackgroundTask(_ taskId: String, task: Task<Void, Never>) {
        backgroundTasks[taskId] = task
    }

    /// Updates task status.
    public func updateStatus(
        _ taskId: String,
        status: TaskStatus,
        message: String? = nil
    ) {
        guard var task = tasks[taskId] else { return }
        task.status = status
        task.statusMessage = message
        task.lastUpdatedAt = ISO8601DateFormatter().string(from: Date())
        tasks[taskId] = task
    }

    /// Stores the result for a task.
    public func storeResult(_ taskId: String, result: ToolCallResult) {
        taskResults[taskId] = result
        updateStatus(taskId, status: .completed)
        backgroundTasks.removeValue(forKey: taskId)

        // Resume any waiting continuations
        if let continuation = taskContinuations.removeValue(forKey: taskId) {
            continuation.resume(returning: result)
        }
    }

    /// Marks a task as failed.
    public func failTask(_ taskId: String, error: String) {
        updateStatus(taskId, status: .failed, message: error)
        taskResults[taskId] = .error(error)
        backgroundTasks.removeValue(forKey: taskId)

        // Resume any waiting continuations with error
        if let continuation = taskContinuations.removeValue(forKey: taskId) {
            continuation.resume(returning: .error(error))
        }
    }

    /// Gets a task by ID.
    public func getTask(_ taskId: String) -> MCPTask? {
        tasks[taskId]
    }

    /// Lists all tasks with optional cursor pagination.
    public func listTasks(cursor: String? = nil, limit: Int = 100) -> TasksListResult {
        let allTasks = Array(tasks.values)
        // Simple pagination - cursor is the offset
        let offset = cursor.flatMap { Int($0) } ?? 0
        let pageTasks = Array(allTasks.dropFirst(offset).prefix(limit))
        let nextCursor = offset + pageTasks.count < allTasks.count
            ? String(offset + pageTasks.count)
            : nil
        return TasksListResult(tasks: pageTasks, nextCursor: nextCursor)
    }

    /// Cancels a task.
    public func cancelTask(_ taskId: String) -> MCPTask? {
        guard var task = tasks[taskId] else { return nil }

        // Cancel via token
        cancellationTokens[taskId]?.cancel()
        cancellationTokens.removeValue(forKey: taskId)

        // Cancel background Swift task
        backgroundTasks[taskId]?.cancel()
        backgroundTasks.removeValue(forKey: taskId)

        task.status = .cancelled
        task.lastUpdatedAt = ISO8601DateFormatter().string(from: Date())
        tasks[taskId] = task

        // Resume any waiting continuations
        if let continuation = taskContinuations.removeValue(forKey: taskId) {
            continuation.resume(throwing: CancellationError())
        }

        return task
    }

    /// Waits for a task result (blocking).
    public func awaitResult(_ taskId: String, timeout: Duration? = nil) async throws -> ToolCallResult {
        // Check if result already available
        if let result = taskResults[taskId] {
            return result
        }

        // Check if task exists
        guard let task = tasks[taskId] else {
            throw TaskError.taskNotFound(taskId)
        }

        // If already completed/failed/cancelled, return appropriate error
        switch task.status {
        case .completed:
            if let result = taskResults[taskId] {
                return result
            }
            throw TaskError.noResult(taskId)
        case .failed:
            throw TaskError.taskFailed(task.statusMessage ?? "Unknown error")
        case .cancelled:
            throw CancellationError()
        case .working, .inputRequired:
            break
        }

        // Wait for result with optional timeout
        return try await withCheckedThrowingContinuation { continuation in
            taskContinuations[taskId] = continuation
        }
    }

    /// Gets the result of a task if available.
    public func getResult(_ taskId: String) -> ToolCallResult? {
        taskResults[taskId]
    }

    /// Gets the cancellation token for a task.
    public func getCancellationToken(_ taskId: String) -> CancellationToken? {
        cancellationTokens[taskId]
    }

    /// Cleans up completed/failed/cancelled tasks older than TTL.
    public func cleanup(olderThan age: TimeInterval = 3600) {
        let now = Date()
        let formatter = ISO8601DateFormatter()

        for (taskId, task) in tasks {
            guard task.status == .completed ||
                task.status == .failed ||
                task.status == .cancelled
            else { continue }

            if let lastUpdated = formatter.date(from: task.lastUpdatedAt),
               now.timeIntervalSince(lastUpdated) > age
            {
                tasks.removeValue(forKey: taskId)
                taskResults.removeValue(forKey: taskId)
                cancellationTokens.removeValue(forKey: taskId)
            }
        }
    }

    // MARK: - Private

    private func expireTask(_ taskId: String) {
        guard let task = tasks[taskId], task.status == .working else { return }
        _ = cancelTask(taskId)
    }
}

// MARK: - Task Errors

/// Errors related to task operations.
public enum TaskError: Error, LocalizedError {
    case taskNotFound(String)
    case taskFailed(String)
    case noResult(String)

    public var errorDescription: String? {
        switch self {
        case let .taskNotFound(id):
            "Task not found: \(id)"
        case let .taskFailed(message):
            "Task failed: \(message)"
        case let .noResult(id):
            "No result available for task: \(id)"
        }
    }
}
