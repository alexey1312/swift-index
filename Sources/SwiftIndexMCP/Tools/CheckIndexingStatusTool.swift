// MARK: - CheckIndexingStatusTool

import Foundation
import SwiftIndexCore

/// MCP tool for checking the status of an async indexing operation.
///
/// This tool works with `index_codebase` when called with `async=true`.
/// It returns the current progress or final result of an indexing task.
public struct CheckIndexingStatusTool: MCPToolHandler, Sendable {
    public let definition: MCPTool

    public init() {
        definition = MCPTool(
            name: "check_indexing_status",
            title: "Indexing Status",
            description: """
            Check the status of an ongoing or completed indexing operation.
            Returns progress information including current file, completion percentage,
            and final results when done.

            Use this tool after calling index_codebase with async=true.
            Poll periodically (every 2-5 seconds) until status is "completed" or "failed".
            """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "task_id": .object([
                        "type": "string",
                        "description": "The task ID returned by index_codebase when called with async=true",
                    ]),
                ]),
                "required": .array([.string("task_id")]),
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
        guard let taskId = arguments["task_id"]?.stringValue else {
            return .error("Missing required argument: task_id")
        }

        let taskManager = MCPContext.shared.taskManager

        // Get task
        guard let task = await taskManager.getTask(taskId) else {
            return .error("Task not found: \(taskId). The task may have expired or the ID is invalid.")
        }

        // Get progress
        let progress = await taskManager.getIndexingProgress(taskId)

        // Build response based on task status
        switch task.status {
        case .working:
            return formatWorkingResponse(task: task, progress: progress)

        case .completed:
            // Get the final result
            if let result = await taskManager.getResult(taskId) {
                return result
            }
            return formatCompletedResponse(task: task, progress: progress)

        case .failed:
            return .error("Indexing failed: \(task.statusMessage ?? "Unknown error")")

        case .cancelled:
            return .error("Indexing was cancelled")

        case .inputRequired:
            return .error("Unexpected state: input_required")
        }
    }

    // MARK: - Private

    private func formatWorkingResponse(task: MCPTask, progress: IndexingProgress?) -> ToolCallResult {
        var response: [String: Any] = [
            "task_id": task.taskId,
            "status": "working",
        ]

        if let progress {
            response["phase"] = progress.phase.rawValue
            response["files_processed"] = progress.filesProcessed
            response["total_files"] = progress.totalFiles
            response["percent_complete"] = progress.percentComplete
            response["chunks_indexed"] = progress.chunksIndexed
            response["errors"] = progress.errors

            if let currentFile = progress.currentFile {
                response["current_file"] = currentFile
            }
        }

        if let statusMessage = task.statusMessage {
            response["message"] = statusMessage
        }

        guard let data = try? JSONCodec.serialize(response, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return .text("{\"task_id\": \"\(task.taskId)\", \"status\": \"working\"}")
        }
        return .text(string)
    }

    private func formatCompletedResponse(task: MCPTask, progress: IndexingProgress?) -> ToolCallResult {
        var response: [String: Any] = [
            "task_id": task.taskId,
            "status": "completed",
        ]

        if let progress {
            response["files_indexed"] = progress.filesProcessed
            response["chunks_indexed"] = progress.chunksIndexed
            response["errors"] = progress.errors
        }

        guard let data = try? JSONCodec.serialize(response, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return .text("{\"task_id\": \"\(task.taskId)\", \"status\": \"completed\"}")
        }
        return .text(string)
    }
}
