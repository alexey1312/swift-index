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
        definition = MCPTool(
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
                        "description": "Absolute path to the directory to index",
                    ]),
                    "force": .object([
                        "type": "boolean",
                        "description": "Force re-indexing even if files haven't changed",
                        "default": false,
                    ]),
                ]),
                "required": .array([.string("path")]),
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
              isDirectory.boolValue
        else {
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
        let context = MCPContext.shared
        let config = try await context.getConfig(for: path)

        // Create embedding provider
        let embeddingProvider = await context.getEmbeddingProvider(config: config)

        // Check provider availability
        guard await embeddingProvider.isAvailable() else {
            throw MCPError.executionFailed("No embedding provider available")
        }

        // Get or create index manager
        let indexManager = try await context.getIndexManager(for: path, config: config)

        // Handle force re-indexing
        if force {
            try await indexManager.clear()
        }

        // Create parser
        let parser = HybridParser()

        // Collect files to index
        let files = try collectFiles(at: path, config: config, parser: parser)

        // Index files
        var stats = IndexingStats()

        for filePath in files {
            do {
                let result = try await indexFile(
                    at: filePath,
                    indexManager: indexManager,
                    parser: parser,
                    embeddingProvider: embeddingProvider,
                    force: force
                )

                stats.filesProcessed += 1
                stats.chunksIndexed += result.chunksIndexed
                stats.filesSkipped += result.skipped ? 1 : 0
            } catch {
                stats.errors += 1
            }
        }

        // Save index
        try await indexManager.save()

        // Get final statistics
        let finalStats = try await indexManager.statistics()

        return IndexingResult(
            indexedFiles: stats.filesProcessed,
            skippedFiles: stats.filesSkipped,
            chunks: stats.chunksIndexed,
            totalChunks: finalStats.chunkCount,
            totalFiles: finalStats.fileCount,
            errors: stats.errors,
            path: path,
            forced: force
        )
    }

    private func collectFiles(
        at path: String,
        config: Config,
        parser: HybridParser
    ) throws -> [String] {
        var files: [String] = []
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw MCPError.executionFailed("Could not enumerate directory: \(path)")
        }

        for case let fileURL as URL in enumerator {
            let filePath = fileURL.path

            // Check exclusion patterns
            var shouldExclude = false
            for pattern in config.excludePatterns {
                if filePath.contains(pattern) {
                    shouldExclude = true
                    break
                }
            }

            if shouldExclude {
                continue
            }

            // Check if regular file
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  let isRegularFile = resourceValues.isRegularFile,
                  isRegularFile
            else {
                continue
            }

            // Check file size
            if let fileSize = resourceValues.fileSize, fileSize > config.maxFileSize {
                continue
            }

            // Check extension
            let ext = fileURL.pathExtension.lowercased()

            if !config.includeExtensions.isEmpty {
                guard config.includeExtensions.contains(ext) ||
                    config.includeExtensions.contains(".\(ext)")
                else {
                    continue
                }
            } else {
                guard parser.supportedExtensions.contains(ext) else {
                    continue
                }
            }

            files.append(filePath)
        }

        return files.sorted()
    }

    private func indexFile(
        at path: String,
        indexManager: IndexManager,
        parser: HybridParser,
        embeddingProvider: EmbeddingProviderChain,
        force: Bool
    ) async throws -> FileIndexResult {
        // Read file content
        let content = try String(contentsOfFile: path, encoding: .utf8)

        // Compute file hash for incremental indexing
        let fileHash = computeFileHash(content)

        // Check if file needs indexing (unless force is set)
        if !force {
            let needsIndexing = try await indexManager.needsIndexing(fileHash: fileHash)
            if !needsIndexing {
                return FileIndexResult(chunksIndexed: 0, skipped: true)
            }
        }

        // Parse file
        let parseResult = parser.parse(content: content, path: path)

        if case .failure = parseResult {
            return FileIndexResult(chunksIndexed: 0, skipped: false)
        }

        let chunks = parseResult.chunks
        guard !chunks.isEmpty else {
            try await indexManager.recordIndexed(fileHash: fileHash, path: path)
            return FileIndexResult(chunksIndexed: 0, skipped: false)
        }

        // Generate embeddings for all chunks
        let contents = chunks.map(\.content)
        let embeddings = try await embeddingProvider.embed(contents)

        // Create chunk-vector pairs
        var items: [(chunk: CodeChunk, vector: [Float])] = []
        for (chunk, embedding) in zip(chunks, embeddings) {
            items.append((chunk: chunk, vector: embedding))
        }

        // Re-index the file
        try await indexManager.reindex(path: path, newChunks: items)

        return FileIndexResult(chunksIndexed: chunks.count, skipped: false)
    }

    private func computeFileHash(_ content: String) -> String {
        var hasher = Hasher()
        hasher.combine(content)
        let hash = hasher.finalize()
        return String(format: "%016x", hash)
    }

    private func formatResult(_ result: IndexingResult) -> String {
        let output: [String: Any] = [
            "path": result.path,
            "forced": result.forced,
            "indexed_files": result.indexedFiles,
            "skipped_files": result.skippedFiles,
            "chunks_indexed": result.chunks,
            "total_chunks": result.totalChunks,
            "total_files": result.totalFiles,
            "errors": result.errors,
        ]

        guard let data = try? JSONCodec.serialize(output, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}

// MARK: - Helper Types

private struct IndexingStats {
    var filesProcessed: Int = 0
    var filesSkipped: Int = 0
    var chunksIndexed: Int = 0
    var errors: Int = 0
}

private struct FileIndexResult {
    let chunksIndexed: Int
    let skipped: Bool
}

private struct IndexingResult {
    let indexedFiles: Int
    let skippedFiles: Int
    let chunks: Int
    let totalChunks: Int
    let totalFiles: Int
    let errors: Int
    let path: String
    let forced: Bool
}
