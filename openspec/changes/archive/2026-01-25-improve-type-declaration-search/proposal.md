# Change: Improve Type Declaration Search

## Why

Benchmark v2 выявил три критические проблемы качества поиска:

1. **Type declarations невидимы** — `public actor GRDBChunkStore: ChunkStore` не появляется в результатах поиска "implements ChunkStore", хотя conformances индексируются. Причина: большие типы разбиваются на method chunks, а declaration header теряется.

2. **Редкие термины регрессируют** — поиск `USearchError` возвращает `SearchOptions` из-за BM25 substring matching ("Search" в "USearchError").

3. **Conformance search неэффективен** — несмотря на boost 1.5x для conformances, реальные реализации протоколов (GRDBChunkStore) не попадают в топ-5.

**Benchmark metrics:**

- `what implements ChunkStore`: 3/5 (цель: 5/5)
- `USearchError`: 1/5 (регрессия с 2/5)
- Avg P@5 conformance queries: 60% (цель: 90%)

## What Changes

1. **Type Declaration Chunks** — создавать отдельные chunks для type declarations (class/struct/actor/enum) с полной информацией о conformances.

2. **Exact Symbol Matching** — добавить boost для точного совпадения symbol name при поиске редких терминов.

3. **Conformance-Aware Ranking** — улучшить ranking для "implements X" запросов, используя indexed conformances.

## Impact

- Affected specs: `parsing`, `search`
- Affected code:
  - `Sources/SwiftIndexCore/Parsing/SwiftSyntaxParser.swift`
  - `Sources/SwiftIndexCore/Search/BM25Search.swift`
  - `Sources/SwiftIndexCore/Search/HybridSearchEngine.swift`
  - `Sources/SwiftIndexCore/Storage/GRDBChunkStore.swift` (schema v8)
