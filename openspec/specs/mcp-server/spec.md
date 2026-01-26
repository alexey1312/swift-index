# mcp-server Specification

## Purpose

Expose SwiftIndex semantic search capabilities to AI assistants via MCP protocol (version 2024-11-05).

## Requirements

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

### Requirement: index_codebase Tool

The system SHALL provide `index_codebase` MCP tool for project indexing.

Tool schema:

```json
{
  "name": "index_codebase",
  "description": "Index a Swift codebase for semantic search",
  "inputSchema": {
    "type": "object",
    "properties": {
      "path": { "type": "string", "description": "Absolute path to the directory to index" },
      "force": { "type": "boolean", "default": false, "description": "Force re-indexing even if files haven't changed" }
    },
    "required": ["path"]
  }
}
```

#### Scenario: Index new project

- **WHEN** calling index_codebase with path
- **THEN** project is indexed
- **AND** returns statistics (files, chunks, errors)

#### Scenario: Incremental index

- **WHEN** calling index_codebase on previously indexed project
- **THEN** only changed files are re-indexed
- **AND** returns incremental stats

#### Scenario: Force re-index

- **WHEN** calling with `force: true`
- **THEN** all files are re-indexed regardless of change status
- **AND** index is rebuilt from scratch

---

### Requirement: search_code Tool

The system SHALL provide `search_code` MCP tool for semantic search.

Tool schema:

```json
{
  "name": "search_code",
  "description": "Semantic search in indexed Swift codebase",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": { "type": "string", "description": "Natural language search query or code pattern" },
      "path": { "type": "string", "default": ".", "description": "Path to indexed codebase" },
      "limit": { "type": "integer", "default": 20 },
      "semantic_weight": { "type": "number", "default": 0.7, "description": "Weight for semantic search (0.0-1.0)" },
      "extensions": { "type": "string", "description": "Filter by file extensions (comma-separated)" },
      "path_filter": { "type": "string", "description": "Filter by path pattern (glob syntax)" },
      "format": { "type": "string", "enum": ["toon", "json", "human"], "description": "Output format" },
      "expand_query": { "type": "boolean", "default": false, "description": "Use LLM to expand query" },
      "synthesize": { "type": "boolean", "default": false, "description": "Generate LLM summary" }
    },
    "required": ["query"]
  }
}
```

#### Scenario: Simple search

- **WHEN** calling search_code with query "authentication"
- **THEN** returns relevant code chunks
- **AND** results include file paths and line numbers

#### Scenario: Search with limit

- **WHEN** calling with `limit: 5`
- **THEN** returns at most 5 results

#### Scenario: Search with path filter

- **WHEN** calling with `path_filter: "Sources/Auth/**"`
- **THEN** only searches in Auth directory

#### Scenario: Search with LLM enhancement

- **WHEN** calling with `expand_query: true` and `synthesize: true`
- **THEN** query is expanded with related terms
- **AND** results include AI summary and follow-up suggestions

#### Scenario: Search result format

- **WHEN** search returns results
- **THEN** each result includes:
  - `content` — code snippet
  - `path` — file path
  - `start_line` / `end_line` — location
  - `relevance_percent` — relevance score (0-100)
  - `kind` — chunk type
  - `symbols` — extracted symbol names
  - `signature` — function/type signature (optional)
  - `breadcrumb` — hierarchy path (optional)
  - `doc_comment` — documentation comment (optional)

---

### Requirement: search_docs Tool

The system SHALL provide `search_docs` MCP tool for documentation search.

Tool schema:

```json
{
  "name": "search_docs",
  "description": "Search indexed documentation using full-text search",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": { "type": "string", "description": "Natural language search query" },
      "path": { "type": "string", "default": ".", "description": "Path to indexed codebase" },
      "limit": { "type": "integer", "default": 10 },
      "path_filter": { "type": "string", "description": "Filter by path pattern (glob syntax)" },
      "format": { "type": "string", "enum": ["toon", "json", "human"], "description": "Output format" }
    },
    "required": ["query"]
  }
}
```

#### Scenario: Search documentation

- **WHEN** calling search_docs with query "installation"
- **THEN** returns relevant documentation snippets
- **AND** results include file paths and line numbers

#### Scenario: Filter by path

- **WHEN** calling with `path_filter: "docs/*.md"`
- **THEN** only searches in docs directory markdown files

---

### Requirement: code_research Tool

The system SHALL provide `code_research` MCP tool for deep analysis.

Tool schema:

```json
{
  "name": "code_research",
  "description": "Deep architectural analysis with multi-hop search",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": { "type": "string", "description": "Research question about codebase" },
      "path": { "type": "string", "default": ".", "description": "Path to indexed codebase" },
      "depth": { "type": "integer", "default": 2, "minimum": 1, "maximum": 5 },
      "focus": { "type": "string", "enum": ["architecture", "dependencies", "patterns", "flow"], "description": "Optional focus area" }
    },
    "required": ["query"]
  }
}
```

#### Scenario: Research protocol implementations

- **WHEN** calling with query "all implementations of Authenticatable"
- **THEN** returns all conforming types
- **AND** includes extension conformances

#### Scenario: Research with depth

- **WHEN** calling with `depth: 5`
- **THEN** follows references 5 levels deep
- **AND** maps dependency graph

#### Scenario: Research with focus

- **WHEN** calling with `focus: "architecture"`
- **THEN** analysis emphasizes architectural patterns
- **AND** identifies system structure

#### Scenario: Research call graph

- **WHEN** calling with query "what calls authenticate()"
- **THEN** returns callers and their callers
- **AND** shows call chain

---

### Requirement: Error Handling

The system SHALL return structured errors for tool failures using MCP ToolCallResult format.

Error format:

```json
{
  "content": [{ "type": "text", "text": "Error message describing the failure" }],
  "isError": true
}
```

Common error messages:

- `"No index found for path: /path. Run 'index_codebase' tool first."`
- `"Missing required argument: query"`
- `"Path does not exist or is not a directory: /path"`
- `"Query cannot be empty"`

#### Scenario: Search without index

- **WHEN** calling search_code on unindexed project
- **THEN** returns error with suggestion to index first

#### Scenario: Invalid path

- **WHEN** calling with non-existent path
- **THEN** returns error with path validation message

#### Scenario: Missing required argument

- **WHEN** calling without required argument
- **THEN** returns error identifying the missing argument

---

### Requirement: Progress Reporting

The system SHALL report progress for long-running operations.

#### Scenario: Index progress

- **WHEN** indexing large project
- **THEN** sends progress notifications
- **AND** includes files processed / total

#### Scenario: Search progress

- **WHEN** multi-hop search takes time
- **THEN** sends progress for each hop

### Requirement: Tool List Ordering

The system SHALL return MCP tools in deterministic order that preserves the registration order in `tools/list` responses.

#### Scenario: Registration order preserved

- **WHEN** tools are registered in a known order
- **THEN** `tools/list` returns tools in that same order

#### Scenario: Re-register preserves order

- **WHEN** a tool is registered with a name that already exists
- **THEN** the tool definition is replaced
- **AND** its position in the `tools/list` order does not change

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
