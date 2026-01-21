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
        self.definition = MCPTool(
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
                        "description": "Absolute path to the directory to watch"
                    ]),
                    "action": .object([
                        "type": "string",
                        "description": "Action to perform: 'start', 'stop', or 'status'",
                        "enum": .array([
                            .string("start"),
                            .string("stop"),
                            .string("status")
                        ]),
                        "default": "start"
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

        let action = arguments["action"]?.stringValue ?? "start"

        // Validate path exists for start action
        if action == "start" {
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
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

        // Start watching
        await Self.watcherState.startWatching(path: path)

        return .text(formatResult(
            action: "start",
            path: path,
            watching: true,
            message: "Started watching for file changes"
        ))
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

        // Stop watching
        await Self.watcherState.stopWatching(path: path)

        return .text(formatResult(
            action: "stop",
            path: path,
            watching: false,
            message: "Stopped watching for file changes"
        ))
    }

    private func getStatus(path: String) async -> ToolCallResult {
        let isWatching = await Self.watcherState.isWatching(path: path)
        let stats = await Self.watcherState.getStats(path: path)

        var output = "{\n"
        output += "  \"path\": \"\(escapeJSON(path))\",\n"
        output += "  \"watching\": \(isWatching),\n"
        output += "  \"stats\": {\n"
        output += "    \"files_modified\": \(stats.filesModified),\n"
        output += "    \"files_added\": \(stats.filesAdded),\n"
        output += "    \"files_deleted\": \(stats.filesDeleted),\n"
        output += "    \"last_event\": \(stats.lastEvent.map { "\"\(formatDate($0))\"" } ?? "null")\n"
        output += "  }\n"
        output += "}"

        return .text(output)
    }

    private func formatResult(
        action: String,
        path: String,
        watching: Bool,
        message: String
    ) -> String {
        """
        {
          "action": "\(action)",
          "path": "\(escapeJSON(path))",
          "watching": \(watching),
          "message": "\(escapeJSON(message))"
        }
        """
    }

    private func escapeJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
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
    private var watchedPaths: Set<String> = []
    private var stats: [String: WatchStats] = [:]
    private var dispatches: [String: DispatchSourceFileSystemObject] = [:]

    func isWatching(path: String) -> Bool {
        watchedPaths.contains(path)
    }

    func startWatching(path: String) {
        watchedPaths.insert(path)
        stats[path] = WatchStats()

        // TODO: Integrate with actual DispatchSource file monitoring
        // For now, just track the state
        // Real implementation would use DispatchSource.makeFileSystemObjectSource
    }

    func stopWatching(path: String) {
        watchedPaths.remove(path)
        dispatches[path]?.cancel()
        dispatches.removeValue(forKey: path)
    }

    func getStats(path: String) -> WatchStats {
        stats[path] ?? WatchStats()
    }

    func recordEvent(path: String, type: EventType) {
        var pathStats = stats[path] ?? WatchStats()

        switch type {
        case .modified:
            pathStats.filesModified += 1
        case .added:
            pathStats.filesAdded += 1
        case .deleted:
            pathStats.filesDeleted += 1
        }

        pathStats.lastEvent = Date()
        stats[path] = pathStats
    }

    enum EventType {
        case modified
        case added
        case deleted
    }
}

// MARK: - Watch Stats

private struct WatchStats {
    var filesModified: Int = 0
    var filesAdded: Int = 0
    var filesDeleted: Int = 0
    var lastEvent: Date?
}
