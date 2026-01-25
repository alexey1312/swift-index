# SwiftIndex vs Grep Benchmark v6

**Дата**: 2026-01-25
**Версия**: SwiftIndex после CamelCase exact match и boost (commit d07d9fd)
**Кодовая база**: swift-index

## Цель

Проверка качества поиска после добавления:

- CamelCase exact match в BM25 и Hybrid search
- Content-based boost для редких CamelCase терминов
- Предотвращение partial matches (например, "USearchError" → "Search")

## Методология

Те же 20 запросов, что и в предыдущих бенчмарках.
**Важно**: Используется MCP tool `search_code` с фильтром `extensions: swift`.

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
