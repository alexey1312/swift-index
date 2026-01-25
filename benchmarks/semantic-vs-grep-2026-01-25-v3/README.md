# SwiftIndex vs Grep Benchmark v3

**Дата**: 2026-01-25
**Версия**: SwiftIndex после улучшений (proposal improve-type-declaration-search)
**Кодовая база**: swift-index (115 файлов, 6512 chunks)

## Цель

Повторный бенчмарк после внедрения улучшений type declaration search:

- Индексация type declarations (actor/class/struct/enum) как отдельных chunks
- Улучшенный поиск по conformances
- Индексация signature для type declarations
- Boost для type declaration chunks

## Методология

Те же 20 запросов, что и в первоначальном бенчмарке.

### Инструменты под тестом

| Инструмент          | Тип                       | Описание                       |
| ------------------- | ------------------------- | ------------------------------ |
| `swiftindex search` | Гибридный BM25 + Semantic | После improve-type-declaration |
| Grep                | Лексический regex         | Точные паттерны                |

### Критерии оценки

1. **Precision@5** — Сколько из топ-5 результатов релевантны?
2. **Concept match** — Понял ли инструмент намерение запроса?

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
