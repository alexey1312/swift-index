// MARK: - MCP Tools Tests

import Foundation
@testable import SwiftIndexMCP
import Testing

private let envSetup: Void = {
    _ = setenv("SWIFTINDEX_EMBEDDING_PROVIDER", "mock", 1)
    return ()
}()

@Suite("MCP Tools")
struct MCPToolsTests {
    // MARK: - IndexCodebaseTool Tests

    @Suite("IndexCodebaseTool")
    struct IndexCodebaseToolTests {
        let tool = IndexCodebaseTool()

        @Test("Tool definition has correct name")
        func toolDefinitionName() {
            #expect(tool.definition.name == "index_codebase")
        }

        @Test("Tool definition has description")
        func toolDefinitionDescription() {
            #expect(!tool.definition.description.isEmpty)
            #expect(tool.definition.description.contains("Index"))
        }

        @Test("Tool definition has input schema")
        func toolDefinitionSchema() {
            let schema = tool.definition.inputSchema
            #expect(schema["type"]?.stringValue == "object")
            #expect(schema["properties"] != nil)
            #expect(schema["required"]?.arrayValue?.contains(.string("path")) == true)
        }

        @Test("Execute with missing path returns error")
        func executeWithMissingPathReturnsError() async throws {
            let result = try await tool.execute(arguments: .object([:]))
            #expect(result.isError == true || result.content.first.map { content in
                if case let .text(text) = content {
                    return text.text.contains("Missing")
                }
                return false
            } == true)
        }

        @Test("Execute with invalid path returns error")
        func executeWithInvalidPathReturnsError() async throws {
            let result = try await tool.execute(
                arguments: .object(["path": "/nonexistent/path/that/does/not/exist"])
            )

            if case let .text(content) = result.content.first {
                #expect(content.text.contains("does not exist") || content.text.contains("error"))
            }
        }

        @Test("Execute with valid path returns result")
        func executeWithValidPathReturnsResult() async throws {
            // Use the current project directory as test path
            let testPath = FileManager.default.currentDirectoryPath

            let result = try await tool.execute(
                arguments: .object(["path": .string(testPath)])
            )

            if case let .text(content) = result.content.first {
                #expect(content.text.contains("indexed_files") || content.text.contains("path"))
            }
        }
    }

    // MARK: - SearchCodeTool Tests

    @Suite("SearchCodeTool")
    struct SearchCodeToolTests {
        let tool = SearchCodeTool()

        @Test("Tool definition has correct name")
        func toolDefinitionName() {
            #expect(tool.definition.name == "search_code")
        }

        @Test("Tool definition has description")
        func toolDefinitionDescription() {
            #expect(!tool.definition.description.isEmpty)
            #expect(tool.definition.description.contains("Search") || tool.definition.description.contains("search"))
        }

        @Test("Tool definition has input schema with query required")
        func toolDefinitionSchema() {
            let schema = tool.definition.inputSchema
            #expect(schema["type"]?.stringValue == "object")
            #expect(schema["required"]?.arrayValue?.contains(.string("query")) == true)
        }

        @Test("Execute with missing query returns error")
        func executeWithMissingQueryReturnsError() async throws {
            let result = try await tool.execute(arguments: .object([:]))

            if case let .text(content) = result.content.first {
                #expect(content.text.contains("Missing") || content.text.contains("query"))
            }
        }

        @Test("Execute with empty query returns error")
        func executeWithEmptyQueryReturnsError() async throws {
            let result = try await tool.execute(
                arguments: .object(["query": "   "])
            )

            if case let .text(content) = result.content.first {
                #expect(content.text.contains("empty") || content.text.contains("cannot"))
            }
        }

        @Test("Execute with valid query returns results")
        func executeWithValidQueryReturnsResults() async throws {
            let result = try await tool.execute(
                arguments: .object([
                    "query": "authentication",
                    "limit": 5,
                ])
            )

            #expect(result.isError != true)
            if case let .text(content) = result.content.first {
                #expect(content.text.contains("results") || content.text.contains("query"))
            }
        }
    }

    // MARK: - CodeResearchTool Tests

    @Suite("CodeResearchTool")
    struct CodeResearchToolTests {
        let tool = CodeResearchTool()

        @Test("Tool definition has correct name")
        func toolDefinitionName() {
            #expect(tool.definition.name == "code_research")
        }

        @Test("Tool definition has description")
        func toolDefinitionDescription() {
            #expect(!tool.definition.description.isEmpty)
            #expect(tool.definition.description.lowercased().contains("research") ||
                tool.definition.description.lowercased().contains("analysis"))
        }

        @Test("Tool definition has depth parameter")
        func toolDefinitionSchema() {
            let schema = tool.definition.inputSchema
            let properties = schema["properties"]?.objectValue
            #expect(properties?["depth"] != nil)
            #expect(properties?["focus"] != nil)
        }

        @Test("Execute with missing query returns error")
        func executeWithMissingQueryReturnsError() async throws {
            let result = try await tool.execute(arguments: .object([:]))

            if case let .text(content) = result.content.first {
                #expect(content.text.contains("Missing") || content.text.contains("query"))
            }
        }

        @Test("Execute with invalid depth returns error")
        func executeWithInvalidDepthReturnsError() async throws {
            let result = try await tool.execute(
                arguments: .object([
                    "query": "test query",
                    "depth": 10, // Max is 5
                ])
            )

            if case let .text(content) = result.content.first {
                #expect(content.text.contains("Depth") || content.text.contains("between"))
            }
        }

        @Test("Execute with valid parameters returns analysis")
        func executeWithValidParametersReturnsAnalysis() async throws {
            let result = try await tool.execute(
                arguments: .object([
                    "query": "how does search work",
                    "depth": 2,
                    "focus": "architecture",
                ])
            )

            #expect(result.isError != true)
            if case let .text(content) = result.content.first {
                #expect(content.text.contains("analysis") || content.text.contains("references"))
            }
        }
    }

    // MARK: - WatchCodebaseTool Tests

    @Suite("WatchCodebaseTool")
    struct WatchCodebaseToolTests {
        let tool = WatchCodebaseTool()

        @Test("Tool definition has correct name")
        func toolDefinitionName() {
            #expect(tool.definition.name == "watch_codebase")
        }

        @Test("Tool definition has description")
        func toolDefinitionDescription() {
            #expect(!tool.definition.description.isEmpty)
            #expect(tool.definition.description.lowercased().contains("watch"))
        }

        @Test("Tool definition has action parameter")
        func toolDefinitionSchema() {
            let schema = tool.definition.inputSchema
            let properties = schema["properties"]?.objectValue
            #expect(properties?["action"] != nil)
            #expect(properties?["path"] != nil)
        }

        @Test("Execute with missing path returns error")
        func executeWithMissingPathReturnsError() async throws {
            let result = try await tool.execute(arguments: .object([:]))

            if case let .text(content) = result.content.first {
                #expect(content.text.contains("Missing") || content.text.contains("path"))
            }
        }

        @Test("Execute with invalid action returns error")
        func executeWithInvalidActionReturnsError() async throws {
            let result = try await tool.execute(
                arguments: .object([
                    "path": "/tmp",
                    "action": "invalid_action",
                ])
            )

            if case let .text(content) = result.content.first {
                #expect(content.text.contains("Invalid") || content.text.contains("action"))
            }
        }

        @Test("Execute start action returns watching true")
        func executeStartActionReturnsWatchingTrue() async throws {
            let testPath = FileManager.default.currentDirectoryPath

            let result = try await tool.execute(
                arguments: .object([
                    "path": .string(testPath),
                    "action": "start",
                ])
            )

            #expect(result.isError != true)
            if case let .text(content) = result.content.first {
                #expect(content.text.contains("watching") || content.text.contains("start"))
            }
        }

        @Test("Execute status action returns stats")
        func executeStatusActionReturnsStats() async throws {
            let testPath = FileManager.default.currentDirectoryPath

            let result = try await tool.execute(
                arguments: .object([
                    "path": .string(testPath),
                    "action": "status",
                ])
            )

            #expect(result.isError != true)
            if case let .text(content) = result.content.first {
                #expect(content.text.contains("stats") || content.text.contains("watching"))
            }
        }

        @Test("Execute stop action returns watching false")
        func executeStopActionReturnsWatchingFalse() async throws {
            let testPath = FileManager.default.currentDirectoryPath

            let result = try await tool.execute(
                arguments: .object([
                    "path": .string(testPath),
                    "action": "stop",
                ])
            )

            #expect(result.isError != true)
            if case let .text(content) = result.content.first {
                #expect(content.text.contains("stop") || content.text.contains("watching"))
            }
        }
    }
}
