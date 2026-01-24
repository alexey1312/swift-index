// MARK: - MCP Protocol Types

import Foundation

// MARK: - JSON-RPC 2.0 Types

/// JSON-RPC 2.0 request message.
public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: RequestID?
    public let method: String
    public let params: JSONValue?

    public init(
        id: RequestID? = nil,
        method: String,
        params: JSONValue? = nil
    ) {
        jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 response message.
public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: RequestID?
    public let result: JSONValue?
    public let error: JSONRPCError?

    public init(
        id: RequestID?,
        result: JSONValue
    ) {
        jsonrpc = "2.0"
        self.id = id
        self.result = result
        error = nil
    }

    public init(
        id: RequestID?,
        error: JSONRPCError
    ) {
        jsonrpc = "2.0"
        self.id = id
        result = nil
        self.error = error
    }
}

/// JSON-RPC 2.0 error object.
public struct JSONRPCError: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    // Standard JSON-RPC error codes
    public static let parseError = JSONRPCError(code: -32700, message: "Parse error")
    public static let invalidRequest = JSONRPCError(code: -32600, message: "Invalid Request")
    public static let methodNotFound = JSONRPCError(code: -32601, message: "Method not found")
    public static let invalidParams = JSONRPCError(code: -32602, message: "Invalid params")
    public static let internalError = JSONRPCError(code: -32603, message: "Internal error")

    public static func methodNotFound(_ method: String) -> JSONRPCError {
        JSONRPCError(code: -32601, message: "Method not found: \(method)")
    }

    public static func invalidParams(_ message: String) -> JSONRPCError {
        JSONRPCError(code: -32602, message: message)
    }

    public static func internalError(_ message: String) -> JSONRPCError {
        JSONRPCError(code: -32603, message: message)
    }

    // MCP-specific error codes (2025-11-25 spec)

    /// Content exceeds size limits.
    public static let contentTooLarge = JSONRPCError(code: -32001, message: "Content too large")

    /// Request exceeded timeout.
    public static let requestTimeout = JSONRPCError(code: -32002, message: "Request timeout")

    /// Server is not initialized (received request before initialize).
    public static let serverNotInitialized = JSONRPCError(code: -32003, message: "Server not initialized")

    /// Request was cancelled via notifications/cancelled.
    public static let requestCancelled = JSONRPCError(code: -32004, message: "Request cancelled")
}

/// Request ID can be string, number, or null.
public enum RequestID: Codable, Sendable, Equatable {
    case string(String)
    case number(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .number(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                RequestID.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected string or number"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        }
    }
}

/// Generic JSON value for flexible parameter handling.
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
        } else if let objectValue = try? container.decode([String: JSONValue].self) {
            self = .object(objectValue)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unable to decode JSON value"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    // MARK: - Convenience Accessors

    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        if case let .int(value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case let .double(value) = self { return value }
        if case let .int(value) = self { return Double(value) }
        return nil
    }

    public var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        if case let .object(dict) = self {
            return dict[key]
        }
        return nil
    }

    public subscript(index: Int) -> JSONValue? {
        if case let .array(arr) = self, index >= 0, index < arr.count {
            return arr[index]
        }
        return nil
    }
}

// MARK: - JSONValue ExpressibleBy Conformances

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - MCP Protocol Types

/// MCP server capabilities (2025-11-25 spec).
public struct MCPServerCapabilities: Codable, Sendable {
    public let tools: ToolsCapability?
    public let resources: ResourcesCapability?
    public let prompts: PromptsCapability?
    public let tasks: TasksCapability?

    public init(
        tools: ToolsCapability? = nil,
        resources: ResourcesCapability? = nil,
        prompts: PromptsCapability? = nil,
        tasks: TasksCapability? = nil
    ) {
        self.tools = tools
        self.resources = resources
        self.prompts = prompts
        self.tasks = tasks
    }

    public struct ToolsCapability: Codable, Sendable {
        public let listChanged: Bool?

        public init(listChanged: Bool? = nil) {
            self.listChanged = listChanged
        }
    }

    public struct ResourcesCapability: Codable, Sendable {
        public let subscribe: Bool?
        public let listChanged: Bool?

        public init(subscribe: Bool? = nil, listChanged: Bool? = nil) {
            self.subscribe = subscribe
            self.listChanged = listChanged
        }
    }

    public struct PromptsCapability: Codable, Sendable {
        public let listChanged: Bool?

        public init(listChanged: Bool? = nil) {
            self.listChanged = listChanged
        }
    }
}

/// MCP server information (2025-11-25 spec).
public struct MCPServerInfo: Codable, Sendable {
    public let name: String
    public let version: String
    public let icons: [MCPIcon]?

    public init(name: String, version: String, icons: [MCPIcon]? = nil) {
        self.name = name
        self.version = version
        self.icons = icons
    }
}

/// Icon for visual identification (2025-11-25 spec).
public struct MCPIcon: Codable, Sendable {
    /// Icon source - URL or data URI.
    public let src: String

    /// MIME type of the icon (e.g., "image/svg+xml", "image/png").
    public let mimeType: String?

    /// Size specifications (e.g., ["48x48", "any"]).
    public let sizes: [String]?

    /// Theme variant ("light" or "dark").
    public let theme: String?

    public init(
        src: String,
        mimeType: String? = nil,
        sizes: [String]? = nil,
        theme: String? = nil
    ) {
        self.src = src
        self.mimeType = mimeType
        self.sizes = sizes
        self.theme = theme
    }
}

/// MCP client information.
public struct MCPClientInfo: Codable, Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

/// Initialize request parameters.
public struct InitializeParams: Codable, Sendable {
    public let protocolVersion: String
    public let capabilities: MCPClientCapabilities
    public let clientInfo: MCPClientInfo

    public init(
        protocolVersion: String,
        capabilities: MCPClientCapabilities,
        clientInfo: MCPClientInfo
    ) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.clientInfo = clientInfo
    }
}

/// MCP client capabilities.
public struct MCPClientCapabilities: Codable, Sendable {
    public let roots: RootsCapability?
    public let sampling: SamplingCapability?

    public init(
        roots: RootsCapability? = nil,
        sampling: SamplingCapability? = nil
    ) {
        self.roots = roots
        self.sampling = sampling
    }

    public struct RootsCapability: Codable, Sendable {
        public let listChanged: Bool?

        public init(listChanged: Bool? = nil) {
            self.listChanged = listChanged
        }
    }

    public struct SamplingCapability: Codable, Sendable {
        public init() {}
    }
}

/// Initialize result.
public struct InitializeResult: Codable, Sendable {
    public let protocolVersion: String
    public let capabilities: MCPServerCapabilities
    public let serverInfo: MCPServerInfo

    public init(
        protocolVersion: String,
        capabilities: MCPServerCapabilities,
        serverInfo: MCPServerInfo
    ) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.serverInfo = serverInfo
    }
}

// MARK: - Tool Types

/// MCP tool definition (2025-11-25 spec).
public struct MCPTool: Codable, Sendable {
    public let name: String
    public let title: String?
    public let description: String
    public let inputSchema: JSONValue
    public let outputSchema: JSONValue?
    public let annotations: ToolAnnotations?

    public init(
        name: String,
        title: String? = nil,
        description: String,
        inputSchema: JSONValue,
        outputSchema: JSONValue? = nil,
        annotations: ToolAnnotations? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.annotations = annotations
    }
}

/// Tool behavior annotations (2025-11-25 spec).
///
/// Hints that help clients understand tool behavior without executing them.
/// All fields are optional and clients should handle missing values gracefully.
public struct ToolAnnotations: Codable, Sendable {
    /// If true, the tool does not modify any state and only reads/retrieves data.
    public let readOnlyHint: Bool?

    /// If true, the tool may perform destructive operations (data loss, irreversible changes).
    public let destructiveHint: Bool?

    /// If true, calling the tool multiple times with same arguments has same effect as once.
    public let idempotentHint: Bool?

    /// If true, the tool may interact with external systems beyond the local environment.
    public let openWorldHint: Bool?

    public init(
        readOnlyHint: Bool? = nil,
        destructiveHint: Bool? = nil,
        idempotentHint: Bool? = nil,
        openWorldHint: Bool? = nil
    ) {
        self.readOnlyHint = readOnlyHint
        self.destructiveHint = destructiveHint
        self.idempotentHint = idempotentHint
        self.openWorldHint = openWorldHint
    }
}

/// Tools list result.
public struct ToolsListResult: Codable, Sendable {
    public let tools: [MCPTool]

    public init(tools: [MCPTool]) {
        self.tools = tools
    }
}

/// Tool call parameters.
public struct ToolCallParams: Codable, Sendable {
    public let name: String
    public let arguments: JSONValue?

    public init(name: String, arguments: JSONValue? = nil) {
        self.name = name
        self.arguments = arguments
    }
}

/// Tool call result (2025-11-25 spec).
public struct ToolCallResult: Codable, Sendable {
    public let content: [ToolResultContent]
    public let structuredContent: JSONValue?
    public let isError: Bool?

    public init(
        content: [ToolResultContent],
        structuredContent: JSONValue? = nil,
        isError: Bool? = nil
    ) {
        self.content = content
        self.structuredContent = structuredContent
        self.isError = isError
    }

    public static func text(_ text: String) -> ToolCallResult {
        ToolCallResult(content: [.text(TextContent(text: text))])
    }

    public static func error(_ message: String) -> ToolCallResult {
        ToolCallResult(content: [.text(TextContent(text: message))], isError: true)
    }

    /// Creates a result with both human-readable text and structured JSON data.
    public static func structured(_ text: String, data: JSONValue) -> ToolCallResult {
        ToolCallResult(
            content: [.text(TextContent(text: text))],
            structuredContent: data
        )
    }
}

/// Tool result content types (2025-11-25 spec).
public enum ToolResultContent: Codable, Sendable {
    case text(TextContent)
    case image(ImageContent)
    case audio(AudioContent)
    case resource(ResourceContent)
    case resourceLink(ResourceLinkContent)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = try .text(TextContent(from: decoder))
        case "image":
            self = try .image(ImageContent(from: decoder))
        case "audio":
            self = try .audio(AudioContent(from: decoder))
        case "resource":
            self = try .resource(ResourceContent(from: decoder))
        case "resource_link":
            self = try .resourceLink(ResourceLinkContent(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .text(content):
            try content.encode(to: encoder)
        case let .image(content):
            try content.encode(to: encoder)
        case let .audio(content):
            try content.encode(to: encoder)
        case let .resource(content):
            try content.encode(to: encoder)
        case let .resourceLink(content):
            try content.encode(to: encoder)
        }
    }
}

/// Content annotations for targeting and prioritization (2025-11-25 spec).
public struct ContentAnnotations: Codable, Sendable {
    /// Target audience for this content (e.g., ["user", "assistant"]).
    public let audience: [String]?

    /// Priority hint (0.0 = lowest, 1.0 = highest).
    public let priority: Double?

    /// Last modified timestamp (ISO 8601 format).
    public let lastModified: String?

    public init(
        audience: [String]? = nil,
        priority: Double? = nil,
        lastModified: String? = nil
    ) {
        self.audience = audience
        self.priority = priority
        self.lastModified = lastModified
    }
}

/// Text content for tool results.
public struct TextContent: Codable, Sendable {
    public let type: String
    public let text: String
    public let annotations: ContentAnnotations?

    public init(text: String, annotations: ContentAnnotations? = nil) {
        type = "text"
        self.text = text
        self.annotations = annotations
    }
}

/// Image content for tool results.
public struct ImageContent: Codable, Sendable {
    public let type: String
    public let data: String
    public let mimeType: String
    public let annotations: ContentAnnotations?

    public init(data: String, mimeType: String, annotations: ContentAnnotations? = nil) {
        type = "image"
        self.data = data
        self.mimeType = mimeType
        self.annotations = annotations
    }
}

/// Resource content for tool results.
public struct ResourceContent: Codable, Sendable {
    public let type: String
    public let resource: ResourceReference
    public let annotations: ContentAnnotations?

    public init(resource: ResourceReference, annotations: ContentAnnotations? = nil) {
        type = "resource"
        self.resource = resource
        self.annotations = annotations
    }
}

/// Audio content for tool results (2025-11-25 spec).
public struct AudioContent: Codable, Sendable {
    public let type: String
    public let data: String
    public let mimeType: String
    public let annotations: ContentAnnotations?

    public init(data: String, mimeType: String, annotations: ContentAnnotations? = nil) {
        type = "audio"
        self.data = data
        self.mimeType = mimeType
        self.annotations = annotations
    }
}

/// Resource reference.
public struct ResourceReference: Codable, Sendable {
    public let uri: String
    public let mimeType: String?
    public let text: String?

    public init(uri: String, mimeType: String? = nil, text: String? = nil) {
        self.uri = uri
        self.mimeType = mimeType
        self.text = text
    }
}

/// Resource link content (2025-11-25 spec).
public struct ResourceLinkContent: Codable, Sendable {
    public let type: String
    public let uri: String
    public let name: String?
    public let description: String?
    public let mimeType: String?
    public let annotations: ContentAnnotations?

    public init(
        uri: String,
        name: String? = nil,
        description: String? = nil,
        mimeType: String? = nil,
        annotations: ContentAnnotations? = nil
    ) {
        type = "resource_link"
        self.uri = uri
        self.name = name
        self.description = description
        self.mimeType = mimeType
        self.annotations = annotations
    }
}
