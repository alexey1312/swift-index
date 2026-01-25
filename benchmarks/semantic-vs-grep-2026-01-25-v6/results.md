# Результаты бенчмарка v6

## Сводная таблица

| #  | Запрос                               | Категория   | SwiftIndex v6 | Изменение vs v5 | Примечание                                    |
| -- | ------------------------------------ | ----------- | ------------- | --------------- | --------------------------------------------- |
| 1  | `HybridSearchEngine`                 | A: Точный   | 5/5 ✓         | =               | #3 с 78% relevance                            |
| 2  | `USearchError`                       | A: Точный   | 0/5 ✗         | ↓ (было 1/5)    | **РЕГРЕССИЯ!** Только Search-содержащие       |
| 3  | `EmbeddingProvider`                  | A: Точный   | 5/5 ✓         | =               | Много релевантных результатов                 |
| 4  | `rrfK`                               | A: Точный   | 5/5 ✓         | =               | Идеально                                      |
| 5  | `text vectorization`                 | B: Синоним  | 5/5 ✓         | =               | vectorStore, EmbeddingProvider                |
| 6  | `store vectors persistently`         | B: Синоним  | 5/5 ✓         | =               | vectorStore найден                            |
| 7  | `nearest neighbor search`            | B: Синоним  | 3/5           | =               | Comparable extensions всё ещё #1-2            |
| 8  | `combine search results`             | B: Синоним  | 5/5 ✓         | =               | HybridSearchEngine.search #3                  |
| 9  | `how does search ranking work`       | C: Концепт  | 5/5 ✓         | =               | HybridSearchEngine.search, semanticRank       |
| 10 | `how are code chunks parsed`         | C: Концепт  | 5/5 ✓         | =               | TreeSitterParser.chunks                       |
| 11 | `what happens when file indexed`     | C: Концепт  | 5/5 ✓         | =               | recordIndexed, indexFile                      |
| 12 | `how are embedding failures handled` | C: Концепт  | 4/5           | =               | embeddings references                         |
| 13 | `actor pattern for thread safety`    | D: Паттерн  | 5/5 ✓         | =               | 5 актеров: GlobMatcher, HubModelManager, etc. |
| 14 | `what implements ChunkStore`         | D: Паттерн  | 5/5 ✓         | ↑ (было 4/5)    | ChunkStore protocol + MockChunkStore          |
| 15 | `how are providers configured`       | D: Паттерн  | 5/5 ✓         | =               | EmbeddingProviderRegistry                     |
| 16 | `where is caching used`              | D: Паттерн  | 5/5 ✓         | =               | cachePath, caching tests                      |
| 17 | `async await concurrency`            | E: Сквозной | 5/5 ✓         | =               | concurrentBatching                            |
| 18 | `error types and handling`           | E: Сквозной | 5/5 ✓         | =               | MCPError, TaskError                           |
| 19 | `TOML config loading validation`     | E: Сквозной | 5/5 ✓         | =               | TOMLConfigValidator, TOMLConfigLoaderTests    |
| 20 | `how is search engine tested`        | E: Сквозной | 5/5 ✓         | =               | SearchEngine protocol, E2ETests               |

## Критическая проблема: `USearchError` (1/5 → 0/5)

**Это регрессия в v6!**

### Ожидаемое поведение после CamelCase exact match

После коммита d07d9fd (CamelCase exact match) поиск `USearchError` должен был улучшиться:

- CamelCase detection работает (тест проходит)
- Content-based boost для редких терминов включен

### Фактический результат

```
[1] BM25Search:27 - actor BM25Search : SearchEngine
[2] TOMLConfig.search - var search : SearchSection?
[3] SearchEngine:9 - protocol SearchEngine : Sendable
[4] PartialConfig.searchEnhancement
[5] SearchCommand.results
```

Все результаты содержат "Search", но ни один не содержит "USearchError".

### Причина регрессии

Grep показывает, что `USearchError` существует в:

- `USearchVectorStore.swift:145` — `} catch let usearchError as USearchError {`
- `CamelCaseSearchTests.swift` — тестовые данные
- `SearchTokenizationTests.swift:36` — тест поиска USearchError

**Гипотеза**: Эти чанки не проиндексированы или CamelCase exact match не применяется к BM25 результатам.

### Рекомендации

1. Проверить, проиндексирован ли `USearchVectorStore.swift` (содержит реальный `USearchError`)
2. Убедиться, что CamelCase exact match фильтрация работает для BM25 результатов
3. Добавить логирование в `HybridSearchEngine.applyRankingBoosts` для диагностики

## Улучшение: `what implements ChunkStore` (4/5 → 5/5)

Результаты стали точнее:

| # | v5                            | v6                                  |
| - | ----------------------------- | ----------------------------------- |
| 1 | ChunkStore protocol           | ChunkStore protocol (150%)          |
| 2 | ChunkStore full definition    | ChunkStore full definition (118%)   |
| 3 | HybridSearchEngine.chunkStore | HybridSearchEngine.chunkStore (73%) |
| 4 | MockChunkStore                | MockChunkStore (79%)                |
| 5 | SemanticSearch.chunkStore     | SemanticSearch.chunkStore (71%)     |

**Примечание**: Relevance scores показывают >100% для protocol definition, что указывает на сильный boost.

## Анализ по категориям

### Категория A: Точные ключевые слова (4 запроса)

| Метрика          | v5  | v6   | Изменение |
| ---------------- | --- | ---- | --------- |
| Avg P@5          | 4.0 | 3.75 | ↓ -0.25   |
| Побед SwiftIndex | 0   | 0    | =         |

**Вывод**: Регрессия из-за `USearchError`.

### Категория B: Синонимы и варианты (4 запроса)

| Метрика          | v5  | v6  | Изменение |
| ---------------- | --- | --- | --------- |
| Avg P@5          | 4.5 | 4.5 | =         |
| Побед SwiftIndex | 3   | 3   | =         |

**Вывод**: Стабильно.

### Категория C: Вопросы о реализации (4 запроса)

| Метрика          | v5   | v6   | Изменение |
| ---------------- | ---- | ---- | --------- |
| Avg P@5          | 4.75 | 4.75 | =         |
| Побед SwiftIndex | 4    | 4    | =         |

**Вывод**: Стабильно отлично.

### Категория D: Паттерны и дизайн (4 запроса)

| Метрика          | v5   | v6 | Изменение |
| ---------------- | ---- | -- | --------- |
| Avg P@5          | 4.75 | 5  | ↑ +0.25   |
| Побед SwiftIndex | 4    | 4  | =         |

**Вывод**: Улучшение на `ChunkStore`.

### Категория E: Сквозные вопросы (4 запроса)

| Метрика          | v5 | v6 | Изменение |
| ---------------- | -- | -- | --------- |
| Avg P@5          | 5  | 5  | =         |
| Побед SwiftIndex | 4  | 4  | =         |

**Вывод**: Идеально!

## Итоговый счёт

| Метрика           | v5   | v6   | Изменение |
| ----------------- | ---- | ---- | --------- |
| Побед SwiftIndex  | 15   | 15   | =         |
| Ничьих            | 3    | 3    | =         |
| Поражений         | 2    | 2    | =         |
| **Avg P@5 (все)** | 4.60 | 4.60 | =         |

**Результат**: Без изменений общего счёта, но с регрессией на критическом запросе.

## Сравнение версий

| Версия | Avg P@5 | Побед | Ключевое изменение                              |
| ------ | ------- | ----- | ----------------------------------------------- |
| v1     | 3.9     | 8     | Baseline                                        |
| v2     | 4.35    | 13    | RRF Fusion                                      |
| v3     | 4.55    | 15    | Type Declarations                               |
| v4     | 4.55    | 15    | Exact Search (без явного эффекта)               |
| v5     | 4.60    | 15    | Snippets + расширенное покрытие (241 files)     |
| v6     | 4.60    | 15    | CamelCase exact match (регрессия USearchError!) |

## Детальные результаты запросов

### Запрос #2: USearchError (РЕГРЕССИЯ)

**Grep находит**:

```
Sources/SwiftIndexCore/Storage/USearchVectorStore.swift:145
Tests/SwiftIndexCoreTests/CamelCaseSearchTests.swift (много упоминаний)
Tests/SwiftIndexCoreTests/SearchTokenizationTests.swift:36
Tests/SwiftIndexCoreTests/StorageTests.swift:580-587
```

**SwiftIndex v6 возвращает**:

```
[1] BM25Search (47%) - содержит "Search"
[2] TOMLConfig.search (52%) - содержит "search"
[3] SearchEngine protocol (46%) - содержит "Search"
[4] PartialConfig.searchEnhancement (46%)
[5] SearchCommand.results (47%)
```

**Проблема**: Ни один результат не содержит `USearchError`. CamelCase exact match не предотвращает partial matches.

**Критический finding**: При поиске "USearchVectorStore add vector" метод `USearchVectorStore.add` (строки 120-176) находится на #2. Этот чанк **содержит** код `catch let usearchError as USearchError`, но при прямом поиске "USearchError" он не возвращается.

**Вывод**: Проблема не в индексации, а в ranking. BM25 матчит "Search" в других чанках (BM25Search, SearchEngine) сильнее, чем "USearchError" в content метода add. CamelCase exact match boost не применяется или недостаточен.

### Запрос #7: nearest neighbor search (без изменений)

По-прежнему Comparable extensions на #1-2:

```
[1] SearchResult : Comparable (36%)
[2] InfoSnippetSearchResult : Comparable (35%)
[3] IndexManager.semanticTask (31%)
[4] USearchVectorStoreTests.searchWithThreshold (34%)
[5] USearchVectorStoreTests.results (32%)
```

**Проблема**: BM25 матчит "search" в "SearchResult", семантика недостаточна.

### Запрос #14: what implements ChunkStore (УЛУЧШЕНИЕ)

```
[1] ChunkStore protocol (150%) - определение протокола
[2] ChunkStore full (118%) - полное определение с методами
[3] HybridSearchEngine.chunkStore (73%)
[4] MockChunkStore (79%) - имплементация!
[5] SemanticSearch.chunkStore (71%)
```

**Улучшение**: MockChunkStore теперь в топ-5, relevance scores выше.

## Выводы и рекомендации

### Критические проблемы

1. **USearchError регрессия** — CamelCase exact match не работает как ожидалось
   - Нужно исследовать, почему чанки с USearchError не находятся
   - Возможно, проблема в индексации, а не в поиске

2. **nearest neighbor search** — Comparable extensions всё ещё доминируют
   - Нужна демоция generic protocol extensions для концептуальных запросов

### Положительные изменения

1. **ChunkStore query** улучшился — relevance scores значительно выше
2. **Стабильность** — 18/20 запросов показали стабильные результаты

### Рекомендации для v7

1. **Исправить USearchError**:
   - Проверить индексацию `USearchVectorStore.swift`
   - Добавить debug logging в CamelCase exact match
   - Убедиться, что фильтрация BM25 результатов работает

2. **Добавить демоцию Comparable extensions**:
   - Для концептуальных запросов (содержащих "search", "find", "how")
   - Понизить ранг generic protocol conformances

3. **Метрики для отслеживания**:
   | Метрика          | v6     | Целевое | Приоритет |
   | ---------------- | ------ | ------- | --------- |
   | USearchError     | 0/5    | 4/5     | Critical  |
   | nearest neighbor | 3/5    | 4/5     | High      |
   | Avg P@5 (точные) | 3.75/5 | 4.5/5   | High      |
