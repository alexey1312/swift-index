# SwiftIndex vs Grep Benchmark

**Дата**: 2026-01-25
**Версия**: SwiftIndex с OpenAI embeddings (1536 dimensions)
**Кодовая база**: swift-index (117 файлов)

## Цель

Сравнение качества семантического поиска (SwiftIndex MCP) и лексического поиска (Grep) по 20 типам запросов.

## Методология

### Инструменты под тестом

| Инструмент                                           | Тип                       | Сильные стороны               |
| ---------------------------------------------------- | ------------------------- | ----------------------------- |
| `mcp__swiftindex__search_code` (semantic_weight=0.7) | Гибридный BM25 + Semantic | Понимание концепций, синонимы |
| `mcp__swiftindex__search_code` (semantic_weight=0.0) | Чистый BM25               | Точные ключевые слова         |
| Grep                                                 | Лексический regex         | Точные паттерны               |

### Критерии оценки

1. **Precision@5** — Сколько из топ-5 результатов действительно релевантны?
2. **Recall** — Нашли ли ключевые локации кода?
3. **Concept match** — Понял ли инструмент намерение запроса?

### Процесс верификации

- После каждого поиска SwiftIndex проверялись 2-3 результата чтением файлов
- Проверялось соответствие номеров строк и сниппетов реальности
- Фиксировались галлюцинации и некорректные совпадения

## 20 категорий запросов

### Категория A: Точные ключевые слова (Grep должен преуспеть)

1. Литеральное имя функции: `HybridSearchEngine`
2. Тип ошибки: `USearchError`
3. Имя протокола: `EmbeddingProvider`
4. Константа: `rrfK`

### Категория B: Синонимы и варианты (Semantic должен преуспеть)

5. Синоним функции: `text vectorization` (ищем embedding)
6. Альтернативная формулировка: `store vectors persistently` (ищем USearchVectorStore)
7. Концептуальный алиас: `nearest neighbor search` (ищем HNSW/USearch)
8. Естественный язык: `combine search results from different sources` (RRF fusion)

### Категория C: Вопросы о реализации (Концептуальные)

9. How-вопрос: `how does the search ranking work`
10. Архитектурный запрос: `how are code chunks parsed and stored`
11. Flow-запрос: `what happens when a file is indexed`
12. Обработка ошибок: `how are embedding failures handled`

### Категория D: Паттерны и дизайн

13. Дизайн-паттерн: `actor pattern for thread safety`
14. Соответствие протоколу: `what implements ChunkStore protocol`
15. Внедрение зависимостей: `how are providers configured`
16. Стратегия кэширования: `where is caching used`

### Категория E: Сквозные вопросы

17. Async-паттерны: `async await concurrency patterns`
18. Распространение ошибок: `error types and their handling`
19. Конфигурация: `TOML configuration loading and validation`
20. Тестирование: `how is search engine tested`
