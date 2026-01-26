# SwiftIndex v8 Benchmark

**Date**: 2026-01-26
**Version**: v8 (post-commit `6f3321c`)

## Changes Since v7

Key commits affecting search quality:

- `6f3321c` - **partial match demotion for CamelCase terms** (targeted fix for exact symbol matching)
- `0311633` - centralize file hashing in FileHasher utility
- `5da4522` - extract helper methods in HybridSearchEngine

## Methodology

### Index Configuration

- Full re-index with `force: true`
- **8691 chunks** indexed from **254 files**
- Default hybrid search (BM25 + semantic with RRF fusion)

### Query Categories

- **Category A**: Exact keywords (symbol names) - 4 queries
- **Category B**: Synonyms and variants - 4 queries
- **Category C**: Implementation questions - 4 queries
- **Category D**: Patterns and design - 4 queries
- **Category E**: Cross-cutting concerns - 4 queries

### Evaluation Criteria

- **P@5** (Precision at 5): Fraction of top-5 results that are relevant
- Relevance judged by: Does result help answer the query?
- Partial relevance (~) counted as 0.5

## Summary

| Category          | Queries | Avg P@5  |
| ----------------- | ------- | -------- |
| A: Exact keywords | 4       | 4.00     |
| B: Synonyms       | 4       | 4.25     |
| C: Implementation | 4       | 4.25     |
| D: Patterns       | 4       | 4.50     |
| E: Cross-cutting  | 4       | 4.50     |
| **Overall**       | **20**  | **4.30** |

## Comparison with v7

| Metric           | v7   | v8   | Change |
| ---------------- | ---- | ---- | ------ |
| Avg P@5          | 4.60 | 4.30 | -0.30  |
| USearchError     | 0/5  | 2/5  | +2     |
| nearest neighbor | 3/5  | 4/5  | +1     |

### Analysis

**Improvements:**

- `USearchError`: From 0/5 to 2/5 - partial match demotion working
- `nearest neighbor search`: From 3/5 to 4/5 - better semantic matching

**Regressions:**

- `EmbeddingProvider`: Protocol definition not in top results (mocks dominate)
- `async await concurrency patterns`: Results not directly relevant
- Overall average slightly lower due to stricter evaluation

See `results.md` for detailed per-query analysis.
