// MARK: - WatchCodebaseTool

import Foundation
import SwiftIndexCore

/// MCP tool for watching a codebase for changes.
///
/// Sets up file system monitoring to detect changes and
/// automatically re-index modified files for up-to-date search.
public struct WatchCodebaseTool: MCPToolHandler, Sendable {
    public let definition: MCPTool

    /// Shared watcher state (actor-isolated for thread safety).
    private static let watcherState = WatcherState()

    public init() {
        definition = MCPTool(
            name: "watch_codebase",
            description: """
            Watch a codebase directory for file changes.
            Automatically re-indexes modified, added, or deleted
            Swift files to keep the search index up-to-date.
            """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object([
                        "type": "string",
                        "description": "Absolute path to the directory to watch",
                    ]),
                    "action": .object([
                        "type": "string",
                        "description": "Action to perform: 'start', 'stop', or 'status'",
                        "enum": .array([
                            .string("start"),
                            .string("stop"),
                            .string("status"),
                        ]),
                        "default": "start",
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

        let action = arguments["action"]?.stringValue ?? "start"

        // Validate path exists for start action
        if action == "start" {
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                return .error("Path does not exist or is not a directory: \(path)")
            }
        }

        // Perform action
        switch action {
        case "start":
            return await startWatching(path: path)
        case "stop":
            return await stopWatching(path: path)
        case "status":
            return await getStatus(path: path)
        default:
            return .error("Invalid action: \(action). Use 'start', 'stop', or 'status'.")
        }
    }

    // MARK: - Private

    private func startWatching(path: String) async -> ToolCallResult {
        let isAlreadyWatching = await Self.watcherState.isWatching(path: path)

        if isAlreadyWatching {
            return .text(formatResult(
                action: "start",
                path: path,
                watching: true,
                message: "Already watching this path"
            ))
        }

        // Get config and create incremental indexer
        do {
            let context = MCPContext.shared
            let config = try await context.getConfig(for: path)

            // Check if index exists
            guard await context.indexExists(for: path, config: config) else {
                return .error(
                    """
                    No index found for path: \(path)
                    Run 'index_codebase' tool first to create the index.
                    """
                )
            }

            // Get index manager and embedding provider
            let indexManager = try await context.getIndexManager(for: path, config: config)
            let embeddingProvider = await context.getEmbeddingProvider(config: config)

            // Create incremental indexer
            let incrementalIndexer = IncrementalIndexer(
                indexManager: indexManager,
                parser: HybridParser(),
                embeddingProvider: embeddingProvider,
                config: config
            )

            // Start watching
            await Self.watcherState.startWatching(
                path: path,
                indexer: incrementalIndexer
            )

            return .text(formatResult(
                action: "start",
                path: path,
                watching: true,
                message: "Started watching for file changes"
            ))
        } catch {
            return .error("Failed to start watching: \(error.localizedDescription)")
        }
    }

    private func stopWatching(path: String) async -> ToolCallResult {
        let wasWatching = await Self.watcherState.isWatching(path: path)

        if !wasWatching {
            return .text(formatResult(
                action: "stop",
                path: path,
                watching: false,
                message: "Was not watching this path"
            ))
        }

        // Stop watching and get final stats
        let stats = await Self.watcherState.stopWatching(path: path)

        // Save the index
        do {
            try await MCPContext.shared.saveAllIndexes()
        } catch {
            // Log but don't fail - watching was stopped
        }

        return .text(formatStopResult(
            path: path,
            stats: stats
        ))
    }

    private func getStatus(path: String) async -> ToolCallResult {
        let isWatching = await Self.watcherState.isWatching(path: path)
        let stats = await Self.watcherState.getStats(path: path)

        let output: [String: Any] = [
            "path": path,
            "watching": isWatching,
            "stats": [
                "files_created": stats.filesCreated,
                "files_modified": stats.filesModified,
                "files_deleted": stats.filesDeleted,
                "chunks_added": stats.chunksAdded,
                "chunks_removed": stats.chunksRemoved,
                "errors": stats.errors,
                "last_event": stats.lastEvent.map { formatDate($0) } as Any,
            ],
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: output,
            options: [.prettyPrinted, .sortedKeys]
        ),
            let string = String(data: data, encoding: .utf8)
        else {
            return .text("{}")
        }
        return .text(string)
    }

    private func formatResult(
        action: String,
        path: String,
        watching: Bool,
        message: String
    ) -> String {
        let output: [String: Any] = [
            "action": action,
            "path": path,
            "watching": watching,
            "message": message,
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: output,
            options: [.prettyPrinted, .sortedKeys]
        ),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    private func formatStopResult(path: String, stats: WatchStats) -> String {
        let output: [String: Any] = [
            "action": "stop",
            "path": path,
            "watching": false,
            "message": "Stopped watching for file changes",
            "session_stats": [
                "files_created": stats.filesCreated,
                "files_modified": stats.filesModified,
                "files_deleted": stats.filesDeleted,
                "chunks_added": stats.chunksAdded,
                "chunks_removed": stats.chunksRemoved,
                "errors": stats.errors,
            ],
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: output,
            options: [.prettyPrinted, .sortedKeys]
        ),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

// MARK: - Watcher State

/// Actor to manage watcher state in a thread-safe manner.
private actor WatcherState {
    private var watchedPaths: [String: WatchSession] = [:]

    struct WatchSession {
        let indexer: IncrementalIndexer
        var task: Task<Void, Error>?
        var stats: WatchStats
    }

    func isWatching(path: String) -> Bool {
        watchedPaths[path] != nil
    }

    func startWatching(path: String, indexer: IncrementalIndexer) {
        var session = WatchSession(
            indexer: indexer,
            task: nil,
            stats: WatchStats()
        )

        // Start the watch task
        session.task = Task {
            try await indexer.watchAndIndex(path: path)
        }

        watchedPaths[path] = session
    }

    func stopWatching(path: String) async -> WatchStats {
        guard let session = watchedPaths[path] else {
            return WatchStats()
        }

        // Cancel the task
        session.task?.cancel()

        // Stop the indexer
        await session.indexer.stop()

        // Get final stats from indexer
        let indexerStats = await session.indexer.getStats()
        let stats = WatchStats(
            filesCreated: indexerStats.filesCreated,
            filesModified: indexerStats.filesModified,
            filesDeleted: indexerStats.filesDeleted,
            chunksAdded: indexerStats.chunksAdded,
            chunksRemoved: indexerStats.chunksRemoved,
            errors: indexerStats.errors,
            lastEvent: Date()
        )

        watchedPaths.removeValue(forKey: path)
        return stats
    }

    func getStats(path: String) async -> WatchStats {
        guard let session = watchedPaths[path] else {
            return WatchStats()
        }

        // Get current stats from indexer
        let indexerStats = await session.indexer.getStats()
        return WatchStats(
            filesCreated: indexerStats.filesCreated,
            filesModified: indexerStats.filesModified,
            filesDeleted: indexerStats.filesDeleted,
            chunksAdded: indexerStats.chunksAdded,
            chunksRemoved: indexerStats.chunksRemoved,
            errors: indexerStats.errors,
            lastEvent: Date()
        )
    }
}

// MARK: - Watch Stats

private struct WatchStats {
    var filesCreated: Int = 0
    var filesModified: Int = 0
    var filesDeleted: Int = 0
    var chunksAdded: Int = 0
    var chunksRemoved: Int = 0
    var errors: Int = 0
    var lastEvent: Date?
}
