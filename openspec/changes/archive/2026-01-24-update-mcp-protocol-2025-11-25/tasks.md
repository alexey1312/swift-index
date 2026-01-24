## 1. Phase 1: Core Updates

- [x] 1.1 Update Protocol Version to `2025-11-25` in `MCPServer.swift`
- [x] 1.2 Update `MCPTool` struct with `title`, `outputSchema`, `annotations`
- [x] 1.3 Update definitions for all existing tools (`index_codebase`, `search_code`, etc.)
- [x] 1.4 Add `isInitialized` validation guard in `handleToolsCall`
- [x] 1.5 Add `contentTooLarge` and `requestTimeout` error codes

## 2. Phase 2: Cancellation Support

- [x] 2.1 Add `activeRequests` tracking to `MCPServer`
- [x] 2.2 Implement `notifications/cancelled` handler
- [x] 2.3 Implement `CancellationToken` actor pattern

## 3. Phase 3: Tasks API

- [x] 3.1 Define `MCPTask`, `TaskStatus`, and related types in `MCPTasks.swift`
- [x] 3.2 Implement `TaskManager` for storage and state management
- [x] 3.3 Add routes for `tasks/get`, `tasks/list`, `tasks/result`, `tasks/cancel`
- [x] 3.4 Update capabilities to include `tasks` support
- [x] 3.5 Update `IndexCodebaseTool` to support `taskSupport: "optional"`
- [x] 3.6 Implement task-augmented tool call handling

## 4. Phase 4: Polish

- [x] 4.1 Implement `MCPIcon` support in protocol and server info
- [x] 4.2 Add `structuredContent` to `ToolCallResult`
- [x] 4.3 Add `ContentAnnotations` support
- [x] 4.4 Implement progress notifications for tasks
- [x] 4.5 Update tests (`SwiftIndexMCPTests`) for new features
