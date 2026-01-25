# Результаты бенчмарка v7

## Сводная таблица

| #  | Запрос                               | Категория   | SwiftIndex v7 | Изменение vs v6 | Примечание                                          |
| -- | ------------------------------------ | ----------- | ------------- | --------------- | --------------------------------------------------- |
| 1  | `HybridSearchEngine`                 | A: Точный   | 5/5 ✓         | =               | Все результаты содержат HybridSearchEngine          |
| 2  | `USearchError`                       | A: Точный   | 0/5 ✗         | =               | **Регрессия сохраняется!** BM25Search, SearchEngine |
| 3  | `EmbeddingProvider`                  | A: Точный   | 5/5 ✓         | =               | embeddingProvider во всех результатах               |
| 4  | `rrfK`                               | A: Точный   | 5/5 ✓         | =               | rrfK во всех результатах                            |
| 5  | `text vectorization`                 | B: Синоним  | 5/5 ✓         | =               | vectorStore, vector references                      |
| 6  | `store vectors persistently`         | B: Синоним  | 5/5 ✓         | =               | VectorStore protocol #1                             |
| 7  | `nearest neighbor search`            | B: Синоним  | 3/5           | =               | Comparable extensions всё ещё #1-2                  |
| 8  | `combine search results`             | B: Синоним  | 5/5 ✓         | =               | HybridSearchEngine.search #1                        |
| 9  | `how does search ranking work`       | C: Концепт  | 5/5 ✓         | =               | HybridSearchEngine.search, semanticRank             |
| 10 | `how are code chunks parsed`         | C: Концепт  | 5/5 ✓         | =               | TreeSitterParser.chunks                             |
| 11 | `what happens when file indexed`     | C: Концепт  | 5/5 ✓         | =               | recordIndexed, indexFile                            |
| 12 | `how are embedding failures handled` | C: Концепт  | 4/5           | =               | embeddings references, нет явной error handling     |
| 13 | `actor pattern for thread safety`    | D: Паттерн  | 5/5 ✓         | =               | 5 актеров: TaskManager, GlobMatcher, etc.           |
| 14 | `what implements ChunkStore`         | D: Паттерн  | 5/5 ✓         | =               | ChunkStore 150%, MockChunkStore 79%                 |
| 15 | `how are providers configured`       | D: Паттерн  | 5/5 ✓         | =               | EmbeddingProviderRegistry                           |
| 16 | `where is caching used`              | D: Паттерн  | 5/5 ✓         | =               | cachePath, caching tests                            |
| 17 | `async await concurrency`            | E: Сквозной | 5/5 ✓         | =               | concurrentBatching, maxConcurrentTasks              |
| 18 | `error types and handling`           | E: Сквозной | 5/5 ✓         | =               | TaskError, ParseError, ConfigError                  |
| 19 | `TOML config loading validation`     | E: Сквозной | 5/5 ✓         | =               | TOMLConfigValidator, TOMLConfigLoaderTests          |
| 20 | `how is search engine tested`        | E: Сквозной | 5/5 ✓         | =               | BM25Search, HybridSearchEngine, E2ETests            |

## Критическая проблема: `USearchError` (0/5 - сохраняется)

**Проблема не исправлена в v7!**

### Фактический результат v7

```
[1] BM25Search:27 - actor BM25Search : SearchEngine (47%)
[2] TOMLConfig.search - var search : SearchSection? (52%)
[3] SearchEngine:9 - protocol SearchEngine : Sendable (46%)
[4] PartialConfig.searchEnhancement (46%)
[5] SearchCommand.results (47%)
```

### Grep находит

```bash
$ grep -rn "USearchError" --include="*.swift"
Sources/SwiftIndexCore/Storage/USearchVectorStore.swift:145
Tests/SwiftIndexCoreTests/CamelCaseSearchTests.swift
Tests/SwiftIndexCoreTests/SearchTokenizationTests.swift:36
Tests/SwiftIndexCoreTests/StorageTests.swift:580-587
```

### Анализ

BM25 матчит "Search" substring в:

- `BM25Search` → содержит "Search"
- `SearchEngine` → содержит "Search"
- `SearchSection` → содержит "Search"

Но `USearchError` в чанке `USearchVectorStore.add` (строки 120-176) не матчится, потому что:

1. `USearchError` — редкий термин внутри content, не в symbols
2. BM25 предпочитает частые "Search" в названиях

### Рекомендация

Для v8 нужно:

1. Добавить content-based exact match для CamelCase терминов
2. Или проиндексировать `catch` clauses как отдельные чанки

## Проблема: `nearest neighbor search` (3/5 - сохраняется)

### Фактический результат v7

```
[1] SearchResult : Comparable (36%)
[2] InfoSnippetSearchResult : Comparable (35%)
[3] USearchVectorStoreTests.searchWithThreshold (34%)
[4] USearchVectorStoreTests.results (32%)
[5] LLMSearchEnhancementE2ETests (32%)
```

### Анализ

Comparable extensions продолжают доминировать для запросов со словом "search".
Semantic search не достаточно сильный, чтобы понять intent "nearest neighbor" → vector search.

### Рекомендация

Добавить демоцию Comparable/Equatable extensions для концептуальных запросов.

## Анализ по категориям

### Категория A: Точные ключевые слова (4 запроса)

| Метрика          | v6   | v7   | Изменение |
| ---------------- | ---- | ---- | --------- |
| Avg P@5          | 3.75 | 3.75 | =         |
| Побед SwiftIndex | 3    | 3    | =         |

**Вывод**: Без изменений. USearchError регрессия сохраняется.

### Категория B: Синонимы и варианты (4 запроса)

| Метрика          | v6  | v7  | Изменение |
| ---------------- | --- | --- | --------- |
| Avg P@5          | 4.5 | 4.5 | =         |
| Побед SwiftIndex | 3   | 3   | =         |

**Вывод**: Стабильно.

### Категория C: Вопросы о реализации (4 запроса)

| Метрика          | v6   | v7   | Изменение |
| ---------------- | ---- | ---- | --------- |
| Avg P@5          | 4.75 | 4.75 | =         |
| Побед SwiftIndex | 4    | 4    | =         |

**Вывод**: Стабильно отлично.

### Категория D: Паттерны и дизайн (4 запроса)

| Метрика          | v6 | v7 | Изменение |
| ---------------- | -- | -- | --------- |
| Avg P@5          | 5  | 5  | =         |
| Побед SwiftIndex | 4  | 4  | =         |

**Вывод**: Идеально!

### Категория E: Сквозные вопросы (4 запроса)

| Метрика          | v6 | v7 | Изменение |
| ---------------- | -- | -- | --------- |
| Avg P@5          | 5  | 5  | =         |
| Побед SwiftIndex | 4  | 4  | =         |

**Вывод**: Идеально!

## Итоговый счёт

| Метрика           | v6   | v7   | Изменение |
| ----------------- | ---- | ---- | --------- |
| Побед SwiftIndex  | 15   | 15   | =         |
| Ничьих            | 3    | 3    | =         |
| Поражений         | 2    | 2    | =         |
| **Avg P@5 (все)** | 4.60 | 4.60 | =         |

**Результат**: Стабильная производительность. Последние коммиты не вызвали регрессий, но и не исправили известные проблемы.

## Сравнение версий

| Версия | Avg P@5 | Побед | Ключевое изменение                              |
| ------ | ------- | ----- | ----------------------------------------------- |
| v1     | 3.90    | 8     | Baseline                                        |
| v2     | 4.35    | 13    | RRF Fusion                                      |
| v3     | 4.55    | 15    | Type Declarations                               |
| v4     | 4.55    | 15    | Exact Search (без явного эффекта)               |
| v5     | 4.60    | 15    | Snippets + расширенное покрытие                 |
| v6     | 4.60    | 15    | CamelCase exact match (регрессия USearchError!) |
| v7     | 4.60    | 15    | FTS improvements (стабильно)                    |

## Детальные результаты топ-5

### Запрос #1: HybridSearchEngine (5/5 ✓)

```
[1] SearchDocsCommand.searchEngine - let searchEngine (63%)
    → Initializes a HybridSearchEngine...
[2] LLMSearchEnhancementE2ETests.searchEngine (64%)
    → Initializes a HybridSearchEngine...
[3] LLMSearchEnhancementPerformanceTests.searchEngine (64%)
    → Initializes a HybridSearchEngine...
[4] LLMSearchEnhancementPerformanceTests.searchEngine (64%)
    → Defines a search engine using HybridSearchEngine...
[5] E2ETests.searchEngine (64%)
    → Initializes a HybridSearchEngine...
```

**Анализ**: Все результаты инициализируют или используют HybridSearchEngine. Идеально.

### Запрос #8: combine search results (5/5 ✓)

```
[1] HybridSearchEngine.search (54%)
    → Performs a hybrid search combining BM25 and semantic methods
[2] HybridSearchEngine.EnhancedSearchResult.results (51%)
    → Stores an array of search results
[3] HybridSearchEngine extension (48%)
    → Implements enhanced searches with query expansion and result fusion
[4] SearchCommand.results (50%)
[5] SearchCodeTool.results (50%)
```

**Анализ**: #1 — идеальный результат! Метод `search` именно "combines" результаты.

### Запрос #13: actor pattern for thread safety (5/5 ✓)

```
[1] TaskManager actor (58%)
[2] GlobMatcher actor (55%)
[3] FileWatcher actor (53%)
[4] IndexManager actor (53%)
[5] HubModelManager actor (49%)
```

**Анализ**: 5 разных актеров! Отличное покрытие паттерна.

### Запрос #14: what implements ChunkStore (5/5 ✓)

```
[1] ChunkStore protocol (150%) ← высокий boost!
[2] ChunkStore full definition (118%)
[3] HybridSearchEngine.chunkStore (73%)
[4] MockChunkStore : ChunkStore (79%) ← имплементация!
[5] SemanticSearch.chunkStore (71%)
```

**Анализ**: Protocol definition с boost 150%, MockChunkStore в топ-5.

## Рекомендации для v8

### Критические (влияют на P@5)

1. **Исправить USearchError поиск**
   - Добавить content-based exact match для редких CamelCase терминов
   - Или индексировать error handling patterns как отдельные чанки

2. **Демоция Comparable extensions**
   - Для концептуальных запросов ("nearest neighbor", "how does X work")
   - Понизить ранг generic protocol conformances

### Желательные (улучшение UX)

3. **Улучшить embedding failures query**
   - Возможно нужен synonym expansion: "failures" → "errors", "catch", "throw"

4. **Добавить intent detection**
   - "nearest neighbor" → vector search intent
   - "error handling" → try/catch intent

## Метрики для отслеживания

| Метрика          | v7     | Целевое v8 | Приоритет |
| ---------------- | ------ | ---------- | --------- |
| USearchError     | 0/5    | 4/5        | Critical  |
| nearest neighbor | 3/5    | 4/5        | High      |
| Avg P@5 (точные) | 3.75/5 | 4.5/5      | High      |
| Avg P@5 (общий)  | 4.60/5 | 4.75/5     | Medium    |
