import Foundation
@testable import SwiftIndexCore
@testable import SwiftIndexMCP
import Testing

private func makeFixture() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftindex-mcp-writer-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try """
    import Foundation

    struct Sample {
        let name: String

        func greet() -> String {
            return "Hello, \\(name)!"
        }
    }
    """.write(to: dir.appendingPathComponent("Sample.swift"), atomically: true, encoding: .utf8)
    try """
    [embedding]
    provider = "mock"
    model = "all-MiniLM-L6-v2"
    dimension = 384
    """.write(to: dir.appendingPathComponent(".swiftindex.toml"), atomically: true, encoding: .utf8)
    return dir
}

private func makeIndexedFixture() async throws -> URL {
    let dir = try makeFixture()
    let result = try await IndexCodebaseTool().execute(arguments: .object([
        "path": .string(dir.path),
        "force": true,
        "async": false,
    ]))
    try #require(result.isError != true)
    return dir
}

private func text(of result: ToolCallResult) -> String {
    guard case let .text(content) = result.content.first else { return "" }
    return content.text
}

@Suite("MCP writer role and graph tools")
struct MCPWriterRoleAndGraphToolTests {
    @Test("index_codebase reports a conflict while another lock holds the index")
    func indexCodebaseReportsConflict() async throws {
        let dir = try makeFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let indexDirectory = dir.appendingPathComponent(".swiftindex").path
        let external = try #require(try IndexWriterLock.acquire(indexDirectory: indexDirectory))
        defer { external.release() }

        let result = try await IndexCodebaseTool().execute(arguments: .object([
            "path": .string(dir.path),
            "async": false,
        ]))

        #expect(result.isError == true)
        #expect(text(of: result).contains("writes this index"))
    }

    @Test("A reader becomes the writer after the lock is released")
    func readerTakesOverWriterRole() async throws {
        let dir = try makeFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let context = MCPContext.shared
        let config = try await context.getConfig(for: dir.path)
        let indexDirectory = dir.appendingPathComponent(config.indexPath).path
        let external = try #require(try IndexWriterLock.acquire(indexDirectory: indexDirectory))

        #expect(await context.acquireWriterRole(for: dir.path, config: config) == false)
        external.release()
        #expect(await context.acquireWriterRole(for: dir.path, config: config) == true)
    }

    @Test("explore returns line-numbered source")
    func exploreReturnsLineNumberedSource() async throws {
        let dir = try await makeIndexedFixture()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = try await ExploreTool().execute(arguments: .object([
            "query": "greet",
            "path": .string(dir.path),
        ]))

        #expect(result.isError != true)
        let output = text(of: result)
        #expect(output.contains(#/\d+\tstruct Sample/#))
        #expect(output.contains(#/\d+\t +func greet/#))
    }

    @Test("code_graph dead_code works without symbol")
    func deadCodeWithoutSymbol() async throws {
        let dir = try await makeIndexedFixture()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = try await CodeGraphTool().execute(arguments: .object([
            "relation": "dead_code",
            "path": .string(dir.path),
        ]))

        #expect(result.isError != true)
    }

    @Test("code_graph relations other than dead_code require symbol", arguments: [
        "callers", "callees", "impact", "paths", "neighborhood",
    ])
    func otherRelationsRequireSymbol(relation: String) async throws {
        let result = try await CodeGraphTool().execute(arguments: .object([
            "relation": .string(relation),
            "path": ".",
        ]))

        #expect(result.isError == true)
        #expect(text(of: result).contains("Missing required argument: symbol"))
    }
}
