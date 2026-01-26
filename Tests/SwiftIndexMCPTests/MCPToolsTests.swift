// MARK: - MCP Tools Tests

import Foundation
@testable import SwiftIndexCore
@testable import SwiftIndexMCP
import Testing

private func createTestFixtures() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftindex-mcp-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let swiftFile = dir.appendingPathComponent("Sample.swift")
    try """
    // Sample Swift file for testing
    import Foundation

    struct Sample {
        let name: String

        func greet() -> String {
            return "Hello, \\(name)!"
        }
    }
    """.write(to: swiftFile, atomically: true, encoding: .utf8)

    let configFile = dir.appendingPathComponent(".swiftindex.toml")
    try """
    [embedding]
    provider = "mock"
    model = "all-MiniLM-L6-v2"
    dimension = 384
    """.write(to: configFile, atomically: true, encoding: .utf8)

    return dir
}

private func prepareIndexedFixtures() async throws -> URL {
    let dir = try createTestFixtures()
    let tool = IndexCodebaseTool()
    let result = try await tool.execute(arguments: .object([
        "path": .string(dir.path),
        "force": true,
    ]))
    if result.isError == true {
        throw NSError(domain: "MCPToolsTests", code: 1)
    }
    return dir
}

private func cleanupFixtures(_ dir: URL) {
    try? FileManager.default.removeItem(at: dir)
}

private func extractTaskId(from jsonString: String) -> String? {
    guard let data = jsonString.data(using: .utf8),
          let json = try? JSONCodec.deserialize(data) as? [String: Any],
          let taskId = json["task_id"] as? String
    else {
        return nil
    }
    return taskId
}

private func extractRetryAfterMs(from jsonString: String) -> Int? {
    guard let data = jsonString.data(using: .utf8),
          let json = try? JSONCodec.deserialize(data) as? [String: Any],
          let retryAfter = json["retry_after_ms"] as? Int
    else {
        return nil
    }
    return retryAfter
}

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
            let fixtureDir = try await prepareIndexedFixtures()
            defer { cleanupFixtures(fixtureDir) }

            let result = try await tool.execute(
                arguments: .object(["path": .string(fixtureDir.path)])
            )

            if case let .text(content) = result.content.first {
                #expect(content.text.contains("indexed_files") || content.text.contains("path"))
            }
        }

        @Test("Tool definition includes async parameter")
        func toolDefinitionIncludesAsyncParam() {
            let schema = tool.definition.inputSchema
            let properties = schema["properties"]?.objectValue
            #expect(properties?["async"] != nil)
        }

        @Test("Execute with async=true returns task_id immediately")
        func executeAsyncReturnsTaskId() async throws {
            let fixtureDir = try createTestFixtures()
            defer { cleanupFixtures(fixtureDir) }

            let result = try await tool.execute(
                arguments: .object([
                    "path": .string(fixtureDir.path),
                    "async": true,
                ])
            )

            #expect(result.isError != true)
            if case let .text(content) = result.content.first {
                #expect(content.text.contains("task_id"))
                #expect(content.text.contains("started"))
            }
        }

        @Test("Tool definition includes poll_interval parameter")
        func toolDefinitionIncludesPollIntervalParam() {
            let schema = tool.definition.inputSchema
            let properties = schema["properties"]?.objectValue
            #expect(properties?["poll_interval"] != nil)

            let pollIntervalSchema = properties?["poll_interval"]?.objectValue
            #expect(pollIntervalSchema?["type"]?.stringValue == "integer")
            #expect(pollIntervalSchema?["minimum"]?.intValue == 1000)
            #expect(pollIntervalSchema?["maximum"]?.intValue == 300_000)
        }

        @Test("Execute with custom poll_interval sets task pollInterval")
        func executeWithCustomPollInterval() async throws {
            let fixtureDir = try createTestFixtures()
            defer { cleanupFixtures(fixtureDir) }

            let customInterval = 5000

            let result = try await tool.execute(
                arguments: .object([
                    "path": .string(fixtureDir.path),
                    "async": true,
                    "poll_interval": .int(customInterval),
                ])
            )

            #expect(result.isError != true)
            guard case let .text(content) = result.content.first,
                  let taskId = extractTaskId(from: content.text)
            else {
                Issue.record("Could not extract task_id from result")
                return
            }

            // Check that the task has the custom poll interval
            let taskManager = MCPContext.shared.taskManager
            let task = await taskManager.getTask(taskId)
            #expect(task?.pollInterval == customInterval)
        }

        @Test("Dynamic poll interval is based on file count")
        func dynamicPollIntervalBasedOnFileCount() async throws {
            let fixtureDir = try createTestFixtures()
            defer { cleanupFixtures(fixtureDir) }

            // Fixture has 1 file, so dynamic interval = max(10000, 1 * 100) = 10000
            let result = try await tool.execute(
                arguments: .object([
                    "path": .string(fixtureDir.path),
                    "async": true,
                ])
            )

            #expect(result.isError != true)
            guard case let .text(content) = result.content.first,
                  let taskId = extractTaskId(from: content.text)
            else {
                Issue.record("Could not extract task_id from result")
                return
            }

            let taskManager = MCPContext.shared.taskManager
            let task = await taskManager.getTask(taskId)
            // Small project should get minimum interval (10 seconds)
            #expect(task?.pollInterval == 10000)
        }
    }

    // MARK: - CheckIndexingStatusTool Tests

    @Suite("CheckIndexingStatusTool")
    struct CheckIndexingStatusToolTests {
        let tool = CheckIndexingStatusTool()

        @Test("Tool definition has correct name")
        func toolDefinitionName() {
            #expect(tool.definition.name == "check_indexing_status")
        }

        @Test("Tool definition has description")
        func toolDefinitionDescription() {
            #expect(!tool.definition.description.isEmpty)
            #expect(tool.definition.description.contains("status"))
        }

        @Test("Tool definition has task_id required")
        func toolDefinitionSchema() {
            let schema = tool.definition.inputSchema
            #expect(schema["type"]?.stringValue == "object")
            #expect(schema["required"]?.arrayValue?.contains(.string("task_id")) == true)
        }

        @Test("Tool has read-only annotation")
        func toolIsReadOnly() {
            #expect(tool.definition.annotations?.readOnlyHint == true)
        }

        @Test("Execute with missing task_id returns error")
        func executeWithMissingTaskIdReturnsError() async throws {
            let result = try await tool.execute(arguments: .object([:]))

            if case let .text(content) = result.content.first {
                #expect(content.text.contains("Missing") || content.text.contains("task_id"))
            }
        }

        @Test("Execute with invalid task_id returns not found")
        func executeWithInvalidTaskIdReturnsNotFound() async throws {
            let result = try await tool.execute(
                arguments: .object(["task_id": "invalid-task-id-12345"])
            )

            if case let .text(content) = result.content.first {
                #expect(content.text.contains("not found") || content.text.contains("expired"))
            }
        }

        @Test("Execute returns progress for valid task")
        func executeReturnsProgressForValidTask() async throws {
            let fixtureDir = try createTestFixtures()
            defer { cleanupFixtures(fixtureDir) }

            // Start async indexing
            let indexTool = IndexCodebaseTool()
            let startResult = try await indexTool.execute(
                arguments: .object([
                    "path": .string(fixtureDir.path),
                    "async": true,
                ])
            )

            // Extract task_id from result
            guard case let .text(content) = startResult.content.first,
                  let taskId = extractTaskId(from: content.text)
            else {
                Issue.record("Could not extract task_id from result")
                return
            }

            // Wait a moment for indexing to start
            try await Task.sleep(for: .milliseconds(100))

            // Check status
            let statusResult = try await tool.execute(
                arguments: .object(["task_id": .string(taskId)])
            )

            #expect(statusResult.isError != true)
            if case let .text(statusContent) = statusResult.content.first {
                #expect(
                    statusContent.text.contains("working") ||
                        statusContent.text.contains("completed") ||
                        statusContent.text.contains("task_id")
                )
            }
        }

        @Test("retry_after_ms uses task pollInterval")
        func retryAfterMsUsesTaskPollInterval() async throws {
            let fixtureDir = try createTestFixtures()
            defer { cleanupFixtures(fixtureDir) }

            let customInterval = 15000

            // Start async indexing with custom poll interval
            let indexTool = IndexCodebaseTool()
            let startResult = try await indexTool.execute(
                arguments: .object([
                    "path": .string(fixtureDir.path),
                    "async": true,
                    "poll_interval": .int(customInterval),
                ])
            )

            guard case let .text(content) = startResult.content.first,
                  let taskId = extractTaskId(from: content.text)
            else {
                Issue.record("Could not extract task_id from result")
                return
            }

            // Check status while task is working
            try await Task.sleep(for: .milliseconds(50))

            let statusResult = try await tool.execute(
                arguments: .object(["task_id": .string(taskId)])
            )

            #expect(statusResult.isError != true)
            if case let .text(statusContent) = statusResult.content.first {
                // Should return the custom poll interval as retry_after_ms
                if let retryAfter = extractRetryAfterMs(from: statusContent.text) {
                    #expect(retryAfter == customInterval)
                }
            }
        }

        @Test("retry_after_ms defaults to 10000 when pollInterval is nil")
        func retryAfterMsDefaultsTo10000() async throws {
            // Create a task directly without poll interval
            let taskManager = MCPContext.shared.taskManager
            let task = await taskManager.createTask(ttl: 60000, pollInterval: nil)

            // Update to working status
            await taskManager.updateStatus(task.taskId, status: .working, message: nil)

            let statusResult = try await tool.execute(
                arguments: .object(["task_id": .string(task.taskId)])
            )

            #expect(statusResult.isError != true)
            if case let .text(statusContent) = statusResult.content.first {
                if let retryAfter = extractRetryAfterMs(from: statusContent.text) {
                    #expect(retryAfter == 10000)
                }
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
            let fixtureDir = try await prepareIndexedFixtures()
            defer { cleanupFixtures(fixtureDir) }

            let result = try await tool.execute(
                arguments: .object([
                    "query": "authentication",
                    "limit": 5,
                    "path": .string(fixtureDir.path),
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
            let fixtureDir = try await prepareIndexedFixtures()
            defer { cleanupFixtures(fixtureDir) }

            let result = try await tool.execute(
                arguments: .object([
                    "query": "how does search work",
                    "depth": 2,
                    "focus": "architecture",
                    "path": .string(fixtureDir.path),
                ])
            )

            #expect(result.isError != true)
            if case let .text(content) = result.content.first {
                #expect(content.text.contains("analysis") || content.text.contains("references"))
            }
        }
    }
}
