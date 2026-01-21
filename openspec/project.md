# Project Context

## Purpose

SwiftIndex — Swift-native MCP-сервер для семантического поиска по Swift кодовым базам.

Цели:

- Обеспечить AI coding assistants (Claude Code, Cursor, Codex) инструментом семантического поиска, заточенным под Swift
- Privacy-first подход: полностью локальная работа по умолчанию
- 100% точный AST парсинг Swift кода через SwiftSyntax
- Гибридный поиск: BM25 + semantic + RRF fusion
- Zero-config интеграция с популярными AI assistants

## Tech Stack

- **Language:** Swift 6.0+
- **Platform:** macOS 14+ (Apple Silicon primary)
- **Parsing:** SwiftSyntax (Swift), tree-sitter (ObjC, C, JSON, YAML, Markdown)
- **Embeddings:** MLX, Ollama, swift-embeddings, Voyage, OpenAI
- **Storage:** GRDB.swift (SQLite + FTS5), USearch (HNSW vectors)
- **Configuration:** TOML (swift-toml)
- **CLI:** swift-argument-parser
- **Logging:** swift-log

## Project Conventions

### Code Style

- Swift 6.0 strict concurrency
- Actor-based isolation for shared state
- Sendable conformance for cross-actor types
- SwiftFormat for formatting
- SwiftLint for linting
- Explicit error handling (no force unwraps)

### Architecture Patterns

- **Protocol-oriented design** — protocols define contracts, implementations swappable
- **Provider chain** — embedding providers with automatic fallback
- **Hybrid parser** — router delegates to SwiftSyntax or tree-sitter by extension
- **Layered configuration** — CLI > Env > Project > Global > Defaults
- **Repository pattern** — MetadataStore, VectorIndex abstractions

### Testing Strategy

- **TDD (Test-Driven Development)** — write tests first, then implement
- **Unit tests** — all core components (76+ tests)
- **Integration tests** — E2E workflows
- **Test fixtures** — sample Swift/ObjC/C/JSON/YAML files
- **Mock implementations** — MockEmbeddingProvider for testing
- **Gates** — build + tests must pass at each phase

### Git Workflow

- **Branch naming:** `feature/<name>`, `fix/<name>`, `chore/<name>`
- **Commit format:** Conventional Commits
  - `feat:` — new feature
  - `fix:` — bug fix
  - `test:` — adding tests
  - `docs:` — documentation
  - `chore:` — maintenance
- **PR requirements:** tests pass, code review, spec compliance

## Domain Context

### Swift Development

- SwiftSyntax — официальный парсер от Apple, 100% точность
- Важные Swift constructs: extensions, protocols, actors, macros, property wrappers
- SPM (Swift Package Manager) — основная система управления зависимостями
- Xcode projects: .xcodeproj, .xcworkspace

### Embedding Models

- MLX — Apple Silicon native ML framework
- Embedding dimensions: 384 (small), 768 (medium), 1024 (large)
- Cosine similarity для vector search
- BM25 — traditional keyword-based ranking

### MCP (Model Context Protocol)

- JSON-RPC 2.0 over stdio
- Tools: `tools/list`, `tools/call`
- Used by Claude Code, Cursor, other AI assistants

## Important Constraints

1. **macOS only** — MLX и некоторые зависимости требуют macOS
2. **Apple Silicon primary** — MLX оптимизирован для M1/M2/M3
3. **Privacy-first** — локальные провайдеры имеют приоритет
4. **No network by default** — cloud только при явном указании API keys
5. **Swift 6.0+** — strict concurrency требует современный Swift

## External Dependencies

### Primary Dependencies

| Dependency            | Version  | Purpose                |
| --------------------- | -------- | ---------------------- |
| swift-syntax          | 600.0.0+ | Swift AST parsing      |
| swift-tree-sitter     | 0.9.0+   | Multi-language parsing |
| mlx-swift-lm          | 2.29.0+  | MLX embeddings         |
| ollama-swift          | 1.8.0+   | Ollama client          |
| swift-embeddings      | 0.0.25+  | Pure Swift embeddings  |
| GRDB.swift            | 7.0.0+   | SQLite + FTS5          |
| usearch               | 2.0.0+   | HNSW vector index      |
| swift-toml            | 1.0.0+   | TOML parsing           |
| swift-argument-parser | 1.5.0+   | CLI framework          |

### External Services (Optional)

- **HuggingFace Hub** — model downloads
- **Ollama** — local embedding server
- **Voyage AI** — cloud embeddings (requires API key)
- **OpenAI** — cloud embeddings (requires API key)
