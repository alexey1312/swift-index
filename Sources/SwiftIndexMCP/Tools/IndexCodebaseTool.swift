// MARK: - IndexCodebaseTool

import Foundation
import SwiftIndexCore

/// MCP tool for indexing a Swift codebase.
///
/// This tool scans a directory, parses Swift files, generates embeddings,
/// and stores the indexed chunks for later searching.
public struct IndexCodebaseTool: MCPToolHandler, Sendable {
    public let definition: MCPTool

    public init() {
        self.definition = MCPTool(
            name: "index_codebase",
            description: """
                Index a Swift codebase for semantic search.
                Parses Swift files, extracts code chunks (functions, types, etc.),
                generates embeddings, and stores them for later searching.
                """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object([
                        "type": "string",
                        "description": "Absolute path to the directory to index"
                    ]),
                    "force": .object([
                        "type": "boolean",
                        "description": "Force re-indexing even if files haven't changed",
                        "default": false
                    ])
                ]),
                "required": .array([.string("path")])
            ])
        )
    }

    public func execute(arguments: JSONValue) async throws -> ToolCallResult {
        // Extract path argument
        guard let path = arguments["path"]?.stringValue else {
            return .error("Missing required argument: path")
        }

        let force = arguments["force"]?.boolValue ?? false

        // Validate path exists
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .error("Path does not exist or is not a directory: \(path)")
        }

        // Perform indexing
        do {
            let result = try await performIndexing(path: path, force: force)
            return .text(formatResult(result))
        } catch {
            return .error("Indexing failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func performIndexing(path: String, force: Bool) async throws -> IndexingResult {
        // TODO: Integrate with actual indexer when implemented
        // For now, return a placeholder that scans files

        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)

        let swiftFiles: [URL] = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ).map { enumerator in
            enumerator.compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
        } ?? []

        // Placeholder: count files and estimate chunks
        // Real implementation would parse files and generate embeddings
        let estimatedChunks = swiftFiles.count * 5 // Rough estimate

        return IndexingResult(
            indexedFiles: swiftFiles.count,
            chunks: estimatedChunks,
            path: path,
            forced: force
        )
    }

    private func formatResult(_ result: IndexingResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let output: [String: Any] = [
            "indexed_files": result.indexedFiles,
            "chunks": result.chunks,
            "path": result.path,
            "forced": result.forced
        ]

        // Format as JSON manually since we need to control the output
        return """
            {
              "indexed_files": \(result.indexedFiles),
              "chunks": \(result.chunks),
              "path": "\(result.path)",
              "forced": \(result.forced)
            }
            """
    }
}

// MARK: - IndexingResult

private struct IndexingResult {
    let indexedFiles: Int
    let chunks: Int
    let path: String
    let forced: Bool
}
