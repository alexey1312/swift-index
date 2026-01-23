// MARK: - MCP Server Tool Ordering Tests

@testable import SwiftIndexMCP
import Testing

@Suite("MCP Server Tool Ordering")
struct MCPServerToolOrderingTests {
    @Test("Tools list preserves registration order")
    func toolsListPreservesRegistrationOrder() async throws {
        let server = MCPServer()

        await server.registerTool(TestTool(name: "alpha"))
        await server.registerTool(TestTool(name: "beta"))
        await server.registerTool(TestTool(name: "gamma"))

        let tools = await server.toolDefinitionsForTesting()
        let names = tools.map(\.name)

        #expect(names == ["alpha", "beta", "gamma"])
    }

    @Test("Updating an existing tool keeps its position")
    func updatingToolKeepsPosition() async throws {
        let server = MCPServer()

        await server.registerTool(TestTool(name: "first"))
        await server.registerTool(TestTool(name: "second"))
        await server.registerTool(TestTool(name: "first"))

        let tools = await server.toolDefinitionsForTesting()
        let names = tools.map(\.name)

        #expect(names == ["first", "second"])
    }
}

private struct TestTool: MCPToolHandler {
    let name: String

    var definition: MCPTool {
        MCPTool(
            name: name,
            description: "test tool",
            inputSchema: .object(["type": "object"])
        )
    }

    func execute(arguments: JSONValue) async throws -> ToolCallResult {
        .text("ok")
    }
}
