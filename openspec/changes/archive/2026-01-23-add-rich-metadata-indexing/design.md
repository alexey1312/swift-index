# Design: Rich Metadata Indexing

## Context

Current architecture:

```
File → HybridParser → CodeChunk → IndexManager → GRDBChunkStore + USearchVectorStore
                                       ↓
                            EmbeddingProviderChain
```

**Problem**: `docComment` and `signature` are extracted in parsers but not passed to `CodeChunk`.

**Stakeholders**: MCP server users, CLI users, search quality

## Goals / Non-Goals

**Goals:**

- Preserve all extracted metadata (docComment, signature, breadcrumb)
- Enable search across documentation content
- Improve semantic search quality via enriched context
- Support parallel file processing for performance

**Non-Goals:**

- Change external MCP API (remains compatible)
- Support old index format (requires re-indexing)
- Real-time LLM description generation (too slow)

## Decisions

### D1: Extend CodeChunk vs New Entity

**Decision**: Extend existing `CodeChunk` + add separate `InfoSnippet` for Phase 2.

**Alternatives considered**:

- Create separate `CodeSnippet` and `InfoSnippet` like Context7
- **Rejected**: Would require significant refactoring; existing `kind` field already distinguishes types

### D2: Token Counting

**Decision**: Use simple approximation `content.count / 4` for token estimation.

**Alternatives considered**:

- Use `tiktoken-swift` for exact counting
- **Rejected**: Model-dependent; approximation sufficient for context window estimation

### D3: Breadcrumb Format

**Decision**: Use existing `typeStack` to build breadcrumb in format `"Module > Class > Method"`.

**Implementation**: `SwiftSyntaxParser` already tracks `typeStack` — reuse for breadcrumb construction.

### D4: Database Migration Strategy

**Decision**: Add v2 migration with new nullable columns and default values.

**Schema changes**:

```sql
ALTER TABLE chunks ADD COLUMN doc_comment TEXT;
ALTER TABLE chunks ADD COLUMN signature TEXT;
ALTER TABLE chunks ADD COLUMN breadcrumb TEXT;
ALTER TABLE chunks ADD COLUMN token_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE chunks ADD COLUMN language TEXT NOT NULL DEFAULT 'unknown';
```

FTS5 index recreated to include `doc_comment` column.

### D5: Language Detection

**Decision**: Detect language from file extension at chunk creation time.

**Implementation**: Static mapping in `CodeChunk.detectLanguage(from:)`:

- `.swift` → "swift"
- `.m`, `.mm` → "objective-c"
- `.c`, `.h` → "c"
- `.json` → "json"
- etc.

## Risks / Trade-offs

| Risk               | Mitigation                                                          |
| ------------------ | ------------------------------------------------------------------- |
| Increased DB size  | docComment/signature typically small; compensated by search quality |
| Schema migration   | No backward compat needed — just re-index                           |
| Performance impact | Metadata fields are nullable; minimal overhead                      |

## Migration Plan

1. Add new columns via GRDB migration
2. Update parsers to populate metadata
3. Old indexes auto-detected → user prompted to re-index
4. Rollback: delete `.swiftindex/` directory and re-index

## Open Questions

None — all decisions finalized.
