# Ключевые находки и изменения v2

## Положительные изменения

### 1. RRF Fusion работает лучше

Гибридный скоринг (rank + normalized score) улучшил результаты для концептуальных запросов.

**Пример**: `combine search results from different sources`

- v1: ConfigLoader.swift (#1), нерелевантные результаты
- v2: HybridSearchEngine.search (#2), HybridSearchTests (#4)

### 2. Description indexing улучшает BM25

Сгенерированные описания теперь индексируются в FTS5:

- "Creates a mock implementation of ChunkStore for testing"
- "HNSW-based vector storage for approximate nearest neighbor search"

Это позволяет находить результаты по концептуальным запросам.

### 3. Semantic re-ranking работает

Запрос `what implements ChunkStore protocol` теперь возвращает протокол с 121% релевантностью.
Это указывает на boost для conformance-related запросов.

### 4. TreeSitter chunks качественные

Все 5 результатов для `how are code chunks parsed` — из TreeSitterParser.
Парсер находится именно там, где он должен быть.

## Оставшиеся проблемы

### 1. Actor definitions не в топе

`public actor GRDBChunkStore: ChunkStore, InfoSnippetStore` не появляется в результатах.

**Проверка**: Поиск `GRDBChunkStore` возвращает только:

- GRDBChunkStoreTests.store (использование)
- Различные let store = try GRDBChunkStore()

**Гипотеза**: Actor definition может быть слишком большой chunk (файл 500+ строк) и разбивается на методы.

### 2. Редкие термины регрессировали

`USearchError` — 2 реальных использования в коде, но результаты содержат "Search" matches.

**Причина**: BM25 не различает подстроки. "Search" в "USearchError" матчит "SearchOptions".

### 3. Conformances не полностью интегрированы

Хотя conformances индексируются, они не используются эффективно для "implements X" запросов.

**Затронутые файлы**:

- `Sources/SwiftIndexCore/Parsing/SwiftSyntaxParser.swift` (extraction)
- `Sources/SwiftIndexCore/Search/SemanticSearch.swift` (re-ranking)

## Сравнение с целями proposal

| Цель proposal                        | Статус           |
| ------------------------------------ | ---------------- |
| RRF hybrid scoring                   | ✓ Работает       |
| Conformance indexing                 | ⚠️ Частично       |
| Description в FTS5                   | ✓ Работает       |
| Semantic re-ranking для conformances | ✓ Boost работает |

## Рекомендации для следующего proposal

### 1. Индексировать type declarations отдельно

Создать отдельный chunk для:

```swift
public actor GRDBChunkStore: ChunkStore, InfoSnippetStore
```

С полями:

- kind: actor/class/struct
- conformances: ["ChunkStore", "InfoSnippetStore"]
- signature: полная декларация

### 2. Добавить exact term matching для редких терминов

Для запросов типа `USearchError`:

- Если термин встречается < 10 раз в индексе, использовать exact match
- Boost для точного совпадения в symbol names

### 3. Улучшить conformance search

Добавить специальный синтаксис:

- `conforms:ChunkStore` — найти все типы, конформящие ChunkStore
- `implements:VectorStore` — альтернативный синтаксис

### 4. Multi-hop для protocol implementations

Когда пользователь ищет "what implements ChunkStore":

1. Найти ChunkStore protocol definition
2. Найти все chunks с conformance = "ChunkStore"
3. Ранжировать по близости к protocol definition

## Метрики прогресса

| Метрика            | Baseline | v2   | Target |
| ------------------ | -------- | ---- | ------ |
| Avg P@5            | 3.9      | 4.35 | 4.5    |
| Win rate vs grep   | 40%      | 65%  | 75%    |
| Conformance search | 40%      | 60%  | 90%    |
