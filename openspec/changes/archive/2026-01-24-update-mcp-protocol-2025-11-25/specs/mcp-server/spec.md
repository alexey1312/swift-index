## MODIFIED Requirements

### Requirement: MCP Server Protocol

The system SHALL implement Model Context Protocol (MCP) server over stdio, compliant with version 2025-11-25.

Protocol requirements:

- JSON-RPC 2.0 message format
- stdio transport (stdin/stdout)
- Tool discovery via `tools/list`
- Tool execution via `tools/call`
- Tasks API via `tasks/*` (NEW)
- Cancellation via `notifications/cancelled` (NEW)

#### Scenario: Server starts

- **WHEN** MCP client connects via stdio
- **THEN** server responds to initialization with protocol version 2025-11-25
- **AND** advertises available tools and capabilities (including tasks)

#### Scenario: Tool discovery

- **WHEN** client sends `tools/list` request
- **THEN** server returns all tools with updated schemas
- **AND** tools include `title`, `outputSchema`, `annotations`, and `icons` fields

## ADDED Requirements

### Requirement: Tasks API

The system SHALL provide `tasks/*` endpoints for managing long-running operations, particularly for `index_codebase`.

Endpoints:

- `tasks/list`: List active tasks
- `tasks/cancel`: Cancel a task
- `tasks/get`: Get task status
- `tasks/result`: Get task result (blocking)

#### Scenario: Create task via tool

- **WHEN** client calls a tool with `task` parameter
- **THEN** server returns a `taskId` immediately
- **AND** executes tool in background

#### Scenario: Cancel task

- **WHEN** client requests `tasks/cancel` with taskId
- **THEN** task is cancelled and status updated to `cancelled`

### Requirement: Content Types and Annotations

The system SHALL support new content types and annotations.

Supported types:

- `audio`: Base64 encoded audio data
- `resource_link`: Enhanced with mimeType and description

#### Scenario: Audio content

- **WHEN** tool returns audio
- **THEN** result contains `type: "audio"` and base64 data

#### Scenario: Content annotations

- **WHEN** tool returns content with metadata
- **THEN** result includes `annotations` (audience, priority)
