// MARK: - MCP Server

import Foundation
import Logging
import OrderedCollections
import SwiftIndexCore
import YYJSON

/// MCP Server for SwiftIndex.
///
/// Implements the Model Context Protocol (MCP) over stdin/stdout,
/// providing code indexing and search tools for AI assistants.
public actor MCPServer {
    // MARK: - Properties

    private let logger: Logger
    private let encoder: YYJSONEncoder
    private let decoder: YYJSONDecoder
    private var isInitialized: Bool = false
    private var clientInfo: MCPClientInfo?

    /// Registered tools.
    private var tools: OrderedDictionary<String, any MCPToolHandler> = [:]

    /// Active requests for cancellation support (2025-11-25 spec).
    private var activeRequests: [String: Task<JSONRPCResponse?, Error>] = [:]

    /// Cancellation tokens for long-running operations.
    private var cancellationTokens: [String: CancellationToken] = [:]

    /// Task manager for async task operations (2025-11-25 spec).
    private let taskManager = TaskManager()

    /// Server information.
    public static let serverInfo = MCPServerInfo(
        name: "swiftindex",
        version: "VERSION_PLACEHOLDER"
    )

    /// Supported protocol version (2025-11-25 spec).
    public static let protocolVersion = "2025-11-25"

    // MARK: - Initialization

    public init(logger: Logger = Logger(label: "SwiftIndexMCP")) {
        self.logger = logger

        // Use YYJSON for faster JSON processing with RFC 8259 strict mode
        encoder = YYJSONEncoder()
        decoder = YYJSONDecoder()
    }

    // MARK: - Tool Registration

    /// Register a tool handler.
    public func registerTool(_ handler: any MCPToolHandler) {
        tools[handler.definition.name] = handler
    }

    /// Unregister a tool by name.
    public func unregisterTool(named name: String) {
        tools.removeValue(forKey: name)
    }

    private func registerDefaultTools() {
        tools["index_codebase"] = IndexCodebaseTool()
        tools["search_code"] = SearchCodeTool()
        tools["search_docs"] = SearchDocsTool()
        tools["code_research"] = CodeResearchTool()
        tools["watch_codebase"] = WatchCodebaseTool()
    }

    // MARK: - Server Loop

    /// Run the MCP server, reading from stdin and writing to stdout.
    public func run() async {
        // Register default tools (must be in async context for actor isolation)
        registerDefaultTools()

        logger.info("SwiftIndex MCP server starting...")

        // Read lines from stdin
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }

            do {
                let response = try await handleMessage(line)
                if let response {
                    try writeResponse(response)
                }
            } catch {
                logger.error("Error handling message: \(error)")
                // Try to send error response
                if let errorResponse = try? createErrorResponse(
                    id: nil,
                    error: .internalError(error.localizedDescription)
                ) {
                    try? writeResponse(errorResponse)
                }
            }
        }

        logger.info("SwiftIndex MCP server shutting down")
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: String) async throws -> JSONRPCResponse? {
        guard let data = message.data(using: .utf8) else {
            throw MCPError.invalidMessage("Invalid UTF-8")
        }

        let request: JSONRPCRequest
        do {
            request = try decoder.decode(JSONRPCRequest.self, from: data)
        } catch {
            logger.error("Failed to parse JSON-RPC request: \(error)")
            return JSONRPCResponse(id: nil, error: .parseError)
        }

        logger.debug("Received request: method=\(request.method)")

        // Handle the request based on method
        return try await routeRequest(request)
    }

    private func routeRequest(_ request: JSONRPCRequest) async throws -> JSONRPCResponse? {
        switch request.method {
        // Lifecycle methods
        case "initialize":
            return try await handleInitialize(request)

        case "initialized", "notifications/initialized":
            // This is a notification, no response needed
            // Note: Some clients send "initialized", others send "notifications/initialized"
            handleInitialized()
            return nil

        case "shutdown":
            return handleShutdown(request)

        // Tool methods
        case "tools/list":
            return try handleToolsList(request)

        case "tools/call":
            return try await handleToolsCall(request)

        // Ping for health check
        case "ping":
            return JSONRPCResponse(id: request.id, result: .object([:]))

        // Cancellation notification (2025-11-25 spec)
        case "notifications/cancelled":
            handleCancellation(request)
            return nil // Notifications don't return responses

        // Tasks API (2025-11-25 spec)
        case "tasks/get":
            return try await handleTasksGet(request)

        case "tasks/list":
            return try await handleTasksList(request)

        case "tasks/result":
            return try await handleTasksResult(request)

        case "tasks/cancel":
            return try await handleTasksCancel(request)

        default:
            logger.warning("Unknown method: \(request.method)")
            return JSONRPCResponse(
                id: request.id,
                error: .methodNotFound(request.method)
            )
        }
    }

    // MARK: - Lifecycle Handlers

    private func handleInitialize(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard let params = request.params else {
            return JSONRPCResponse(id: request.id, error: .invalidParams("Missing params"))
        }

        // Parse client info if available
        if let clientInfoObj = params["clientInfo"]?.objectValue {
            let info = MCPClientInfo(
                name: clientInfoObj["name"]?.stringValue ?? "unknown",
                version: clientInfoObj["version"]?.stringValue ?? "unknown"
            )
            clientInfo = info
            logger.info("Client connected: \(info.name) \(info.version)")
        }

        let result = InitializeResult(
            protocolVersion: Self.protocolVersion,
            capabilities: MCPServerCapabilities(
                tools: .init(listChanged: false),
                tasks: TasksCapability(
                    list: TasksListCapability(),
                    cancel: TasksCancelCapability(),
                    requests: TaskRequestsCapability(
                        tools: ToolsCallTaskCapability(call: true)
                    )
                )
            ),
            serverInfo: Self.serverInfo
        )

        let resultData = try encoder.encode(result)
        let resultValue = try decoder.decode(JSONValue.self, from: resultData)

        return JSONRPCResponse(id: request.id, result: resultValue)
    }

    private func handleInitialized() {
        isInitialized = true
        logger.info("MCP session initialized")
    }

    private func handleShutdown(_ request: JSONRPCRequest) -> JSONRPCResponse {
        logger.info("Shutdown requested")
        isInitialized = false

        // Cancel all active requests on shutdown
        for (requestId, task) in activeRequests {
            task.cancel()
            logger.debug("Cancelled request on shutdown: \(requestId)")
        }
        activeRequests.removeAll()
        cancellationTokens.removeAll()

        return JSONRPCResponse(id: request.id, result: .null)
    }

    // MARK: - Cancellation Support (2025-11-25 spec)

    private func handleCancellation(_ request: JSONRPCRequest) {
        guard let params = request.params,
              let requestIdValue = params["requestId"]
        else {
            logger.warning("Cancellation notification missing requestId")
            return
        }

        let requestId = extractRequestIdString(from: requestIdValue)

        // Cancel the task if it exists
        if let task = activeRequests[requestId] {
            task.cancel()
            activeRequests.removeValue(forKey: requestId)
            logger.info("Cancelled request: \(requestId)")
        }

        // Cancel via token if available
        if let token = cancellationTokens[requestId] {
            token.cancel()
            cancellationTokens.removeValue(forKey: requestId)
            logger.debug("Cancelled token for request: \(requestId)")
        }

        // Log reason if provided
        if let reason = params["reason"]?.stringValue {
            logger.debug("Cancellation reason: \(reason)")
        }
    }

    private func extractRequestIdString(from value: JSONValue) -> String {
        switch value {
        case let .string(s):
            s
        case let .int(i):
            String(i)
        default:
            String(describing: value)
        }
    }

    /// Creates a cancellation token for a request.
    func createCancellationToken(for requestId: RequestID) -> CancellationToken {
        let idString = requestIdToString(requestId)
        let token = CancellationToken()
        cancellationTokens[idString] = token
        return token
    }

    private func requestIdToString(_ id: RequestID) -> String {
        switch id {
        case let .string(s):
            s
        case let .number(n):
            String(n)
        }
    }

    // MARK: - Tool Handlers

    private func handleToolsList(_ request: JSONRPCRequest) throws -> JSONRPCResponse {
        // Validate server is initialized (2025-11-25 spec)
        guard isInitialized else {
            return JSONRPCResponse(id: request.id, error: .serverNotInitialized)
        }

        let toolDefinitions = tools.values.map(\.definition)
        let result = ToolsListResult(tools: toolDefinitions)

        let resultData = try encoder.encode(result)
        let resultValue = try decoder.decode(JSONValue.self, from: resultData)

        return JSONRPCResponse(id: request.id, result: resultValue)
    }

    private func handleToolsCall(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
        // Validate server is initialized (2025-11-25 spec)
        guard isInitialized else {
            return JSONRPCResponse(id: request.id, error: .serverNotInitialized)
        }

        guard let params = request.params else {
            return JSONRPCResponse(id: request.id, error: .invalidParams("Missing params"))
        }

        guard let toolName = params["name"]?.stringValue else {
            return JSONRPCResponse(id: request.id, error: .invalidParams("Missing tool name"))
        }

        guard let tool = tools[toolName] else {
            return JSONRPCResponse(
                id: request.id,
                error: .invalidParams("Unknown tool: \(toolName)")
            )
        }

        let arguments = params["arguments"] ?? .object([:])

        // Check for task-augmented call (2025-11-25 spec)
        if let taskParams = params["task"]?.objectValue {
            return try await handleTaskAugmentedToolCall(
                request: request,
                tool: tool,
                toolName: toolName,
                arguments: arguments,
                taskParams: taskParams
            )
        }

        logger.debug("Calling tool: \(toolName)")

        do {
            let result = try await tool.execute(arguments: arguments)
            let resultData = try encoder.encode(result)
            let resultValue = try decoder.decode(JSONValue.self, from: resultData)
            return JSONRPCResponse(id: request.id, result: resultValue)
        } catch {
            logger.error("Tool execution failed: \(error)")
            let errorResult = ToolCallResult.error("Tool execution failed: \(error.localizedDescription)")
            let resultData = try encoder.encode(errorResult)
            let resultValue = try decoder.decode(JSONValue.self, from: resultData)
            return JSONRPCResponse(id: request.id, result: resultValue)
        }
    }

    /// Handles a task-augmented tool call (2025-11-25 spec).
    private func handleTaskAugmentedToolCall(
        request: JSONRPCRequest,
        tool: any MCPToolHandler,
        toolName: String,
        arguments: JSONValue,
        taskParams: [String: JSONValue]
    ) async throws -> JSONRPCResponse {
        let ttl = taskParams["ttl"]?.intValue
        let pollInterval = taskParams["pollInterval"]?.intValue

        // Create the task
        let task = await taskManager.createTask(ttl: ttl, pollInterval: pollInterval)
        logger.info("Created task \(task.taskId) for tool: \(toolName)")

        // Start background execution
        let backgroundTask = Task {
            do {
                // Get cancellation token
                let token = await taskManager.getCancellationToken(task.taskId)

                // Execute the tool
                let result = try await tool.execute(arguments: arguments)

                // Check if cancelled during execution
                if token?.isCancelled == true {
                    await taskManager.updateStatus(task.taskId, status: .cancelled)
                } else {
                    await taskManager.storeResult(task.taskId, result: result)
                }
            } catch is CancellationError {
                await taskManager.updateStatus(task.taskId, status: .cancelled)
            } catch {
                await taskManager.failTask(task.taskId, error: error.localizedDescription)
            }
        }
        await taskManager.registerBackgroundTask(task.taskId, task: backgroundTask)

        // Return immediately with task info
        let createResult = CreateTaskResult(task: task)
        let resultData = try encoder.encode(createResult)
        let resultValue = try decoder.decode(JSONValue.self, from: resultData)
        return JSONRPCResponse(id: request.id, result: resultValue)
    }

    // MARK: - Tasks Handlers (2025-11-25 spec)

    private func handleTasksGet(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard isInitialized else {
            return JSONRPCResponse(id: request.id, error: .serverNotInitialized)
        }

        guard let params = request.params,
              let taskId = params["taskId"]?.stringValue
        else {
            return JSONRPCResponse(id: request.id, error: .invalidParams("Missing taskId"))
        }

        guard let task = await taskManager.getTask(taskId) else {
            return JSONRPCResponse(
                id: request.id,
                error: .invalidParams("Task not found: \(taskId)")
            )
        }

        let result = TaskGetResult(task: task)
        let resultData = try encoder.encode(result)
        let resultValue = try decoder.decode(JSONValue.self, from: resultData)
        return JSONRPCResponse(id: request.id, result: resultValue)
    }

    private func handleTasksList(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard isInitialized else {
            return JSONRPCResponse(id: request.id, error: .serverNotInitialized)
        }

        let cursor = request.params?["cursor"]?.stringValue
        let limit = request.params?["limit"]?.intValue ?? 100

        let result = await taskManager.listTasks(cursor: cursor, limit: limit)
        let resultData = try encoder.encode(result)
        let resultValue = try decoder.decode(JSONValue.self, from: resultData)
        return JSONRPCResponse(id: request.id, result: resultValue)
    }

    private func handleTasksResult(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard isInitialized else {
            return JSONRPCResponse(id: request.id, error: .serverNotInitialized)
        }

        guard let params = request.params,
              let taskId = params["taskId"]?.stringValue
        else {
            return JSONRPCResponse(id: request.id, error: .invalidParams("Missing taskId"))
        }

        guard let task = await taskManager.getTask(taskId) else {
            return JSONRPCResponse(
                id: request.id,
                error: .invalidParams("Task not found: \(taskId)")
            )
        }

        // Wait for result (blocking)
        do {
            let toolResult = try await taskManager.awaitResult(taskId)
            let updatedTask = await taskManager.getTask(taskId) ?? task

            let result = TaskResultResponse(task: updatedTask, result: toolResult)
            let resultData = try encoder.encode(result)
            let resultValue = try decoder.decode(JSONValue.self, from: resultData)
            return JSONRPCResponse(id: request.id, result: resultValue)
        } catch is CancellationError {
            return JSONRPCResponse(id: request.id, error: .requestCancelled)
        } catch {
            return JSONRPCResponse(
                id: request.id,
                error: .internalError(error.localizedDescription)
            )
        }
    }

    private func handleTasksCancel(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard isInitialized else {
            return JSONRPCResponse(id: request.id, error: .serverNotInitialized)
        }

        guard let params = request.params,
              let taskId = params["taskId"]?.stringValue
        else {
            return JSONRPCResponse(id: request.id, error: .invalidParams("Missing taskId"))
        }

        guard let task = await taskManager.cancelTask(taskId) else {
            return JSONRPCResponse(
                id: request.id,
                error: .invalidParams("Task not found: \(taskId)")
            )
        }

        let result = TaskCancelResult(task: task)
        let resultData = try encoder.encode(result)
        let resultValue = try decoder.decode(JSONValue.self, from: resultData)
        return JSONRPCResponse(id: request.id, result: resultValue)
    }

    // MARK: - Response Writing

    private func writeResponse(_ response: JSONRPCResponse) throws {
        let data = try encoder.encode(response)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw MCPError.encodingFailed
        }

        // Write to stdout with newline
        print(jsonString)
        fflush(stdout)
    }

    private func createErrorResponse(id: RequestID?, error: JSONRPCError) throws -> JSONRPCResponse {
        JSONRPCResponse(id: id, error: error)
    }

    func toolDefinitionsForTesting() -> [MCPTool] {
        tools.values.map(\.definition)
    }
}

// MARK: - MCP Tool Handler Protocol

/// Protocol for MCP tool handlers.
public protocol MCPToolHandler: Sendable {
    /// The tool definition including name, description, and input schema.
    var definition: MCPTool { get }

    /// Execute the tool with the given arguments.
    func execute(arguments: JSONValue) async throws -> ToolCallResult
}

// MARK: - MCP Errors

/// Errors that can occur during MCP operations.
public enum MCPError: Error, LocalizedError {
    case invalidMessage(String)
    case encodingFailed
    case toolNotFound(String)
    case invalidArguments(String)
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidMessage(details):
            "Invalid message: \(details)"
        case .encodingFailed:
            "Failed to encode response"
        case let .toolNotFound(name):
            "Tool not found: \(name)"
        case let .invalidArguments(details):
            "Invalid arguments: \(details)"
        case let .executionFailed(details):
            "Execution failed: \(details)"
        }
    }
}
