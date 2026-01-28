# Search Ranking Strategy & Insights

This document outlines the architectural decisions and ranking logic used in SwiftIndex to ensure high-quality search results across different types of files in a codebase.

## Hierarchy of Truth

SwiftIndex implements a "gradient ranking" system based on file paths to prioritize production logic while suppressing historical or testing noise.

| Priority         | Scope                     | Weight    | Purpose                                                                   |
| :--------------- | :------------------------ | :-------- | :------------------------------------------------------------------------ |
| **1. Primary**   | `Sources/`                | **1.25x** | **Production Logic**: The actual implementation that runs in the app.     |
| **2. Secondary** | `docs/`, `openspec/`      | **0.9x**  | **Intent & Specs**: Contextual documentation and planning files.          |
| **3. Tertiary**  | `Tests/`                  | **0.8x**  | **Examples**: Code usage examples and mocks.                              |
| **4. Submerged** | `benchmarks/`, `archive/` | **0.5x**  | **Noise Reduction**: Historical data and logs that cause false positives. |

### Rationale

- **Implementation First**: Developers usually look for _how a feature is implemented_. Boosting `Sources/` by 25% ensuring that real code beats test mocks even if the mock has a "cleaner" BM25 profile.
- **Active Docs vs. Archives**: Active specifications are kept near neutral (0.9x) to remain discoverable, while the `archive/` and `benchmarks/` folders are heavily demoted (0.5x) to prevent "keyword stuffing" from historical reports.
- **The 1.56x Gap**: The relative difference between production code (1.25) and tests (0.8) is **1.56x**. This specific gap was found during Benchmark v10 to be the "sweet spot" for ensuring `GRDBChunkStore` (Source) ranks above `MockChunkStore` (Test).

## Key Insights from Benchmarking (v1 - v11)

### 1. The "Protocol First" Rule

Generic queries for protocol names (e.g., `ChunkStore`) should always return the **Protocol Definition** as result #1.

- **Solution**: Added a high boost for type declarations (`protocol`, `actor`, `class`) and their signatures.
- **Result**: 150% relevance for protocol files.

### 2. CamelCase Identifier Splitting

Standard BM25 tokenizers split `USearchError` into `usearch` and `error`. This causes common terms like "Search" or "Error" to match thousands of unrelated chunks.

- **Solution**: Implemented `exactSymbolMatch` detection and applied a **2.5x boost** for exact CamelCase matches on rare terms.
- **Insight**: Partial match demotion (0.3x) is equally important to suppress the "Search" noise when the user specifically typed "USearch".

### 3. Conceptual Query Detection

Queries starting with "how to", "what implements", or "where is" imply a different intent than "find this symbol".

- **Solution**: Standard protocol extensions (like `Comparable`, `Equatable`) are demoted (**0.5x**) only for conceptual queries to prevent them from flooding results for "how does X work".

### 4. Self-Referential Noise

In projects that include benchmark results (like this one), the benchmark logs themselves become "term-dense" noise sources.

- **Finding**: The term `USearchError` appeared 50+ times in old benchmark results, making them rank #1 globally.
- **Fix**: Strong path-based demotion for `benchmarks/` was the only effective way to handle this without complex NLP.

## Performance Metrics

As of version **v11**:

- **P@5 (Precision at 5)**: 4.75 / 5.0
- **Implementation Accuracy**: 100% (Production code consistently ranks above Mocks).
- **Average Latency**: < 1.0s for hybrid search on 10k chunks.
