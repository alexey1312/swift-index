# SwiftIndex vs Grep Benchmark v4

**Дата**: 2026-01-25
**Версия**: SwiftIndex после попытки улучшения точного поиска (improve-exact-term-search)
**Кодовая база**: swift-index

## Цель

Проверка влияния изменений `improve-exact-term-search` на качество поиска, особенно для редких токенов (например, `USearchError`).

## Методология

Те же 20 запросов, что и в предыдущих бенчмарках.

### Инструменты

- `swiftindex search` (через MCP `search_code`)
- Grep (как база для сравнения)

## 20 категорий запросов

См. `benchmarks/semantic-vs-grep-2026-01-25-v3/README.md` для полного списка.
