# Change: Add search-docs Command to CLI

## Why

Текущее состояние:

- **CLI**: только `swiftindex search` (код) — нет поиска по документации
- **MCP**: есть `search_code` и `search_docs` — полный функционал

Это создаёт асимметрию: пользователи CLI не могут искать по Markdown документации, README, и другим .md файлам. MCP-интегрированные AI-ассистенты имеют больше возможностей.

## What Changes

### 1. Добавить `swiftindex search-docs` команду

- Параллельная команда к существующей `search`
- Использует `HybridSearchEngine.searchInfoSnippets()`
- Поддерживает те же форматы вывода: toon, human, json

### 2. Параметры команды

```
swiftindex search-docs <QUERY> [OPTIONS]
  --limit <N>        Maximum results (default: 10)
  --format <FORMAT>  Output: toon, human, json (default: toon)
  --path <PATH>      Path to indexed codebase (default: .)
  --path-filter <GLOB>  Filter by path pattern
```

### 3. Структура результатов

InfoSnippet содержит:

- `path` — путь к файлу
- `startLine`, `endLine` — позиция в файле
- `breadcrumb` — иерархия (README > Installation > macOS)
- `kind` — тип (markdownSection, documentation, example)
- `content` — текст документации
- `tokenCount` — приблизительное количество токенов

## Impact

- Affected specs: `cli`
- Affected code:
  - `Sources/swiftindex/Commands/SearchDocsCommand.swift` (new)
  - `Sources/swiftindex/swiftindex.swift` (register command)

## Non-Goals

- Объединение search и search-docs в один endpoint — сознательно оставляем раздельно
- Изменение MCP API — уже работает корректно
