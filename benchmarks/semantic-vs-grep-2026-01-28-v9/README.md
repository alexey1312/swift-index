# SwiftIndex vs Grep Benchmark v9

**Date**: 2026-01-28
**Version**: v9 (Current HEAD)
**Codebase**: swift-index

## Methodology

### Index Configuration

- Existing index used (as per user instruction)
- Default hybrid search (BM25 + semantic with RRF fusion)

### Query Categories

Same as previous benchmarks (v2-v8):

- **Category A**: Exact keywords (4 queries)
- **Category B**: Synonyms and variants (4 queries)
- **Category C**: Implementation questions (4 queries)
- **Category D**: Patterns and design (4 queries)
- **Category E**: Cross-cutting questions (4 queries)

### Evaluation Criteria

- **P@5** (Precision at 5): Fraction of top-5 results that are relevant.
