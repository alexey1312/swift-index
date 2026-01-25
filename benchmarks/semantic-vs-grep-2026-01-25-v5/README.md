# SwiftIndex vs Grep Benchmark v5

**Дата**: 2026-01-25
**Версия**: SwiftIndex после индексации snippets (InfoSnippet) и документации
**Кодовая база**: swift-index (241 файлов, 8425 chunks)

## Цель

Проверка качества поиска после добавления:

- Индексации InfoSnippet (документация, markdown секции)
- Расширенного покрытия codebase (с 115 до 241 файлов)
- Увеличения количества chunks (с 6512 до 8425)

## Методология

Те же 20 запросов, что и в предыдущих бенчмарках.
**Важно**: Используется MCP tool `search_code` с фильтром `extensions: swift` для исключения benchmark docs из результатов.

### Инструменты

- `mcp__swiftindex__search_code` (через MCP)
- Grep (как база для сравнения)

## 20 категорий запросов

### Категория A: Точные ключевые слова

1. `HybridSearchEngine`
2. `USearchError`
3. `EmbeddingProvider`
4. `rrfK`

### Категория B: Синонимы и варианты

5. `text vectorization`
6. `store vectors persistently`
7. `nearest neighbor search`
8. `combine search results from different sources`

### Категория C: Вопросы о реализации

9. `how does the search ranking work`
10. `how are code chunks parsed and stored`
11. `what happens when a file is indexed`
12. `how are embedding failures handled`

### Категория D: Паттерны и дизайн

13. `actor pattern for thread safety`
14. `what implements ChunkStore protocol`
15. `how are providers configured`
16. `where is caching used`

### Категория E: Сквозные вопросы

17. `async await concurrency patterns`
18. `error types and their handling`
19. `TOML configuration loading and validation`
20. `how is search engine tested`
