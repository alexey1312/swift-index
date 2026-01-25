# Documentation Search Benchmark Results

**Date**: 2026-01-25
**Status**: Feature Not Operational

## Executive Summary

The `search-docs` command returns no results because **info_snippets are not stored during indexing**. This benchmark documents:

1. The current state (0 snippets indexed)
2. Grep baseline showing what should be found
3. Code search comparison (works, searches code not docs)

## Current State

```bash
# Info snippets count
sqlite3 .swiftindex/chunks.db "SELECT COUNT(*) FROM info_snippets;"
# Result: 0

# All queries return empty
.build/release/swiftindex search-docs "configuration"
# Result: No documentation found.
```

## Query Results

### Category A: Exact Terms

| # | Query                | search-docs | grep hits | Expected docs                         |
| - | -------------------- | ----------- | --------- | ------------------------------------- |
| 1 | `TOML configuration` | 0           | 0         | AGENTS.md (Config section)            |
| 2 | `HybridSearchEngine` | 0           | 3         | AGENTS.md (Architecture)              |
| 3 | `MCP server`         | 0           | 3+        | AGENTS.md, docs/search-enhancement.md |
| 4 | `embedding provider` | 0           | 1         | AGENTS.md (CLI Commands)              |

### Category B: Synonyms/Variants

| # | Query                | search-docs | grep hits | Expected docs                      |
| - | -------------------- | ----------- | --------- | ---------------------------------- |
| 5 | `setup instructions` | 0           | 0         | AGENTS.md (Build Commands)         |
| 6 | `output formats`     | 0           | 2         | AGENTS.md, docs/search-features.md |
| 7 | `vector index`       | 0           | 1         | AGENTS.md (Dependencies)           |
| 8 | `query expansion`    | 0           | 3+        | docs/search-features.md            |

### Category C: How-to Questions

| #  | Query                             | search-docs | grep hits | Expected docs                |
| -- | --------------------------------- | ----------- | --------- | ---------------------------- |
| 9  | `how to install swiftindex`       | 0           | 0         | AGENTS.md (Homebrew section) |
| 10 | `how to configure search weights` | 0           | 0         | AGENTS.md (Search Config)    |
| 11 | `how to run tests`                | 0           | 0         | AGENTS.md (Build & Test)     |
| 12 | `how to use CLI commands`         | 0           | 1         | AGENTS.md (CLI Commands)     |

### Category D: Conceptual/Architecture

| #  | Query                          | search-docs | grep hits | Expected docs                |
| -- | ------------------------------ | ----------- | --------- | ---------------------------- |
| 13 | `architecture overview`        | 0           | 0         | AGENTS.md (Architecture)     |
| 14 | `search ranking algorithm`     | 0           | 0         | AGENTS.md (Ranking Boosts)   |
| 15 | `storage layer design`         | 0           | 0         | AGENTS.md (Module Structure) |
| 16 | `privacy and local processing` | 0           | 2         | docs/search-enhancement.md   |

### Category E: Cross-cutting/Troubleshooting

| #  | Query                       | search-docs | grep hits | Expected docs             |
| -- | --------------------------- | ----------- | --------- | ------------------------- |
| 17 | `performance optimization`  | 0           | 3+        | docs/search-features.md   |
| 18 | `error handling`            | 0           | 3+        | docs/search-features.md   |
| 19 | `API keys configuration`    | 0           | 0         | AGENTS.md (Env Variables) |
| 20 | `build and release process` | 0           | 0         | AGENTS.md (Distribution)  |

## Grep Baseline Examples

### Query: "MCP server"

```
docs/search-enhancement.md:## MCP Server Behavior
docs/search-enhancement.md:When search enhancement is enabled, the MCP server automatically:
AGENTS.md:- **CLI tool + MCP server** for AI assistants
```

### Query: "query expansion"

```
docs/search-features.md:## Query Expansion
docs/search-features.md:Query expansion uses an LLM to generate related search terms...
```

### Query: "privacy"

```
docs/search-enhancement.md:Uses Apple MLX for fully local text generation on Apple Silicon. Best for privacy-sensitive use cases...
docs/search-enhancement.md:Uses a local Ollama server for privacy-preserving LLM operations.
```

## Code Search Comparison

Code search (`swiftindex search`) works and finds relevant code chunks:

### Query: "TOML configuration"

```
[1] Sources/SwiftIndexCore/Configuration/TOMLConfig.swift:1-1
    Symbols: TOMLConfig
    Relevance: 59%
    Description: Defines a constant configuration object for TOML parsing...

[2] Sources/SwiftIndexCore/Configuration/TOMLConfigLoader.swift:48-48
    Symbols: TOMLConfigLoader.filePath
    Relevance: 49%
```

### Query: "MCP server"

```
[1] Sources/SwiftIndexMCP/Models/MCPServerInfo.swift:5-5
    Symbols: MCPServerInfo
    Doc: MCP server information (2025-11-25 spec).
    Relevance: 59%
```

## Implementation Gap

### Current Flow

```
Parser.parse()
  → ParseResult.successWithSnippets(chunks, snippets)
    → IndexManager stores chunks only
      → Snippets are discarded
```

### Required Fix

```swift
// In IndexManager.indexFile()
let result = parser.parse(content: content, path: path)
try await chunkStore.insertBatch(result.chunks)
try await chunkStore.insertSnippetBatch(result.snippets)  // ADD THIS
```

## Conclusions

1. **Feature Status**: Infrastructure complete, wiring incomplete
2. **Grep Effectiveness**: 12/20 queries have grep hits (60%)
3. **Code Search**: Good alternative for code-related docs
4. **Priority**: Implement snippet storage to enable doc search

## Recommendations

1. **Short-term**: Use `swiftindex search` for code-related documentation
2. **Medium-term**: Implement snippet storage in IndexManager
3. **Long-term**: Add semantic search for documentation (embeddings for InfoSnippets)
