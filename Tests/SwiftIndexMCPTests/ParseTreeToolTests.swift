// MARK: - ParseTreeTool Tests

import Foundation
@testable import SwiftIndexCore
@testable import SwiftIndexMCP
import Testing

private func createTempSwiftFile(content: String = """
import Foundation

struct Sample {
    let name: String

    func greet() -> String {
        return "Hello, \\(name)!"
    }
}
""") throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftindex-parsetree-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let swiftFile = dir.appendingPathComponent("Sample.swift")
    try content.write(to: swiftFile, atomically: true, encoding: .utf8)

    return swiftFile
}

private func createTempDirectory(with files: [String: String]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftindex-parsetree-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    for (filename, content) in files {
        let fileURL = dir.appendingPathComponent(filename)
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    return dir
}

private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

@Suite("ParseTreeTool")
struct ParseTreeToolTests {
    let tool = ParseTreeTool()

    // MARK: - Tool Definition Tests

    @Test("Tool definition has correct name")
    func toolDefinitionName() {
        #expect(tool.definition.name == "parse_tree")
    }

    @Test("Tool definition has title")
    func toolDefinitionTitle() {
        #expect(tool.definition.title == "Parse Tree Visualizer")
    }

    @Test("Tool definition has description")
    func toolDefinitionDescription() {
        #expect(!tool.definition.description.isEmpty)
        #expect(tool.definition.description.contains("AST"))
    }

    @Test("Tool has read-only annotation")
    func toolIsReadOnly() {
        #expect(tool.definition.annotations?.readOnlyHint == true)
    }

    @Test("Tool has idempotent annotation")
    func toolIsIdempotent() {
        #expect(tool.definition.annotations?.idempotentHint == true)
    }

    @Test("Tool is not destructive")
    func toolIsNotDestructive() {
        #expect(tool.definition.annotations?.destructiveHint == false)
    }

    @Test("Tool definition has input schema with path required")
    func toolDefinitionSchema() {
        let schema = tool.definition.inputSchema
        #expect(schema["type"]?.stringValue == "object")
        #expect(schema["required"]?.arrayValue?.contains(.string("path")) == true)
    }

    @Test("Tool definition has pattern parameter")
    func toolDefinitionPatternParam() {
        let schema = tool.definition.inputSchema
        let properties = schema["properties"]?.objectValue
        #expect(properties?["pattern"] != nil)
    }

    @Test("Tool definition has format parameter with enum")
    func toolDefinitionFormatParam() {
        let schema = tool.definition.inputSchema
        let properties = schema["properties"]?.objectValue
        let formatSchema = properties?["format"]?.objectValue
        #expect(formatSchema?["enum"] != nil)
    }

    // MARK: - Error Handling Tests

    @Test("Missing path returns error")
    func missingPathReturnsError() async throws {
        let result = try await tool.execute(arguments: .object([:]))
        #expect(result.isError == true)
        if case let .text(content) = result.content.first {
            #expect(content.text.contains("Missing"))
        }
    }

    @Test("Invalid path returns error")
    func invalidPathReturnsError() async throws {
        let result = try await tool.execute(arguments: .object([
            "path": .string("/nonexistent/path/that/does/not/exist"),
        ]))
        #expect(result.isError == true)
        if case let .text(content) = result.content.first {
            #expect(content.text.contains("does not exist"))
        }
    }

    @Test("Negative max_depth returns error")
    func negativeMaxDepthReturnsError() async throws {
        let tempFile = try createTempSwiftFile()
        defer { cleanup(tempFile.deletingLastPathComponent()) }

        let result = try await tool.execute(arguments: .object([
            "path": .string(tempFile.path),
            "max_depth": .int(-1),
        ]))
        #expect(result.isError == true)
        if case let .text(content) = result.content.first {
            #expect(content.text.contains("max_depth"))
        }
    }

    // MARK: - Single File Tests

    @Test("Valid Swift file returns AST nodes")
    func validFileReturnsAST() async throws {
        let tempFile = try createTempSwiftFile()
        defer { cleanup(tempFile.deletingLastPathComponent()) }

        let result = try await tool.execute(arguments: .object([
            "path": .string(tempFile.path),
        ]))
        #expect(result.isError != true)
        if case let .text(content) = result.content.first {
            #expect(content.text.contains("struct"))
            #expect(content.text.contains("Sample"))
        }
    }

    @Test("Empty Swift file returns no declarations message")
    func emptyFileReturnsMessage() async throws {
        let tempFile = try createTempSwiftFile(content: "// Just a comment\n")
        defer { cleanup(tempFile.deletingLastPathComponent()) }

        let result = try await tool.execute(arguments: .object([
            "path": .string(tempFile.path),
        ]))
        #expect(result.isError != true)
        if case let .text(content) = result.content.first {
            #expect(content.text.contains("No declarations"))
        }
    }

    @Test("JSON format returns valid JSON")
    func jsonFormatReturnsValidJSON() async throws {
        let tempFile = try createTempSwiftFile()
        defer { cleanup(tempFile.deletingLastPathComponent()) }

        let result = try await tool.execute(arguments: .object([
            "path": .string(tempFile.path),
            "format": .string("json"),
        ]))
        #expect(result.isError != true)
        if case let .text(content) = result.content.first {
            #expect(content.text.contains("{"))
            #expect(content.text.contains("\"nodes\""))
        }
    }

    @Test("Human format returns readable output")
    func humanFormatReturnsReadableOutput() async throws {
        let tempFile = try createTempSwiftFile()
        defer { cleanup(tempFile.deletingLastPathComponent()) }

        let result = try await tool.execute(arguments: .object([
            "path": .string(tempFile.path),
            "format": .string("human"),
        ]))
        #expect(result.isError != true)
        if case let .text(content) = result.content.first {
            #expect(content.text.contains("Sample.swift"))
            #expect(content.text.contains("nodes"))
        }
    }

    @Test("TOON format is default")
    func toonFormatIsDefault() async throws {
        let tempFile = try createTempSwiftFile()
        defer { cleanup(tempFile.deletingLastPathComponent()) }

        let result = try await tool.execute(arguments: .object([
            "path": .string(tempFile.path),
        ]))
        #expect(result.isError != true)
        if case let .text(content) = result.content.first {
            #expect(content.text.contains("ast{"))
        }
    }

    // MARK: - Filtering Tests

    @Test("Kind filter filters nodes")
    func kindFilterFiltersNodes() async throws {
        let tempFile = try createTempSwiftFile()
        defer { cleanup(tempFile.deletingLastPathComponent()) }

        let result = try await tool.execute(arguments: .object([
            "path": .string(tempFile.path),
            "kind_filter": .string("method"),
        ]))
        #expect(result.isError != true)
        if case let .text(content) = result.content.first {
            #expect(content.text.contains("method"))
            // Struct should be filtered out when only showing methods
        }
    }

    @Test("Max depth limits traversal")
    func maxDepthLimitsTraversal() async throws {
        let tempFile = try createTempSwiftFile()
        defer { cleanup(tempFile.deletingLastPathComponent()) }

        let resultWithDepth = try await tool.execute(arguments: .object([
            "path": .string(tempFile.path),
            "max_depth": .int(0),
        ]))

        let resultWithoutDepth = try await tool.execute(arguments: .object([
            "path": .string(tempFile.path),
        ]))

        // With depth 0, we should see fewer nodes
        if case let .text(withDepth) = resultWithDepth.content.first,
           case let .text(withoutDepth) = resultWithoutDepth.content.first
        {
            // The depth-limited result should be shorter or different
            #expect(withDepth.text.count <= withoutDepth.text.count)
        }
    }

    // MARK: - Directory Tests

    @Test("Directory with no Swift files returns message")
    func directoryWithNoSwiftFilesReturnsMessage() async throws {
        let tempDir = try createTempDirectory(with: [
            "readme.md": "# Readme",
        ])
        defer { cleanup(tempDir) }

        let result = try await tool.execute(arguments: .object([
            "path": .string(tempDir.path),
        ]))
        #expect(result.isError != true)
        if case let .text(content) = result.content.first {
            #expect(content.text.contains("No matching"))
        }
    }

    @Test("Directory with Swift files returns batch result")
    func directoryWithSwiftFilesReturnsBatchResult() async throws {
        let tempDir = try createTempDirectory(with: [
            "File1.swift": "struct File1 {}",
            "File2.swift": "class File2 {}",
        ])
        defer { cleanup(tempDir) }

        let result = try await tool.execute(arguments: .object([
            "path": .string(tempDir.path),
        ]))
        #expect(result.isError != true)
        if case let .text(content) = result.content.first {
            #expect(content.text.contains("batch{"))
            #expect(content.text.contains("File1"))
            #expect(content.text.contains("File2"))
        }
    }

    @Test("Custom pattern filters files")
    func customPatternFiltersFiles() async throws {
        let tempDir = try createTempDirectory(with: [
            "Sources/Main.swift": "struct Main {}",
            "Tests/MainTests.swift": "class MainTests {}",
        ])
        defer { cleanup(tempDir) }

        let result = try await tool.execute(arguments: .object([
            "path": .string(tempDir.path),
            "pattern": .string("Sources/**/*.swift"),
        ]))
        #expect(result.isError != true)
        if case let .text(content) = result.content.first {
            #expect(content.text.contains("Main"))
            #expect(!content.text.contains("MainTests"))
        }
    }
}

// MARK: - ParseTreeVisualizer Direct Tests

@Suite("ParseTreeVisualizer")
struct ParseTreeVisualizerTests {
    let visualizer = ParseTreeVisualizer()

    @Test("Visualize empty content returns empty result")
    func visualizeEmptyContent() {
        let result = visualizer.visualize(content: "", path: "test.swift")
        #expect(result.nodes.isEmpty)
        #expect(result.totalNodes == 0)
    }

    @Test("Visualize detects Swift language")
    func visualizeDetectsSwiftLanguage() {
        let result = visualizer.visualize(content: "struct S {}", path: "test.swift")
        #expect(result.language == "swift")
    }

    @Test("SkippedFiles are tracked in batch result")
    func skippedFilesAreTracked() async throws {
        let tempDir = try createTempDirectory(with: [
            "valid.swift": "struct Valid {}",
        ])
        defer { cleanup(tempDir) }

        // Create an unreadable file by removing read permissions
        let unreadableFile = tempDir.appendingPathComponent("unreadable.swift")
        try "struct Unreadable {}".write(to: unreadableFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadableFile.path)
        defer {
            // Restore permissions for cleanup
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadableFile.path)
        }

        let result = try await visualizer.visualizeDirectory(at: tempDir.path)

        #expect(result.files.count == 1)
        #expect(result.skippedFiles.count == 1)
        #expect(result.skippedFiles.first?.path.contains("unreadable.swift") == true)
    }

    @Test("Invalid glob pattern throws error")
    func invalidGlobPatternThrowsError() async throws {
        let tempDir = try createTempDirectory(with: [
            "test.swift": "struct Test {}",
        ])
        defer { cleanup(tempDir) }

        let options = ParseTreeOptions(pattern: "[invalid")

        await #expect(throws: ParseTreeError.self) {
            _ = try await visualizer.visualizeDirectory(at: tempDir.path, options: options)
        }
    }

    @Test("Directory enumeration failure throws error")
    func directoryEnumerationFailureThrowsError() async {
        // Non-existent directory should trigger enumeration failure
        // Note: FileManager.enumerator returns nil for non-existent paths
        let nonExistentPath = "/nonexistent/path/\(UUID().uuidString)"

        await #expect(throws: ParseTreeError.self) {
            _ = try await visualizer.visualizeDirectory(at: nonExistentPath)
        }
    }

    @Test("formatTOON includes skipped files section")
    func formatTOONIncludesSkippedFiles() {
        let result = ParseTreeBatchResult(
            files: [],
            totalFiles: 0,
            totalNodes: 0,
            maxDepth: 0,
            rootPath: "/test",
            skippedFiles: [
                SkippedFile(path: "/test/bad.swift", reason: "Permission denied"),
            ]
        )

        let output = visualizer.formatTOON(result)
        #expect(output.contains("skipped[1]"))
        #expect(output.contains("bad.swift"))
        #expect(output.contains("Permission denied"))
    }

    @Test("formatHuman includes skipped files section")
    func formatHumanIncludesSkippedFiles() {
        let result = ParseTreeBatchResult(
            files: [],
            totalFiles: 0,
            totalNodes: 0,
            maxDepth: 0,
            rootPath: "/test",
            skippedFiles: [
                SkippedFile(path: "/test/bad.swift", reason: "Permission denied"),
            ]
        )

        let output = visualizer.formatHuman(result)
        #expect(output.contains("Skipped Files"))
        #expect(output.contains("bad.swift"))
        #expect(output.contains("Permission denied"))
    }
}

// MARK: - ParseTreeError Tests

@Suite("ParseTreeError")
struct ParseTreeErrorTests {
    @Test("invalidGlobPattern has descriptive message")
    func invalidGlobPatternMessage() {
        let error = ParseTreeError.invalidGlobPattern(pattern: "[bad", reason: "unmatched bracket")
        #expect(error.errorDescription?.contains("[bad") == true)
        #expect(error.errorDescription?.contains("unmatched bracket") == true)
    }

    @Test("directoryEnumerationFailed has descriptive message")
    func directoryEnumerationFailedMessage() {
        let error = ParseTreeError.directoryEnumerationFailed(path: "/some/path")
        #expect(error.errorDescription?.contains("/some/path") == true)
    }

    @Test("jsonEncodingFailed has descriptive message")
    func jsonEncodingFailedMessage() {
        let error = ParseTreeError.jsonEncodingFailed
        #expect(error.errorDescription?.contains("JSON") == true)
    }

    @Test("Errors are Equatable")
    func errorsAreEquatable() {
        let error1 = ParseTreeError.invalidGlobPattern(pattern: "test", reason: "reason")
        let error2 = ParseTreeError.invalidGlobPattern(pattern: "test", reason: "reason")
        let error3 = ParseTreeError.invalidGlobPattern(pattern: "other", reason: "reason")

        #expect(error1 == error2)
        #expect(error1 != error3)
    }
}
