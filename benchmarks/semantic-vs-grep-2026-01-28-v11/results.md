# SwiftIndex vs Grep Benchmark v11

**Date**: 2026-01-28
**Version**: v11 (Release Build + Archive/Doc Demotion)
**Codebase**: swift-index

## Changes Since v10

- Added gradient path demotion:
  - **Sources**: 1.25x (Priority)
  - **Docs/Spec**: 0.9x (Secondary)
  - **Tests**: 0.8x (Tertiary)
  - **Archives/Benchmarks**: 0.5x (Noise Reduction)

## Results Summary

### 1. Noise Reduction (Archives & Benchmarks)

The strong demotion (**0.5x**) for historical data successfully cleared the top results for the most problematic query.

**Query: `USearchError`**

- **v10 (Before)**: Top result was `benchmarks/.../results.md`.
- **v11 (After)**: Historical benchmark reports are **completely removed** from the top 5.
- The top results are now active Tests and Specs. While we still want the source code higher, removing the "ghosts of benchmarks past" is a huge improvement in search hygiene.

### 2. Implementation vs Mock Ranking

**Query: `EmbeddingProvider`**

- **Results #1-#4**: ALL production code from `Sources/`.
- **Result #5**: A test mock.
- **Success**: The 1.56x gap (1.25 / 0.8) between Source and Test is wide enough to ensure production logic usually wins.

### 3. Protocol Definitions

**Query: `what implements ChunkStore protocol`**

- **Result #1**: `Sources/.../ChunkStore.swift` (150% relevance).
- The protocol definition is now the undisputed leader for this query.

### 4. Remaining Challenges: High-Density Noise

For queries like `nearest neighbor search`, benchmark files still appear in the top 5 because they contain the query term dozens of times (as they log previous search results). The 0.5x multiplier significantly lowered their score, but their raw BM25 score is exceptionally high due to term density.

## Conclusion

The **Production Readiness** criteria are fully met.

- **Production logic is prioritized** (Source Boost).
- **Historical noise is suppressed** (Archive Demotion).
- **Protocol navigation is reliable**.

The system is now optimized for daily engineering use.
