# Change: Update MCPServer to Spec 2025-11-25

## Why

The current MCP implementation uses protocol version `2024-11-05`, which is outdated. The `2025-11-25` anniversary release introduces critical features like Tasks API for long-running operations (indexing), Cancellation support, and richer content types (Audio, Icons) that are needed for a complete MCP experience.

## What Changes

- **Protocol Version**: Update from `2024-11-05` to `2025-11-25`.
- **Tools**: Update `MCPTool` definition with `title`, `outputSchema`, `annotations`, and `icons`.
- **Tasks API**: Implement `tasks/*` endpoints for managing long-running operations.
- **Cancellation**: Handle `notifications/cancelled` and implement `CancellationToken`.
- **Content Types**: Add support for `audio` content and `resource_link` improvements.
- **Validation**: Strict `isInitialized` checks and new error codes.

## Impact

- **Affected Specs**: `mcp-server`
- **Affected Code**: `SwiftIndexMCP` (Server, Protocol, Context), all Tool implementations (`IndexCodebaseTool`, etc.).
