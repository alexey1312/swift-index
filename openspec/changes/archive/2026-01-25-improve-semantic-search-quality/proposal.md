# Change: Improve Semantic Search Quality

## Why

Benchmarks (2026-01-25) revealed significant issues with the current search implementation:

- `semantic_weight` parameter had no effect because RRF fusion ignored original scores.
- Queries like "what implements ChunkStore" failed to find relevant types because protocol conformances were not indexed.
- Generated descriptions were not being indexed in FTS, losing valuable context.

## What Changes

- **Score-Aware RRF Fusion**: Introduced a hybrid scoring mechanism that combines rank-based score with normalized original score, controlled by an `alpha` parameter.
- **Protocol Conformance Indexing**:
  - Parser now extracts inherited types and protocol conformances.
  - `CodeChunk` model includes a `conformances` list.
  - Storage layer indexes `conformances` in a dedicated column and FTS.
- **Metadata-Aware Re-ranking**: Semantic search now boosts results that match intent-specific criteria (e.g., "implements X").
- **Description Indexing**: `generated_description` is now stored and indexed in FTS.
- **Configuration**: Increased hybrid search fetch limit to improve recall before fusion.

## Impact

- **Search**: Significantly improved relevance for "implements" queries and better adherence to `semantic_weight` configuration.
- **Storage**: Database schema migration (v7) adds `conformances` and `generated_description` columns. Re-indexing required.
- **Parsing**: Swift syntax parsing now captures inheritance clauses.
