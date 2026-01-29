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

            Shorthand: si (e.g., "use si to index" means use this swiftindex tool)
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
                    "poll_interval": .object([
                        "type": "integer",
                        "description":
                            """
                            Polling interval in milliseconds for check_indexing_status. \
                            If not specified, calculated dynamically based on project size \
                            (100ms per file, clamped to 10-60 seconds).
                            """,
                        "minimum": 1000,
                        "maximum": 300_000,
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
        let customPollInterval = arguments["poll_interval"]?.intValue

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
            return await startAsyncIndexing(path: path, force: force, customPollInterval: customPollInterval)
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

    private func startAsyncIndexing(path: String, force: Bool, customPollInterval: Int?) async -> ToolCallResult {
        let taskManager = MCPContext.shared.taskManager

        // Estimate file count first to calculate dynamic poll interval
        let estimatedFiles = await estimateFileCount(path: path)

        // Use custom poll interval if provided, otherwise calculate dynamically
        // Dynamic: 100ms per file, clamped to 10-60 seconds
        let pollInterval: Int = if let custom = customPollInterval {
            // Clamp custom value to 1-300 seconds
            max(1000, min(300_000, custom))
        } else {
            // Dynamic calculation based on project size
            max(10000, min(60000, estimatedFiles * 100))
        }

        // Create task with reasonable TTL (1 hour) and poll interval
        let task = await taskManager.createTask(ttl: 3_600_000, pollInterval: pollInterval)

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
                snippetsIndexed: result.snippets,
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
        let config: Config
        do {
            config = try await mcpContext.getConfig(for: path)
        } catch ConfigError.notInitialized {
            throw MCPError.executionFailed("""
            Project not initialized. No .swiftindex.toml found.

            Run 'swiftindex init' in the project directory first.
            """)
        }
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

        // Throttling: update progress every N files or N seconds to reduce polling noise
        let progressUpdateInterval = 5 // Update every 5 files
        var lastProgressUpdate = ContinuousClock.now
        let minProgressInterval: Duration = .seconds(2) // Or every 2 seconds

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
                stats.snippetsIndexed += result.snippetsIndexed
                stats.filesSkipped += result.skipped ? 1 : 0
            } catch {
                stats.errors += 1
            }

            // Update indexing progress for async mode with throttling
            // Update every N files, every N seconds, or on the last file
            if let taskId {
                let now = ContinuousClock.now
                let isLastFile = index == totalFiles - 1
                let intervalReached = (index + 1) % progressUpdateInterval == 0
                let timeElapsed = now - lastProgressUpdate >= minProgressInterval

                if isLastFile || intervalReached || timeElapsed {
                    await taskManager.updateIndexingProgress(taskId, progress: IndexingProgress(
                        filesProcessed: stats.filesProcessed,
                        totalFiles: totalFiles,
                        currentFile: fileName,
                        chunksIndexed: stats.chunksIndexed,
                        snippetsIndexed: stats.snippetsIndexed,
                        errors: stats.errors,
                        phase: .indexing
                    ))
                    lastProgressUpdate = now
                }
            }
        }

        // Save index
        await context?.reportStatus("Saving index...")
        if let taskId {
            await taskManager.updateIndexingProgress(taskId, progress: IndexingProgress(
                filesProcessed: stats.filesProcessed,
                totalFiles: totalFiles,
                chunksIndexed: stats.chunksIndexed,
                snippetsIndexed: stats.snippetsIndexed,
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
            snippets: stats.snippetsIndexed,
            totalChunks: finalStats.chunkCount,
            totalSnippets: finalStats.snippetCount,
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
    ) async throws -> MCPFileIndexResult {
        // Read file content
        let content = try String(contentsOfFile: path, encoding: .utf8)

        // Compute file hash for incremental indexing
        let fileHash = FileHasher.hash(content)

        // Check if file needs indexing (unless force is set)
        if !force {
            let needsIndexing = try await indexManager.needsIndexing(path: path, fileHash: fileHash)
            if !needsIndexing {
                return MCPFileIndexResult(chunksIndexed: 0, snippetsIndexed: 0, skipped: true)
            }
        }

        // Parse file
        let parseResult = parser.parse(content: content, path: path, fileHash: fileHash)

        if case .failure = parseResult {
            return MCPFileIndexResult(chunksIndexed: 0, snippetsIndexed: 0, skipped: false)
        }

        // Use unified indexFile method from IndexManager
        // This handles both chunks (with change detection) and snippets
        let result = try await indexManager.indexFile(
            path: path,
            fileHash: fileHash,
            parseResult: parseResult
        ) { chunksToEmbed in
            // Generate embeddings for chunks that need them
            try await embeddingProvider.embed(chunksToEmbed.map(\.content))
        }

        return MCPFileIndexResult(
            chunksIndexed: result.chunksIndexed,
            snippetsIndexed: result.snippetsIndexed,
            skipped: false
        )
    }

    private func formatResult(_ result: IndexingResult) -> String {
        let output: [String: Any] = [
            "path": result.path,
            "forced": result.forced,
            "indexed_files": result.indexedFiles,
            "skipped_files": result.skippedFiles,
            "chunks_indexed": result.chunks,
            "snippets_indexed": result.snippets,
            "total_chunks": result.totalChunks,
            "total_snippets": result.totalSnippets,
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
    var snippetsIndexed: Int = 0
    var errors: Int = 0
}

private struct MCPFileIndexResult {
    let chunksIndexed: Int
    let snippetsIndexed: Int
    let skipped: Bool
}

private struct IndexingResult {
    let indexedFiles: Int
    let skippedFiles: Int
    let chunks: Int
    let snippets: Int
    let totalChunks: Int
    let totalSnippets: Int
    let totalFiles: Int
    let errors: Int
    let path: String
    let forced: Bool
}
