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
            title: "Code Indexer",
            description: """
            Index a Swift codebase for semantic search.
            Parses Swift files, extracts code chunks (functions, types, etc.),
            generates embeddings, and stores them for later searching.

            For long-running indexing operations, set async=true to run in background.
            Returns a task_id immediately that can be used with check_indexing_status
            to monitor progress.
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
                    "async": .object([
                        "type": "boolean",
                        "description":
                            """
                            Run indexing in background and return task_id immediately. \
                            Use check_indexing_status to monitor progress. \
                            Set to false for synchronous blocking mode.
                            """,
                        "default": true,
                    ]),
                ]),
                "required": .array([.string("path")]),
            ]),
            annotations: ToolAnnotations(
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        )
    }

    public func execute(arguments: JSONValue) async throws -> ToolCallResult {
        try await execute(arguments: arguments, context: nil)
    }

    public func execute(arguments: JSONValue, context: ToolExecutionContext?) async throws -> ToolCallResult {
        // Extract path argument
        guard let path = arguments["path"]?.stringValue else {
            return .error("Missing required argument: path")
        }

        let force = arguments["force"]?.boolValue ?? false
        let runAsync = arguments["async"]?.boolValue ?? true

        // Validate path exists
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return .error("Path does not exist or is not a directory: \(path)")
        }

        // If async mode, start background task and return immediately
        if runAsync {
            return await startAsyncIndexing(path: path, force: force)
        }

        // Synchronous mode - perform indexing and wait for result
        do {
            let result = try await performIndexing(path: path, force: force, context: context, taskId: nil)
            return .text(formatResult(result))
        } catch is CancellationError {
            return .error("Indexing was cancelled")
        } catch {
            return .error("Indexing failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Async Mode

    private func startAsyncIndexing(path: String, force: Bool) async -> ToolCallResult {
        let taskManager = MCPContext.shared.taskManager

        // Create task with reasonable TTL (1 hour)
        let task = await taskManager.createTask(ttl: 3_600_000, pollInterval: 2000)

        // Estimate file count for initial response
        let estimatedFiles = await estimateFileCount(path: path)

        // Initialize progress
        await taskManager.updateIndexingProgress(task.taskId, progress: IndexingProgress(
            totalFiles: estimatedFiles,
            phase: .collecting
        ))

        // Start background indexing and register task for cancellation support
        let backgroundTask = Task {
            await performBackgroundIndexing(
                path: path,
                force: force,
                taskId: task.taskId,
                taskManager: taskManager
            )
        }
        await taskManager.registerBackgroundTask(task.taskId, task: backgroundTask)

        // Return immediately with task info
        let response: [String: Any] = [
            "task_id": task.taskId,
            "status": "started",
            "estimated_files": estimatedFiles,
            "message": "Indexing started. Use check_indexing_status tool with this task_id to monitor progress.",
        ]

        guard let data = try? JSONCodec.serialize(response, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return .text("{\"task_id\": \"\(task.taskId)\", \"status\": \"started\"}")
        }
        return .text(string)
    }

    private func estimateFileCount(path: String) async -> Int {
        let mcpContext = MCPContext.shared
        guard let config = try? await mcpContext.getConfig(for: path) else {
            return 0
        }

        let parser = HybridParser()
        let files = (try? collectFiles(at: path, config: config, parser: parser)) ?? []
        return files.count
    }

    private func performBackgroundIndexing(
        path: String,
        force: Bool,
        taskId: String,
        taskManager: TaskManager
    ) async {
        do {
            let result = try await performIndexing(path: path, force: force, context: nil, taskId: taskId)

            // Update final progress
            await taskManager.updateIndexingProgress(taskId, progress: IndexingProgress(
                filesProcessed: result.indexedFiles,
                totalFiles: result.totalFiles,
                chunksIndexed: result.chunks,
                errors: result.errors,
                phase: .completed
            ))

            // Store result
            await taskManager.storeResult(taskId, result: .text(formatResult(result)))
        } catch is CancellationError {
            await taskManager.updateStatus(taskId, status: .cancelled, message: "Indexing was cancelled")
        } catch {
            await taskManager.updateIndexingProgress(taskId, progress: IndexingProgress(phase: .failed))
            await taskManager.failTask(taskId, error: error.localizedDescription)
        }
    }

    // MARK: - Private

    private func performIndexing(
        path: String,
        force: Bool,
        context: ToolExecutionContext?,
        taskId: String?
    ) async throws -> IndexingResult {
        let mcpContext = MCPContext.shared
        let config = try await mcpContext.getConfig(for: path)
        let taskManager = mcpContext.taskManager

        // Report initial status
        await context?.reportStatus("Initializing...")

        // Create embedding provider
        let embeddingProvider = try await mcpContext.getEmbeddingProvider(config: config)

        // Check provider availability
        guard await embeddingProvider.isAvailable() else {
            throw MCPError.executionFailed("No embedding provider available")
        }

        // Get or create index manager
        let indexManager = try await mcpContext.getIndexManager(for: path, config: config)

        // Handle force re-indexing
        if force {
            await context?.reportStatus("Clearing existing index...")
            try await indexManager.clear()
        }

        // Create parser
        let parser = HybridParser()

        // Collect files to index
        await context?.reportStatus("Collecting files...")
        if let taskId {
            await taskManager.updateIndexingProgress(taskId, progress: IndexingProgress(phase: .collecting))
        }
        let files = try collectFiles(at: path, config: config, parser: parser)

        // Index files
        var stats = IndexingStats()
        let totalFiles = files.count

        // Update progress with total files count
        if let taskId {
            await taskManager.updateIndexingProgress(taskId, progress: IndexingProgress(
                totalFiles: totalFiles,
                phase: .indexing
            ))
        }

        for (index, filePath) in files.enumerated() {
            // Check for cancellation
            try await context?.checkCancellation()
            if let taskId {
                let token = await taskManager.getCancellationToken(taskId)
                try await token?.checkCancellationAsync()
            }

            // Report progress
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            await context?.reportProgress(
                current: index + 1,
                total: totalFiles,
                message: "Indexing: \(fileName)"
            )

            // Index file first, then update progress with accurate stats
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

            // Update indexing progress for async mode with accurate post-processing stats
            if let taskId {
                await taskManager.updateIndexingProgress(taskId, progress: IndexingProgress(
                    filesProcessed: stats.filesProcessed,
                    totalFiles: totalFiles,
                    currentFile: fileName,
                    chunksIndexed: stats.chunksIndexed,
                    errors: stats.errors,
                    phase: .indexing
                ))
            }
        }

        // Save index
        await context?.reportStatus("Saving index...")
        if let taskId {
            await taskManager.updateIndexingProgress(taskId, progress: IndexingProgress(
                filesProcessed: stats.filesProcessed,
                totalFiles: totalFiles,
                chunksIndexed: stats.chunksIndexed,
                errors: stats.errors,
                phase: .saving
            ))
        }
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
        let fileHash = FileHasher.hash(content)

        // Check if file needs indexing (unless force is set)
        if !force {
            let needsIndexing = try await indexManager.needsIndexing(path: path, fileHash: fileHash)
            if !needsIndexing {
                return FileIndexResult(chunksIndexed: 0, skipped: true)
            }
        }

        // Parse file
        let parseResult = parser.parse(content: content, path: path, fileHash: fileHash)

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
