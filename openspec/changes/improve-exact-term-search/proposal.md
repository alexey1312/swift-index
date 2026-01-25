# Change: Improve Exact Term Search and Result Ranking

## Why

Benchmark v3 (2026-01-25) выявил две регрессии:

1. **USearchError не находится (0/5)** — редкие термины полностью теряются, BM25 токенизирует "USearchError" и матчит "Search" в других символах
2. **nearest neighbor search (3/5)** — Comparable extensions загрязняют результаты концептуальных запросов
3. **GRDBChunkStore не на #1** — production implementation ниже mock implementations

Текущий exact_symbol_boost (2.0x) в спецификации не реализован или недостаточен.

## What Changes

### 1. Implement Exact Symbol Match Boost

- Добавить определение частоты термина в индексе
- Для терминов с < 10 совпадений применять 2.5x boost при точном match в symbols
- Приоритизировать symbol field над content field для редких терминов

### 2. Standard Protocol Extension Demotion

- Определить список standard protocols: Comparable, Equatable, Hashable, Codable, Sendable
- Для концептуальных запросов ("how", "what", "where") понизить extension chunks для standard protocols
- Demotion factor: 0.5x

### 3. Source vs Test Ranking Boost

- Production code (`/Sources/`) получает +10% boost
- Test code (`/Tests/`) без boost
- Применяется после всех остальных boost factors

### 4. Public Modifier Boost

- Type declarations с `public` модификатором получают +10% boost
- Помогает ранжировать production implementations выше mock implementations

## Impact

- Affected specs: `search`
- Affected code:
  - `Sources/SwiftIndexCore/Search/HybridSearchEngine.swift`
  - `Sources/SwiftIndexCore/Search/SemanticSearch.swift`
  - `Sources/SwiftIndexCore/Storage/GRDBChunkStore.swift` (term frequency)

## Expected Results

| Запрос                       | v3  | Expected                |
| ---------------------------- | --- | ----------------------- |
| `USearchError`               | 0/5 | 4/5                     |
| `nearest neighbor search`    | 3/5 | 5/5                     |
| `what implements ChunkStore` | 4/5 | 5/5 (GRDBChunkStore #1) |

## Metrics

| Метрика                   | v3   | Target |
| ------------------------- | ---- | ------ |
| Avg P@5                   | 4.55 | 4.7    |
| Exact term match accuracy | 70%  | 95%    |
| Win rate vs grep          | 75%  | 80%    |
