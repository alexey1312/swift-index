# MCP Server

SwiftIndex provides an MCP (Model Context Protocol) server for integration with AI assistants.

## Starting the Server

```bash
swiftindex serve
```

The server communicates over stdin/stdout using JSON-RPC 2.0.

## Supported Protocol Versions

- `2025-11-25` — full Tasks API and progress reporting support
- `2024-11-05` — basic support (Claude Code)

## Tools

| Tool             | Description                  |
| ---------------- | ---------------------------- |
| `index_codebase` | Index a codebase             |
| `search_code`    | Semantic code search         |
| `search_docs`    | Documentation search         |
| `code_research`  | Deep analysis with multi-hop |
| `watch_codebase` | File change monitoring       |

## Background Execution with Progress

For long-running operations (indexing large projects), we recommend using task-augmented calls. This allows you to:

- Receive progress updates
- Cancel operations
- Avoid timeouts

### Creating a Task

Add the `task` parameter to a `tools/call` request:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "index_codebase",
    "arguments": {
      "path": "/path/to/project"
    },
    "task": {
      "pollInterval": 2000,
      "ttl": 300000
    }
  }
}
```

`task` parameters:

- `pollInterval` — recommended polling interval in milliseconds (default: 1000)
- `ttl` — task time-to-live in milliseconds (task is cancelled after expiration)

### Response with taskId

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "task": {
      "taskId": "abc-123",
      "status": "working",
      "createdAt": "2025-01-26T10:00:00Z",
      "lastUpdatedAt": "2025-01-26T10:00:00Z",
      "pollInterval": 2000
    }
  }
}
```

### Checking Progress

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tasks/get",
  "params": {
    "taskId": "abc-123"
  }
}
```

Response:

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "task": {
      "taskId": "abc-123",
      "status": "working",
      "statusMessage": "Indexing: User.swift (45/120, 38%)",
      "createdAt": "2025-01-26T10:00:00Z",
      "lastUpdatedAt": "2025-01-26T10:00:15Z",
      "pollInterval": 2000
    }
  }
}
```

### statusMessage Formats

During indexing:

```
Initializing...
Collecting files...
Indexing: User.swift (45/120, 38%)
Saving index...
```

During code_research:

```
Loading configuration...
Initializing search engine...
Searching (1/3, 33%)
Analyzing references (2/3, 67%)
Generating analysis (3/3, 100%)
```

### Getting the Result

After task completion (`status: "completed"`):

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tasks/result",
  "params": {
    "taskId": "abc-123"
  }
}
```

### Cancelling a Task

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tasks/cancel",
  "params": {
    "taskId": "abc-123"
  }
}
```

### Listing All Tasks

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "tasks/list",
  "params": {
    "limit": 100
  }
}
```

## Task Statuses

| Status           | Description               |
| ---------------- | ------------------------- |
| `working`        | In progress               |
| `completed`      | Completed successfully    |
| `failed`         | Completed with error      |
| `cancelled`      | Cancelled                 |
| `input_required` | Input required (not used) |

## Tool Annotations

Each tool has annotations for clients:

| Tool             | readOnlyHint | idempotentHint |
| ---------------- | ------------ | -------------- |
| `index_codebase` | false        | true           |
| `search_code`    | true         | true           |
| `search_docs`    | true         | true           |
| `code_research`  | true         | true           |
| `watch_codebase` | false        | false          |

- `readOnlyHint: true` — tool does not modify state
- `idempotentHint: true` — repeated calls with same parameters are safe
