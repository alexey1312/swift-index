# Design: SwiftIndex Core Architecture

## Context

SwiftIndex — MCP-сервер для семантического поиска по Swift кодовым базам. Целевая аудитория: разработчики использующие AI coding assistants (Claude Code, Cursor, Codex) для Swift/iOS проектов.

**Constraints:**
- macOS 14+ (для MLX и SwiftSyntax)
- Swift 6.0+ (strict concurrency)
- Privacy-first: локальная работа по умолчанию
- Performance: индексация 10K+ файлов за минуты

**Stakeholders:**
- Swift/iOS разработчики
- AI coding assistant users
- Enterprise teams с privacy requirements

## Goals / Non-Goals

### Goals
- 100% точный AST парсинг Swift кода
- Multi-language поддержка (ObjC, C, JSON, YAML)
- Privacy-first с опциональным cloud fallback
- Zero-config интеграция с Claude Code
- Hybrid search (keyword + semantic)
- TDD development approach

### Non-Goals
- Поддержка Linux/Windows (только macOS)
- Real-time collaborative editing
- IDE plugins (Phase 2+)
- Source code modification/refactoring

## Decisions

### D1: Hybrid Parsing (SwiftSyntax + tree-sitter)

**Decision:** Использовать SwiftSyntax для .swift файлов, tree-sitter для остальных языков.

**Rationale:**
- SwiftSyntax — официальный парсер от Apple, 100% точность для Swift 5.9+ (macros, actors)
- tree-sitter — mature multi-language парсер с готовыми грамматиками
- Комбинация обеспечивает best-of-both-worlds

**Alternatives Considered:**
| Option | Pros | Cons |
|--------|------|------|
| SwiftSyntax only | 100% Swift accuracy | No multi-lang support |
| tree-sitter only | Multi-lang, fast | 99% Swift accuracy, lag on new features |
| **Hybrid (chosen)** | Best accuracy + multi-lang | More complexity |
| SourceKit-LSP | Rich semantic info | Heavy, requires Xcode |

**Trade-offs:**
- (+) Maximum Swift accuracy
- (+) Multi-language support
- (-) Two parser implementations to maintain
- (-) Increased binary size

### D2: Embedding Provider Chain

**Decision:** Chain pattern с автоматическим fallback: MLX → Ollama → swift-embeddings → Cloud.

**Rationale:**
- Privacy-first: локальные провайдеры имеют приоритет
- Reliability: всегда есть fallback (swift-embeddings always available)
- Flexibility: пользователь может форсировать конкретный провайдер

**Provider Priority:**
```
1. MLX (Apple Silicon native)
   └── Fastest, no network, requires model download
2. Ollama (local server)
   └── Good performance, requires Ollama installation
3. swift-embeddings (pure Swift)
   └── Always available, slower but guaranteed
4. Voyage/OpenAI (cloud)
   └── Requires API key, network latency
```

**Alternatives Considered:**
| Option | Pros | Cons |
|--------|------|------|
| Cloud-only | Simple, consistent | Privacy concerns, latency |
| MLX-only | Fast, private | Requires Apple Silicon |
| **Chain (chosen)** | Flexible, reliable | Complex implementation |

### D3: Storage Architecture (GRDB + USearch)

**Decision:** GRDB для metadata/FTS5, USearch для vector index.

**Rationale:**
- GRDB — type-safe Swift SQLite, battle-tested, FTS5 для BM25
- USearch — production HNSW, handles billions of vectors
- Separation of concerns: structured data vs vectors

**Schema:**
```sql
-- GRDB (metadata.sqlite)
CREATE TABLE chunks (
    id TEXT PRIMARY KEY,
    path TEXT NOT NULL,
    content TEXT NOT NULL,
    start_line INTEGER,
    end_line INTEGER,
    kind TEXT,
    symbols TEXT,  -- JSON array
    file_hash TEXT,
    created_at REAL
);

CREATE VIRTUAL TABLE chunks_fts USING fts5(
    content,
    symbols,
    content='chunks',
    content_rowid='rowid'
);

-- USearch (vectors.usearch)
-- HNSW index with cosine similarity
-- dimension: 384-1024 depending on model
```

**Alternatives Considered:**
| Option | Pros | Cons |
|--------|------|------|
| SQLite + vector extension | Single DB | Vector extension immature |
| Qdrant/Milvus | Full-featured | External service, heavy |
| **GRDB + USearch (chosen)** | Type-safe, embedded | Two storage systems |
| Pure file-based | Simple | No FTS, slow queries |

### D4: Hybrid Search with RRF

**Decision:** Combine BM25 (FTS5) + Semantic (USearch) с Reciprocal Rank Fusion.

**Rationale:**
- BM25 хорош для exact keyword matches
- Semantic хорош для conceptual similarity
- RRF — proven fusion algorithm (k=60 default)

**Algorithm:**
```swift
func hybridSearch(query: String, semanticWeight: Float = 0.7) -> [SearchResult] {
    let bm25Results = fts5Search(query)
    let semanticResults = vectorSearch(embed(query))

    return rrfFuse(
        bm25Results.map { ($0, 1 - semanticWeight) },
        semanticResults.map { ($0, semanticWeight) },
        k: 60
    )
}
```

**Alternatives Considered:**
| Option | Pros | Cons |
|--------|------|------|
| BM25 only | Fast, exact | No semantic understanding |
| Semantic only | Good conceptual | Misses exact matches |
| Linear combination | Simple | Score normalization issues |
| **RRF (chosen)** | Rank-based, robust | Slightly complex |

### D5: Configuration Layering

**Decision:** TOML config с layered priority: CLI > Env > Project > Global > Defaults.

**Rationale:**
- TOML — human-readable, good Swift support
- Layered merge позволяет override на любом уровне
- Pattern успешно используется в clai

**Priority:**
```
1. CLI flags          --provider mlx
2. Environment        SWIFTINDEX_PROVIDER=ollama
3. Project config     .swiftindex.toml
4. User global        ~/.config/swiftindex/config.toml
5. Built-in defaults  Hardcoded
```

### D6: TDD Development Approach

**Decision:** Test-first development для всех компонентов.

**Rationale:**
- Ensures testability from design phase
- Enables parallel development (tests as contracts)
- Catches regressions early
- Gates prevent broken builds

**Pattern:**
```
1. Define Protocol
2. Write Tests (mock impl)
3. Implement Real Component
4. Run Tests → Must Pass
5. Integration Test
```

## Risks / Trade-offs

### R1: Dependency Stability
- **Risk:** Молодые библиотеки (swift-tree-sitter, swift-embeddings) могут иметь breaking changes
- **Mitigation:** Pin versions, integration tests, fallback to stable alternatives

### R2: Large Codebase Performance
- **Risk:** Проекты с 10K+ файлов могут индексироваться медленно
- **Mitigation:** Incremental indexing, file hash tracking, background processing

### R3: Model Download UX
- **Risk:** Первый запуск требует скачивания ML моделей (100MB+)
- **Mitigation:** Progress indication, consent dialog, pre-downloaded option

### R4: MLX Compatibility
- **Risk:** MLX только для Apple Silicon
- **Mitigation:** Automatic fallback to Ollama/swift-embeddings on Intel

## Migration Plan

N/A — greenfield project, no migration required.

## Open Questions

1. **Q: Как обрабатывать Swift Macros с compile-time expansion?**
   - Current plan: Index macro definition, not expansion
   - May need SourceKit integration for full expansion

2. **Q: Поддержка SPM vs CocoaPods vs Carthage?**
   - Current plan: Focus on SPM, detect others for exclude patterns
   - May need package manager specific handling

3. **Q: Incremental vs full re-index trigger?**
   - Current plan: File hash based incremental
   - May need AST-level diff for better accuracy
