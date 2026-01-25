# Documentation Search Benchmark

**Date**: 2026-01-25
**Version**: Current main branch
**Tool**: `.build/release/swiftindex search-docs`

## Overview

This benchmark evaluates the `search-docs` functionality for searching indexed documentation (InfoSnippets) in the SwiftIndex codebase.

## Discovery: Feature Not Yet Complete

During benchmark setup, we discovered that **info_snippets are not being stored during indexing**:

```bash
# After full re-index
$ sqlite3 .swiftindex/chunks.db "SELECT COUNT(*) FROM info_snippets;"
0

$ .build/release/swiftindex search-docs "configuration" --format human -l 5
No documentation found.
```

### Root Cause

The infrastructure exists but is not connected:

| Component                          | Status                                           |
| ---------------------------------- | ------------------------------------------------ |
| `InfoSnippet` model                | Implemented                                      |
| `InfoSnippetStore` protocol        | Implemented                                      |
| `GRDBChunkStore.insertSnippet()`   | Implemented                                      |
| `TreeSitterParser.parseMarkdown()` | Returns `.successWithSnippets(chunks, snippets)` |
| `IndexManager` snippet storage     | **Not implemented**                              |

The parser returns `ParseResult.successWithSnippets(chunks, snippets)` for markdown files, but `IndexManager` only stores chunks, not snippets.

### Location of Gap

`Sources/SwiftIndexCore/Storage/IndexManager.swift` needs to:

1. Extract snippets from `ParseResult.snippets`
2. Call `chunkStore.insertSnippetBatch(snippets)`

## Benchmark Queries (20 queries, 4 per category)

### Category A: Exact Terms (direct keyword matches)

1. `TOML configuration` - config docs
2. `HybridSearchEngine` - search engine docs
3. `MCP server` - MCP documentation
4. `embedding provider` - provider docs

### Category B: Synonyms/Variants

5. `setup instructions` - installation docs
6. `output formats` - format documentation
7. `vector index` - HNSW/USearch docs
8. `query expansion` - LLM enhancement docs

### Category C: How-to Questions

9. `how to install swiftindex`
10. `how to configure search weights`
11. `how to run tests`
12. `how to use CLI commands`

### Category D: Conceptual/Architecture

13. `architecture overview`
14. `search ranking algorithm`
15. `storage layer design`
16. `privacy and local processing`

### Category E: Cross-cutting/Troubleshooting

17. `performance optimization`
18. `error handling`
19. `API keys configuration`
20. `build and release process`

## Methodology

### Planned Approach (when feature is complete)

1. **Tool**: `.build/release/swiftindex search-docs`
2. **Index**: Documentation snippets from markdown files
3. **Format**: `--format human` for evaluation
4. **Limit**: Default 5 results (P@5 scoring)

### Current Approach (workaround)

Since `search-docs` returns no results, we compare:

1. **grep baseline**: `grep -r` on markdown files
2. **code search**: `swiftindex search` (searches code chunks, not docs)

## Metrics

| Metric             | Description                                    |
| ------------------ | ---------------------------------------------- |
| P@5                | Relevant results in top 5 (0-5 scale)          |
| Breadcrumb Quality | Is hierarchy helpful? (for docs with sections) |
| Response Time      | ms per query                                   |

## Documentation Files in Project

```
docs/search-features.md
docs/search-enhancement.md
CLAUDE.md (symlink to AGENTS.md)
CLAUDE.local.md
```

## Next Steps

1. Implement snippet storage in `IndexManager`
2. Re-run this benchmark
3. Compare semantic search vs BM25-only for docs

## Reference: Code Search Alternative

For code-related documentation, `swiftindex search` can find doc comments:

```bash
$ .build/release/swiftindex search "configuration" --format human -l 5
```

This searches code chunks which include doc comments extracted by parsers.
