# Результаты бенчмарка v3

## Сводная таблица

| #  | Запрос                               | Категория   | SwiftIndex v3 | Изменение vs v2 | Победитель     |
| -- | ------------------------------------ | ----------- | ------------- | --------------- | -------------- |
| 1  | `HybridSearchEngine`                 | A: Точный   | 5/5 ✓         | =               | **Ничья**      |
| 2  | `USearchError`                       | A: Точный   | 0/5           | ↓ (было 1/5)    | **Grep**       |
| 3  | `EmbeddingProvider`                  | A: Точный   | 5/5 ✓         | =               | **Ничья**      |
| 4  | `rrfK`                               | A: Точный   | 5/5 ✓         | =               | **Ничья**      |
| 5  | `text vectorization`                 | B: Синоним  | 5/5 ✓         | ↑ (было 4/5)    | **SwiftIndex** |
| 6  | `store vectors persistently`         | B: Синоним  | 5/5 ✓         | =               | **SwiftIndex** |
| 7  | `nearest neighbor search`            | B: Синоним  | 3/5           | ↓ (было 4/5)    | **Grep**       |
| 8  | `combine search results`             | B: Синоним  | 5/5 ✓         | ↑ (было 4/5)    | **SwiftIndex** |
| 9  | `how does search ranking work`       | C: Концепт  | 5/5 ✓         | ↑ (было 4/5)    | **SwiftIndex** |
| 10 | `how are code chunks parsed`         | C: Концепт  | 5/5 ✓         | =               | **SwiftIndex** |
| 11 | `what happens when file indexed`     | C: Концепт  | 5/5 ✓         | =               | **SwiftIndex** |
| 12 | `how are embedding failures handled` | C: Концепт  | 4/5           | =               | **SwiftIndex** |
| 13 | `actor pattern for thread safety`    | D: Паттерн  | 5/5 ✓         | =               | **SwiftIndex** |
| 14 | `what implements ChunkStore`         | D: Паттерн  | 4/5 ✓         | ↑ (было 3/5)    | **SwiftIndex** |
| 15 | `how are providers configured`       | D: Паттерн  | 5/5 ✓         | ↑ (было 4/5)    | **SwiftIndex** |
| 16 | `where is caching used`              | D: Паттерн  | 5/5 ✓         | =               | **SwiftIndex** |
| 17 | `async await concurrency`            | E: Сквозной | 5/5 ✓         | ↑ (было 4/5)    | **SwiftIndex** |
| 18 | `error types and handling`           | E: Сквозной | 5/5 ✓         | =               | **SwiftIndex** |
| 19 | `TOML config loading validation`     | E: Сквозной | 5/5 ✓         | =               | **SwiftIndex** |
| 20 | `how is search engine tested`        | E: Сквозной | 5/5 ✓         | =               | **SwiftIndex** |

## Анализ по категориям

### Категория A: Точные ключевые слова (4 запроса)

| Метрика          | v1   | v2  | v3   | Изменение v2→v3 |
| ---------------- | ---- | --- | ---- | --------------- |
| Avg P@5          | 4.25 | 4.0 | 3.75 | ↓ -0.25         |
| Побед SwiftIndex | 0    | 0   | 0    | =               |

**Вывод**: Регрессия на `USearchError` (0/5) — редкий термин совсем не находится. BM25 матчит "Search" вместо точного термина.

### Категория B: Синонимы и варианты (4 запроса)

| Метрика          | v1  | v2   | v3  | Изменение v2→v3 |
| ---------------- | --- | ---- | --- | --------------- |
| Avg P@5          | 4.0 | 4.25 | 4.5 | ↑ +0.25         |
| Побед SwiftIndex | 2   | 2    | 3   | ↑ +1            |

**Вывод**: Улучшение на `text vectorization` и `combine search results`. Небольшая регрессия на `nearest neighbor search` (Comparable extensions).

### Категория C: Вопросы о реализации (4 запроса)

| Метрика          | v1   | v2  | v3   | Изменение v2→v3 |
| ---------------- | ---- | --- | ---- | --------------- |
| Avg P@5          | 3.75 | 4.5 | 4.75 | ↑ +0.25         |
| Побед SwiftIndex | 2    | 4   | 4    | =               |

**Вывод**: Стабильно отличные результаты. Улучшение на `how does search ranking work`.

### Категория D: Паттерны и дизайн (4 запроса)

| Метрика          | v1  | v2   | v3   | Изменение v2→v3 |
| ---------------- | --- | ---- | ---- | --------------- |
| Avg P@5          | 3.5 | 4.25 | 4.75 | ↑ +0.5          |
| Побед SwiftIndex | 2   | 3    | 4    | ↑ +1            |

**Вывод**: Значительное улучшение! `what implements ChunkStore` теперь находит GRDBChunkStore.

### Категория E: Сквозные вопросы (4 запроса)

| Метрика          | v1   | v2   | v3  | Изменение v2→v3 |
| ---------------- | ---- | ---- | --- | --------------- |
| Avg P@5          | 4.25 | 4.75 | 5.0 | ↑ +0.25         |
| Побед SwiftIndex | 2    | 4    | 4   | =               |

**Вывод**: Идеальные результаты! Все 4 запроса имеют 5/5 релевантность.

## Итоговый счёт

| Метрика           | v1  | v2   | v3   | Изменение v2→v3 |
| ----------------- | --- | ---- | ---- | --------------- |
| Побед SwiftIndex  | 8   | 13   | 15   | ↑ +2            |
| Ничьих            | 7   | 3    | 3    | =               |
| Поражений         | 5   | 4    | 2    | ↓ -2            |
| **Avg P@5 (все)** | 3.9 | 4.35 | 4.55 | ↑ +0.2          |

**Победитель**: SwiftIndex (значительное улучшение)

## Ключевые улучшения

### 1. `what implements ChunkStore` (3/5 → 4/5)

**Ключевое улучшение proposal!**

Теперь находит `GRDBChunkStore` с 106% релевантностью:

```
[1] MockChunkStore (actor : ChunkStore) — 172%
[2] MockChunkStoreWithSnippets (actor : ChunkStore, InfoSnippetStore) — 142%
[3] GRDBChunkStore (public actor : ChunkStore, InfoSnippetStore) — 106% ✓
```

Type declaration chunks работают!

### 2. `actor that implements ChunkStore` — новый запрос

Специально для проверки type declarations:

- MockChunkStore: 172%
- MockChunkStoreWithSnippets: 142%
- **GRDBChunkStore: 106%** — появляется в топ-3!

### 3. `combine search results` (4/5 → 5/5)

Теперь все 5 результатов релевантны:

- HybridSearchEngine.search (#2)
- IndexManager.searchHybrid (#5)

### 4. `how does search ranking work` (4/5 → 5/5)

Улучшенная индексация находит:

- SearchResult.semanticRank
- BM25Search.result (scoring)
- SemanticSearch.result (ranking)
- searchRelevanceRanking test

### 5. `async await concurrency` (4/5 → 5/5)

Все результаты про concurrency:

- concurrentBatching test
- async let patterns
- EmbeddingBatcherBatchingTests

## Регрессии

### 1. `USearchError` (1/5 → 0/5)

Ни один результат не содержит USearchError. Все результаты про "Search":

- TOMLConfig.search
- SearchOptions.default
- BM25Search (actor declaration)

**Причина**: BM25 разбивает "USearchError" на токены и матчит "Search".

**Решение**: Добавить exact match boost для редких терминов.

### 2. `nearest neighbor search` (4/5 → 3/5)

Результаты #1 и #2 — Comparable extensions (нерелевантно):

- SearchResult : Comparable
- InfoSnippetSearchResult : Comparable

USearchVectorStore (HNSW nearest neighbor) появляется только на #3.

**Причина**: "search" матчит SearchResult по BM25.

## Метрики для отслеживания

| Метрика                 | v1     | v2     | v3     | Целевое |
| ----------------------- | ------ | ------ | ------ | ------- |
| Avg P@5 (все запросы)   | 3.9/5  | 4.35/5 | 4.55/5 | 4.5/5 ✓ |
| Avg P@5 (синонимы)      | 4.0/5  | 4.25/5 | 4.5/5  | 4.8/5   |
| Avg P@5 (концепты)      | 3.75/5 | 4.5/5  | 4.75/5 | 4.5/5 ✓ |
| Avg P@5 (паттерны)      | 3.5/5  | 4.25/5 | 4.75/5 | 4.5/5 ✓ |
| "implements X" точность | 40%    | 60%    | 80%    | 90%     |
| Win rate vs grep        | 40%    | 65%    | 75%    | 75% ✓   |

## Сравнение версий

| Версия | Avg P@5 | Побед | Ничьих | Поражений | Ключевое изменение                         |
| ------ | ------- | ----- | ------ | --------- | ------------------------------------------ |
| v1     | 3.9     | 8     | 7      | 5         | Baseline                                   |
| v2     | 4.35    | 13    | 3      | 4         | RRF fusion + conformance indexing          |
| v3     | 4.55    | 15    | 3      | 2         | Type declaration chunks + signature search |
