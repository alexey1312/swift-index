# Change: Add SwiftIndex Core

## Why

Современные AI coding assistants (Claude Code, Cursor, Codex) не имеют специализированных инструментов семантического поиска для Swift кодовых баз. Существующие решения:

1. **Не понимают Swift-специфику** — extensions, protocols, actors, macros, property wrappers обрабатываются некорректно
2. **Требуют cloud зависимости** — отправляют код на внешние серверы для embeddings
3. **Не поддерживают multi-language** — проекты со смешанным Swift/ObjC/C кодом индексируются частично
4. **Используют простой text search** — без семантического понимания кода

SwiftIndex решает эти проблемы как **Swift-native MCP-сервер** с:

- 100% точным AST парсингом через SwiftSyntax
- Privacy-first подходом (полностью локальная работа)
- Гибридным поиском (BM25 + semantic + RRF fusion)
- Zero-config интеграцией с AI assistants

## What Changes

### NEW: Configuration Layer

- TOML конфигурация (`.swiftindex.toml`)
- Environment variables с приоритетом
- CLI flags override
- Layered config merge: CLI > Env > Project > Global > Defaults

### NEW: Hybrid Parsing Layer

- **SwiftSyntax** для .swift файлов (100% точность AST)
- **tree-sitter** для остальных языков:
  - Objective-C (.m, .h)
  - C/C++ (.c, .cpp)
  - JSON (.json)
  - YAML (.yaml, .yml)
  - Markdown (.md)
- HybridParser роутер по расширению файла
- AST-aware chunking с сохранением контекста

### NEW: Embedding Provider Chain

Автоматический fallback с privacy-first подходом:

1. **MLXEmbeddingProvider** — Apple Silicon native, zero network
2. **OllamaEmbeddingProvider** — локальный Ollama server
3. **SwiftEmbeddingsProvider** — pure Swift, always available
4. **VoyageProvider** — cloud fallback (requires API key)
5. **OpenAIProvider** — cloud fallback (requires API key)

### NEW: Storage Layer

- **GRDB.swift** — type-safe SQLite для метаданных
- **FTS5** — full-text search для BM25
- **USearch** — HNSW vector index для semantic search
- Incremental indexing с file hash tracking

### NEW: Hybrid Search Engine

- **BM25Search** — keyword-based через FTS5
- **SemanticSearch** — vector similarity через USearch
- **RRF Fusion** — Reciprocal Rank Fusion для объединения
- **MultiHopSearch** — follow references для глубокого анализа
- Configurable weights (semantic_weight: 0.7 default)

### NEW: MCP Server

4 инструмента для AI assistants:

- `index_codebase` — индексация Swift проекта
- `search_code` — гибридный семантический поиск
- `code_research` — multi-hop архитектурный анализ
- `watch_codebase` — отслеживание изменений

### NEW: CLI Application

- `swiftindex index` — однократная индексация
- `swiftindex search <query>` — поиск из терминала
- `swiftindex watch` — watch mode с auto-sync
- `swiftindex install-claude-code` — настройка Claude Code
- `swiftindex install-codex` — настройка Codex
- `swiftindex install-cursor` — настройка Cursor
- `swiftindex providers` — статус embedding providers

## Impact

### Affected Specs

7 новых capability specs:

- `configuration` — конфигурация и settings
- `parsing` — AST парсинг и chunking
- `embedding` — embedding provider chain
- `storage` — persistence и indexing
- `search` — hybrid search engine
- `mcp-server` — MCP tools
- `cli` — CLI commands

### Affected Code

Greenfield implementation — новый Swift package:

```
swift-index/
├── Package.swift                    # 15+ dependencies
├── Sources/
│   ├── SwiftIndexCore/             # Core library
│   ├── SwiftIndexMCP/              # MCP Server
│   └── swiftindex/                 # CLI
└── Tests/
    ├── SwiftIndexCoreTests/        # Unit tests
    └── IntegrationTests/           # E2E tests
```

### Dependencies (15+)

**Parsing:**

- swift-syntax (600.0.0+)
- swift-tree-sitter (0.9.0+)
- tree-sitter-objc, tree-sitter-c, tree-sitter-json, tree-sitter-yaml, tree-sitter-markdown

**Embeddings:**

- mlx-swift-lm (2.29.0+)
- ollama-swift (1.8.0+)
- swift-embeddings (0.0.25+)
- swift-huggingface (0.5.0+)

**Storage:**

- GRDB.swift (7.0.0+)
- usearch (2.0.0+)

**Configuration:**

- swift-toml (1.0.0+)

**CLI:**

- swift-argument-parser (1.5.0+)
- swift-log (1.6.0+)

### Risk Assessment

- **Low risk** — greenfield project, no breaking changes
- **Dependency risk** — некоторые библиотеки молодые (swift-tree-sitter, swift-embeddings)
- **Performance risk** — большие проекты (10K+ files) требуют оптимизации

### Rollout Plan

1. Phase 0: Foundation — Package.swift, protocols, models
2. Phase 1: Core components — parallel development (2 agents)
3. Phase 2: Storage layer
4. Phase 3: Search engine
5. Phase 4: Application layer (MCP + CLI)
6. Phase 5: Integration and polish
