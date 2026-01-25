# Documentation Search Benchmark Results

**Date**: 2026-01-25
**Status**: Feature Operational (after fix)

## Executive Summary

After implementing snippet storage in IndexManager, `search-docs` now works:

| Metric               | Value        |
| -------------------- | ------------ |
| Snippets Indexed     | 1927         |
| Avg Response Time    | ~3ms         |
| Queries with Results | 20/20 (100%) |

## Fix Applied

Added snippet storage to IndexManager:

```swift
// Sources/SwiftIndexCore/Storage/IndexManager.swift
@discardableResult
public func reindexSnippets(path: String, snippets: [InfoSnippet]) async throws -> Int

// Sources/swiftindex/Commands/IndexCommand.swift
let snippets = parseResult.snippets
if !snippets.isEmpty {
    snippetsIndexed = try await context.indexManager.reindexSnippets(path: path, snippets: snippets)
}
```

Also updated `.swiftindex.toml` to include `.md` files:

```toml
include_extensions = [".swift", ".m", ".h", ".md"]
```

## Query Results

### Category A: Exact Terms

| # | Query                | Results | Top Result                        | Relevance |
| - | -------------------- | ------- | --------------------------------- | --------- |
| 1 | `TOML configuration` | 5       | README.md > Configuration         | 31%       |
| 2 | `HybridSearchEngine` | 5       | benchmarks > Категория A          | 18%       |
| 3 | `MCP server`         | 5       | openspec/specs/mcp-server/spec.md | 31%       |
| 4 | `embedding provider` | 5       | README.md > Embedding Providers   | 26%       |

### Category B: Synonyms/Variants

| # | Query                | Results | Top Result                                            | Relevance |
| - | -------------------- | ------- | ----------------------------------------------------- | --------- |
| 5 | `setup instructions` | 3       | CLAUDE.local.md > Documentation                       | -         |
| 6 | `output formats`     | 3       | docs/search-features.md > Output Formats              | -         |
| 7 | `vector index`       | 3       | openspec/specs/storage/spec.md > Vector Index Storage | -         |
| 8 | `query expansion`    | 3       | docs/search-features.md > Query Expansion             | -         |

### Category C: How-to Questions

| #  | Query                             | Results | Top Result           | Notes            |
| -- | --------------------------------- | ------- | -------------------- | ---------------- |
| 9  | `how to install swiftindex`       | 3       | benchmarks/README.md | Self-referential |
| 10 | `how to configure search weights` | 3       | benchmarks/README.md | Self-referential |
| 11 | `how to run tests`                | 3       | benchmarks/README.md | Self-referential |
| 12 | `how to use CLI commands`         | 3       | benchmarks/README.md | Self-referential |

**Note**: How-to queries matched the benchmark README itself since it contains these exact phrases.

### Category D: Conceptual/Architecture

| #  | Query                          | Results | Top Result                                        | Relevance        |
| -- | ------------------------------ | ------- | ------------------------------------------------- | ---------------- |
| 13 | `architecture overview`        | 3       | benchmarks/README.md                              | Self-referential |
| 14 | `search ranking algorithm`     | 3       | benchmarks/README.md                              | Self-referential |
| 15 | `storage layer design`         | 3       | openspec/changes/archive > Phase 2: Storage Layer | -                |
| 16 | `privacy and local processing` | 3       | benchmarks/README.md                              | Self-referential |

### Category E: Cross-cutting/Troubleshooting

| #  | Query                       | Results | Top Result                                                      | Relevance |
| -- | --------------------------- | ------- | --------------------------------------------------------------- | --------- |
| 17 | `performance optimization`  | 3       | openspec/specs/storage/spec.md > Performance improvement        | -         |
| 18 | `error handling`            | 3       | docs/search-features.md                                         | -         |
| 19 | `API keys configuration`    | 3       | openspec/specs/configuration/spec.md > API Keys via Environment | -         |
| 20 | `build and release process` | 3       | openspec/changes/archive > Improve MLX defaults                 | -         |

## Performance Metrics

| Query Type            | Avg Time |
| --------------------- | -------- |
| Short (2-3 words)     | 2-3ms    |
| How-to phrases        | 5ms      |
| Multi-word conceptual | 3ms      |

## Observations

### Strengths

1. **Fast**: All queries complete in <5ms
2. **Breadcrumbs**: Location paths show document hierarchy
3. **100% recall**: Every query returns results

### Weaknesses

1. **Self-referential bias**: Benchmark README matches many queries
2. **BM25 only**: No semantic understanding, exact term matching
3. **No relevance differentiation**: Many results show same % relevance

### Recommendations

1. **Exclude benchmark files** from search during evaluation
2. **Add semantic search** for info_snippets (embeddings)
3. **Improve relevance scoring** for better differentiation
4. **Consider TF-IDF boosts** for rare terms

## Comparison: Before vs After Fix

| Aspect               | Before | After       |
| -------------------- | ------ | ----------- |
| Snippets in DB       | 0      | 1927        |
| Queries with results | 0/20   | 20/20       |
| Response time        | N/A    | ~3ms        |
| Feature status       | Broken | Operational |

## Files Changed

1. `Sources/SwiftIndexCore/Storage/IndexManager.swift`
   - Added `reindexSnippets()` method
   - Added `snippetCount()` method
   - Updated `clear()` to clear snippets
   - Added `snippetCount` to `IndexStatistics`

2. `Sources/swiftindex/Commands/IndexCommand.swift`
   - Added snippet storage after chunk indexing

3. `.swiftindex.toml`
   - Added `.md` to `include_extensions`
