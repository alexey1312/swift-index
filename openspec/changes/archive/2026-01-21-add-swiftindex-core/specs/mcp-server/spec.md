## ADDED Requirements

### Requirement: MCP Server Protocol

The system SHALL implement Model Context Protocol (MCP) server over stdio.

Protocol requirements:

- JSON-RPC 2.0 message format
- stdio transport (stdin/stdout)
- Tool discovery via `tools/list`
- Tool execution via `tools/call`

#### Scenario: Server starts

- **WHEN** MCP client connects via stdio
- **THEN** server responds to initialization
- **AND** advertises available tools

#### Scenario: Tool discovery

- **WHEN** client sends `tools/list` request
- **THEN** server returns all 4 tools with schemas

---

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
      "path": { "type": "string", "description": "Path to codebase root" },
      "provider": { "type": "string", "enum": ["mlx", "ollama", "swift-embeddings", "voyage", "openai"] },
      "include_tests": { "type": "boolean", "default": false },
      "rebuild": { "type": "boolean", "default": false }
    },
    "required": ["path"]
  }
}
```

#### Scenario: Index new project

- **WHEN** calling index_codebase with path
- **THEN** project is indexed
- **AND** returns statistics (files, chunks, duration)

#### Scenario: Incremental index

- **WHEN** calling index_codebase on previously indexed project
- **THEN** only changed files are re-indexed
- **AND** returns incremental stats

#### Scenario: Index with specific provider

- **WHEN** calling with `provider: "ollama"`
- **THEN** uses Ollama for embeddings
- **AND** ignores default provider chain

#### Scenario: Include test files

- **WHEN** calling with `include_tests: true`
- **THEN** test files are indexed
- **AND** searchable alongside production code

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
      "query": { "type": "string", "description": "Natural language search query" },
      "limit": { "type": "integer", "default": 10 },
      "semantic_weight": { "type": "number", "default": 0.7 },
      "file_filter": { "type": "string", "description": "Glob pattern to filter files" }
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

#### Scenario: Search with file filter

- **WHEN** calling with `file_filter: "Sources/Auth/**"`
- **THEN** only searches in Auth directory

#### Scenario: Search result format

- **WHEN** search returns results
- **THEN** each result includes:
  - `content` — code snippet
  - `path` — file path
  - `startLine` / `endLine` — location
  - `score` — relevance score
  - `kind` — chunk type

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
      "depth": { "type": "integer", "default": 2, "minimum": 1, "maximum": 3 }
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

- **WHEN** calling with `depth: 3`
- **THEN** follows references 3 levels deep
- **AND** maps dependency graph

#### Scenario: Research call graph

- **WHEN** calling with query "what calls authenticate()"
- **THEN** returns callers and their callers
- **AND** shows call chain

---

### Requirement: watch_codebase Tool

The system SHALL provide `watch_codebase` MCP tool for file watching.

Tool schema:

```json
{
  "name": "watch_codebase",
  "description": "Watch codebase for changes and auto-update index",
  "inputSchema": {
    "type": "object",
    "properties": {
      "path": { "type": "string", "description": "Path to codebase root" },
      "action": { "type": "string", "enum": ["start", "stop", "status"] }
    },
    "required": ["path", "action"]
  }
}
```

#### Scenario: Start watching

- **WHEN** calling with `action: "start"`
- **THEN** file watcher is started
- **AND** returns confirmation

#### Scenario: Stop watching

- **WHEN** calling with `action: "stop"`
- **THEN** file watcher is stopped
- **AND** returns confirmation

#### Scenario: Watch status

- **WHEN** calling with `action: "status"`
- **THEN** returns watcher state
- **AND** includes files being watched

---

### Requirement: Error Handling

The system SHALL return structured errors for tool failures.

Error format:

```json
{
  "error": {
    "code": -32000,
    "message": "Index not found",
    "data": { "path": "/project", "suggestion": "Run index_codebase first" }
  }
}
```

#### Scenario: Search without index

- **WHEN** calling search_code on unindexed project
- **THEN** returns error with suggestion to index first

#### Scenario: Invalid path

- **WHEN** calling with non-existent path
- **THEN** returns error with path validation message

#### Scenario: Provider unavailable

- **WHEN** specified provider is unavailable
- **THEN** returns error with available providers list

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
