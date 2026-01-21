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

/// MCP server capabilities.
public struct MCPServerCapabilities: Codable, Sendable {
    public let tools: ToolsCapability?
    public let resources: ResourcesCapability?
    public let prompts: PromptsCapability?

    public init(
        tools: ToolsCapability? = nil,
        resources: ResourcesCapability? = nil,
        prompts: PromptsCapability? = nil
    ) {
        self.tools = tools
        self.resources = resources
        self.prompts = prompts
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

/// MCP server information.
public struct MCPServerInfo: Codable, Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
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

/// MCP tool definition.
public struct MCPTool: Codable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
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

/// Tool call result.
public struct ToolCallResult: Codable, Sendable {
    public let content: [ToolResultContent]
    public let isError: Bool?

    public init(content: [ToolResultContent], isError: Bool? = nil) {
        self.content = content
        self.isError = isError
    }

    public static func text(_ text: String) -> ToolCallResult {
        ToolCallResult(content: [.text(TextContent(text: text))])
    }

    public static func error(_ message: String) -> ToolCallResult {
        ToolCallResult(content: [.text(TextContent(text: message))], isError: true)
    }
}

/// Tool result content types.
public enum ToolResultContent: Codable, Sendable {
    case text(TextContent)
    case image(ImageContent)
    case resource(ResourceContent)

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
        case "resource":
            self = try .resource(ResourceContent(from: decoder))
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
        case let .resource(content):
            try content.encode(to: encoder)
        }
    }
}

/// Text content for tool results.
public struct TextContent: Codable, Sendable {
    public let type: String
    public let text: String

    public init(text: String) {
        type = "text"
        self.text = text
    }
}

/// Image content for tool results.
public struct ImageContent: Codable, Sendable {
    public let type: String
    public let data: String
    public let mimeType: String

    public init(data: String, mimeType: String) {
        type = "image"
        self.data = data
        self.mimeType = mimeType
    }
}

/// Resource content for tool results.
public struct ResourceContent: Codable, Sendable {
    public let type: String
    public let resource: ResourceReference

    public init(resource: ResourceReference) {
        type = "resource"
        self.resource = resource
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
