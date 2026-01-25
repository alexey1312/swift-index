# SwiftIndex vs Grep Benchmark v7

**Дата**: 2026-01-25
**Версия**: SwiftIndex после улучшений FTS (commit 603243d)
**Кодовая база**: swift-index
**Метод тестирования**: MCP server (`mcp__swiftindex__search_code`)

## Цель

Проверка качества поиска после последних улучшений:

- Улучшенная обработка FTS запросов (commit 603243d)
- CamelCase exact match и boost (commit d07d9fd)
- Snippet indexing support (commit 17ec3a8)

## Методология

20 запросов через MCP tool `search_code` с параметрами:

- `extensions: swift`
- `limit: 5`
- `format: human`

### Категории запросов

| Категория | Тип                   | Запросы |
| --------- | --------------------- | ------- |
| A         | Точные ключевые слова | 1-4     |
| B         | Синонимы и варианты   | 5-8     |
| C         | Вопросы о реализации  | 9-12    |
| D         | Паттерны и дизайн     | 13-16   |
| E         | Сквозные вопросы      | 17-20   |

### Оценка P@5

- 5/5: Все 5 результатов релевантны
- 4/5: 4 результата релевантны
- 3/5: 3 результата релевантны
- и т.д.

## Список запросов

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
