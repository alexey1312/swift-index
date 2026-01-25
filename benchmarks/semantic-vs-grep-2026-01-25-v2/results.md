# Результаты бенчмарка v2

## Сводная таблица

| #  | Запрос                               | Категория   | SwiftIndex v2 | Изменение vs v1 | Победитель     |
| -- | ------------------------------------ | ----------- | ------------- | --------------- | -------------- |
| 1  | `HybridSearchEngine`                 | A: Точный   | 5/5 ✓         | =               | **Ничья**      |
| 2  | `USearchError`                       | A: Точный   | 1/5           | ↓ (было 2/5)    | **Grep**       |
| 3  | `EmbeddingProvider`                  | A: Точный   | 5/5 ✓         | =               | **Ничья**      |
| 4  | `rrfK`                               | A: Точный   | 5/5 ✓         | =               | **Ничья**      |
| 5  | `text vectorization`                 | B: Синоним  | 4/5           | ↓ (было 5/5)    | **SwiftIndex** |
| 6  | `store vectors persistently`         | B: Синоним  | 5/5 ✓         | =               | **SwiftIndex** |
| 7  | `nearest neighbor search`            | B: Синоним  | 4/5           | =               | **Grep**       |
| 8  | `combine search results`             | B: Синоним  | 4/5 ✓         | ↑ (было 2/5)    | **SwiftIndex** |
| 9  | `how does search ranking work`       | C: Концепт  | 4/5 ✓         | ↑ (было 3/5)    | **SwiftIndex** |
| 10 | `how are code chunks parsed`         | C: Концепт  | 5/5 ✓         | ↑ (было 4/5)    | **SwiftIndex** |
| 11 | `what happens when file indexed`     | C: Концепт  | 5/5 ✓         | ↑ (было 4/5)    | **SwiftIndex** |
| 12 | `how are embedding failures handled` | C: Концепт  | 4/5           | =               | **SwiftIndex** |
| 13 | `actor pattern for thread safety`    | D: Паттерн  | 5/5 ✓         | ↑ (было 4/5)    | **SwiftIndex** |
| 14 | `what implements ChunkStore`         | D: Паттерн  | 3/5           | ↑ (было 2/5)    | **Grep**       |
| 15 | `how are providers configured`       | D: Паттерн  | 4/5 ✓         | ↑ (было 3/5)    | **SwiftIndex** |
| 16 | `where is caching used`              | D: Паттерн  | 5/5 ✓         | =               | **SwiftIndex** |
| 17 | `async await concurrency`            | E: Сквозной | 4/5 ✓         | ↑ (было 3/5)    | **SwiftIndex** |
| 18 | `error types and handling`           | E: Сквозной | 5/5 ✓         | ↑ (было 4/5)    | **SwiftIndex** |
| 19 | `TOML config loading validation`     | E: Сквозной | 5/5 ✓         | =               | **SwiftIndex** |
| 20 | `how is search engine tested`        | E: Сквозной | 5/5 ✓         | =               | **SwiftIndex** |

## Анализ по категориям

### Категория A: Точные ключевые слова (4 запроса)

| Метрика          | v1   | v2  | Изменение |
| ---------------- | ---- | --- | --------- |
| Avg P@5          | 4.25 | 4.0 | ↓ -0.25   |
| Побед SwiftIndex | 0    | 0   | =         |

**Вывод**: Небольшая регрессия на `USearchError` — редкий термин теперь хуже находится.

### Категория B: Синонимы и варианты (4 запроса)

| Метрика          | v1  | v2   | Изменение |
| ---------------- | --- | ---- | --------- |
| Avg P@5          | 4.0 | 4.25 | ↑ +0.25   |
| Побед SwiftIndex | 2   | 2    | =         |

**Вывод**: Улучшение на `combine search results` (+2 балла) — RRF fusion теперь находит HybridSearchEngine в топе.

### Категория C: Вопросы о реализации (4 запроса)

| Метрика          | v1   | v2  | Изменение |
| ---------------- | ---- | --- | --------- |
| Avg P@5          | 3.75 | 4.5 | ↑ +0.75   |
| Побед SwiftIndex | 2    | 4   | ↑ +2      |

**Вывод**: Значительное улучшение! Концептуальные "how" вопросы теперь находят правильные результаты.

### Категория D: Паттерны и дизайн (4 запроса)

| Метрика          | v1  | v2   | Изменение |
| ---------------- | --- | ---- | --------- |
| Avg P@5          | 3.5 | 4.25 | ↑ +0.75   |
| Побед SwiftIndex | 2   | 3    | ↑ +1      |

**Вывод**: Улучшение на `actor pattern` и `implements ChunkStore`, но конформансы всё ещё не идеальны.

### Категория E: Сквозные вопросы (4 запроса)

| Метрика          | v1   | v2   | Изменение |
| ---------------- | ---- | ---- | --------- |
| Avg P@5          | 4.25 | 4.75 | ↑ +0.5    |
| Побед SwiftIndex | 2    | 4    | ↑ +2      |

**Вывод**: Отличные результаты! Все 4 запроса теперь выигрывают у grep.

## Итоговый счёт

| Метрика           | v1  | v2   | Изменение |
| ----------------- | --- | ---- | --------- |
| Побед SwiftIndex  | 8   | 13   | ↑ +5      |
| Ничьих            | 7   | 3    | ↓ -4      |
| Поражений         | 5   | 4    | ↓ -1      |
| **Avg P@5 (все)** | 3.9 | 4.35 | ↑ +0.45   |

**Победитель**: SwiftIndex (значительное улучшение)

## Ключевые улучшения

### 1. `combine search results` (2/5 → 4/5)

Раньше возвращал `ConfigLoader.swift` ("multiple sources").
Теперь находит `HybridSearchEngine.search` и `HybridSearchTests.hybridSearchCombination`.

### 2. `how does search ranking work` (3/5 → 4/5)

Теперь находит `searchRelevanceRanking` тест и `SemanticSearch.searchRaw` с re-ranking логикой.

### 3. `how are code chunks parsed` (4/5 → 5/5)

Все 5 результатов теперь из `TreeSitterParser` — точно то, что нужно.

### 4. `actor pattern for thread safety` (4/5 → 5/5)

Находит `GlobMatcher`, `DescriptionGenerationState`, `WatcherState` и тесты с Counter.

### 5. `what implements ChunkStore` (2/5 → 3/5)

Улучшение, но всё ещё не идеально:

- #1: ChunkStore.swift (протокол) — теперь с 121% релевантностью!
- MockChunkStore появляется с описанием "mock implementation of ChunkStore"

## Оставшиеся проблемы

### 1. `USearchError` регрессия (2/5 → 1/5)

Редкий термин теперь хуже находится. Результаты:

- #1: TOMLConfig.search (нерелевантно)
- #2: SearchOptions.default (нерелевантно)

**Причина**: BM25 матчит "Search" вместо точного термина.

### 2. `what implements ChunkStore` не находит GRDBChunkStore

Actor definition `public actor GRDBChunkStore: ChunkStore` не появляется в топ-5.

**Гипотеза**: Определение актора не индексируется как отдельный chunk, или его conformances не попадают в FTS5.

## Метрики для отслеживания

| Метрика                 | v1     | v2     | Целевое |
| ----------------------- | ------ | ------ | ------- |
| Avg P@5 (все запросы)   | 3.9/5  | 4.35/5 | 4.5/5   |
| Avg P@5 (синонимы)      | 4.0/5  | 4.25/5 | 4.8/5   |
| Avg P@5 (концепты)      | 3.75/5 | 4.5/5  | 4.5/5 ✓ |
| "implements X" точность | 40%    | 60%    | 90%     |
