// MARK: - MCP Server

import Foundation
import Logging
import SwiftIndexCore

/// MCP Server for SwiftIndex.
///
/// Implements the Model Context Protocol (MCP) over stdin/stdout,
/// providing code indexing and search tools for AI assistants.
public actor MCPServer {
    // MARK: - Properties

    private let logger: Logger
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var isInitialized: Bool = false
    private var clientInfo: MCPClientInfo?

    /// Registered tools.
    private var tools: [String: any MCPToolHandler] = [:]

    /// Server information.
    public static let serverInfo = MCPServerInfo(
        name: "swiftindex",
        version: "0.1.0"
    )

    /// Supported protocol version.
    public static let protocolVersion = "2024-11-05"

    // MARK: - Initialization

    public init(logger: Logger = Logger(label: "SwiftIndexMCP")) {
        self.logger = logger

        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        decoder = JSONDecoder()

        // Register default tools
        initializeDefaultTools()
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

    private nonisolated func initializeDefaultTools() {
        // Default tools are registered lazily via registerTool
    }

    private func registerDefaultTools() {
        tools["index_codebase"] = IndexCodebaseTool()
        tools["search_code"] = SearchCodeTool()
        tools["code_research"] = CodeResearchTool()
        tools["watch_codebase"] = WatchCodebaseTool()
    }

    // MARK: - Server Loop

    /// Run the MCP server, reading from stdin and writing to stdout.
    public func run() async {
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

        case "initialized":
            // This is a notification, no response needed
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
            clientInfo = MCPClientInfo(
                name: clientInfoObj["name"]?.stringValue ?? "unknown",
                version: clientInfoObj["version"]?.stringValue ?? "unknown"
            )
            logger.info("Client connected: \(clientInfo!.name) \(clientInfo!.version)")
        }

        let result = InitializeResult(
            protocolVersion: Self.protocolVersion,
            capabilities: MCPServerCapabilities(
                tools: .init(listChanged: false)
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
        return JSONRPCResponse(id: request.id, result: .null)
    }

    // MARK: - Tool Handlers

    private func handleToolsList(_ request: JSONRPCRequest) throws -> JSONRPCResponse {
        let toolDefinitions = tools.values.map(\.definition)
        let result = ToolsListResult(tools: toolDefinitions)

        let resultData = try encoder.encode(result)
        let resultValue = try decoder.decode(JSONValue.self, from: resultData)

        return JSONRPCResponse(id: request.id, result: resultValue)
    }

    private func handleToolsCall(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
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
