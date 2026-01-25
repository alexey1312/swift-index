# Ключевые находки и проблемы

## Критические проблемы

### 1. Семантический вес не влияет на результаты

**Симптом**: `semantic_weight=0.7` и `semantic_weight=0.0` возвращают идентичные результаты для всех 20 запросов.

**Ожидаемое поведение**: Разные веса должны давать разные ранжирования.

**Гипотезы**:

- BM25 доминирует когда термины запроса буквально присутствуют в коде
- OpenAI эмбеддинги не добавляют дифференциации
- LLM-описания содержат те же ключевые слова, что и запрос

**Затронутые файлы**:

- `Sources/SwiftIndexCore/Search/HybridSearchEngine.swift`
- `Sources/SwiftIndexCore/Search/RRFFusion.swift`

### 2. Провал на запросах "what implements X"

**Симптом**: Запрос `"what implements ChunkStore protocol"` вернул:

1. `FollowUpGenerator.swift` (нерелевантно)
2. `Parser.swift` (протокол, не реализация)
3. `GRDBChunkStore.swift` (правильно, но на 3-м месте)

**Ожидаемое поведение**: `GRDBChunkStore : ChunkStore` должен быть #1.

**Причина**: Отсутствует понимание Swift синтаксиса наследования/conformance.

**Затронутые файлы**:

- Индексация не учитывает protocol conformance
- Описания не содержат информацию о реализуемых протоколах

### 3. Провал на запросе "combine search results"

**Симптом**: Вернул `ConfigLoader.swift` вместо `RRFFusion.swift`.

**Ожидаемое поведение**: RRFFusion — это буквально "объединение результатов поиска".

**Причина**:

- Описание `ConfigLoader`: "Loads configuration from multiple sources"
- Слово "sources" совпало с запросом
- Семантическое понимание не сработало

### 4. Нерелевантные результаты в топ-5

**Примеры провалов**:

| Запрос          | Нерелевантный результат   | Почему попал                 |
| --------------- | ------------------------- | ---------------------------- |
| `USearchError`  | `SearchOptions(limit: 1)` | BM25 матчит "Search"         |
| `actor pattern` | `MockLLMProvider`         | Описание содержит "pattern"  |
| `async await`   | `GlobMatcherTests`        | Тесты используют async/await |

## Положительные находки

### 1. LLM-описания работают

Автогенерированные описания делают код семантически searchable:

- `"Facilitates efficient HNSW-based nearest neighbor searches"`
- `"Loads and validates a vector store by checking file existence"`

### 2. Навигация breadcrumb полезна

`HybridSearchTests > engine` — помогает понять контекст без чтения файла.

### 3. Сигнатуры методов в результатах

```
Signature: public func search(vector: [Float], limit: Int)
```

Позволяет понять API без открытия файла.

## Метрики для отслеживания

| Метрика                  | Текущее значение | Целевое      |
| ------------------------ | ---------------- | ------------ |
| Avg P@5 (все запросы)    | 3.9/5            | 4.5/5        |
| Avg P@5 (синонимы)       | 4.0/5            | 4.8/5        |
| Avg P@5 (концепты)       | 3.75/5           | 4.5/5        |
| Семантический вес эффект | 0%               | >30% разница |
| "implements X" точность  | 40%              | 90%          |
