// MARK: - ParseTreeTool

import Foundation
import SwiftIndexCore

/// MCP tool for visualizing Swift AST structure.
///
/// Parses Swift files and displays their abstract syntax tree structure.
/// Supports both single files and directories with glob patterns.
public struct ParseTreeTool: MCPToolHandler, Sendable {
    public let definition: MCPTool

    public init() {
        definition = MCPTool(
            name: "parse_tree",
            title: "Parse Tree Visualizer",
            description: """
            Visualize Swift AST (Abstract Syntax Tree) structure.
            Parses Swift files and displays their declaration hierarchy.
            Supports both single files and directories with glob patterns.

            Useful for understanding code structure, finding declarations,
            and exploring the syntax tree of Swift source files.

            Shorthand: si (e.g., "use si parse_tree" means use this swiftindex tool)
            """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object([
                        "type": "string",
                        "description": "Path to a Swift file or directory to parse",
                    ]),
                    "pattern": .object([
                        "type": "string",
                        "description": "Glob pattern for directories (default: **/*.swift)",
                        "default": "**/*.swift",
                    ]),
                    "max_depth": .object([
                        "type": "integer",
                        "description": "Maximum AST depth to traverse",
                    ]),
                    "kind_filter": .object([
                        "type": "string",
                        "description": "Comma-separated list of node kinds to include (e.g., class,struct,method)",
                    ]),
                    "format": .object([
                        "type": "string",
                        "description": "Output format: toon (compact), json, or human",
                        "enum": .array([.string("toon"), .string("json"), .string("human")]),
                    ]),
                ]),
                "required": .array([.string("path")]),
            ]),
            annotations: ToolAnnotations(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        )
    }

    public func execute(arguments: JSONValue) async throws -> ToolCallResult {
        // Extract arguments
        guard let path = arguments["path"]?.stringValue else {
            return .error("Missing required argument: path")
        }

        let patternArg = arguments["pattern"]?.stringValue
        let maxDepth = arguments["max_depth"]?.intValue
        let kindFilterArg = arguments["kind_filter"]?.stringValue
        let formatArg = arguments["format"]?.stringValue ?? "toon"

        // Validate max_depth
        if let depth = maxDepth, depth < 0 {
            return .error("max_depth must be non-negative")
        }

        // Parse kind filter
        var kindFilter: Set<String>?
        if let kinds = kindFilterArg {
            kindFilter = Set(
                kinds.split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
            )
        }

        // Build options
        let options = ParseTreeOptions(
            maxDepth: maxDepth,
            kindFilter: kindFilter,
            expandChildren: true,
            pattern: patternArg
        )

        // Check if path exists and determine type
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .error("Path does not exist: \(path)")
        }

        let visualizer = ParseTreeVisualizer()

        do {
            if isDirectory.boolValue {
                // Directory mode
                let result = try await visualizer.visualizeDirectory(at: path, options: options)

                if result.files.isEmpty {
                    let effectivePattern = patternArg ?? "**/*.swift"
                    return .text(
                        """
                        No matching Swift files found.
                        Path: \(path)
                        Pattern: \(effectivePattern)
                        """
                    )
                }

                let output = try formatBatchResult(result, format: formatArg, visualizer: visualizer)
                return .text(output)

            } else {
                // Single file mode
                let result = try visualizer.visualizeFile(at: path, options: options)

                if result.nodes.isEmpty {
                    return .text("No declarations found in file: \(path)")
                }

                let output = try formatSingleResult(result, format: formatArg, visualizer: visualizer)
                return .text(output)
            }
        } catch {
            return .error("Parse failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func formatSingleResult(
        _ result: ParseTreeResult,
        format: String,
        visualizer: ParseTreeVisualizer
    ) throws -> String {
        switch format {
        case "json":
            try visualizer.formatJSON(result)
        case "human":
            visualizer.formatHuman(result)
        default:
            visualizer.formatTOON(result)
        }
    }

    private func formatBatchResult(
        _ result: ParseTreeBatchResult,
        format: String,
        visualizer: ParseTreeVisualizer
    ) throws -> String {
        switch format {
        case "json":
            try visualizer.formatJSON(result)
        case "human":
            visualizer.formatHuman(result)
        default:
            visualizer.formatTOON(result)
        }
    }
}
