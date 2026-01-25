# Design: Improve Type Declaration Search

## Context

Текущая архитектура индексации создаёт chunks на уровне методов/функций. Это приводит к тому, что type declarations (class/struct/actor/enum) теряются при разбиении больших типов.

Например, `GRDBChunkStore.swift` (500+ строк) разбивается на ~20 method chunks, но сам `public actor GRDBChunkStore: ChunkStore, InfoSnippetStore` не индексируется как отдельная сущность.

## Goals / Non-Goals

**Goals:**

- Type declarations появляются в топ-5 для "implements X" запросов
- Редкие термины (< 10 occurrences) находятся точно
- Avg P@5 для conformance queries: 90%+

**Non-Goals:**

- Изменение формата вывода
- Добавление специального синтаксиса поиска (оставляем natural language)
- Изменение embedding provider

## Decisions

### Decision 1: Type Declaration Chunks

**Что**: Создавать отдельный chunk для каждого type declaration header.

**Структура chunk:**

```swift
CodeChunk(
    content: "public actor GRDBChunkStore: ChunkStore, InfoSnippetStore",
    kind: .actor,
    symbols: ["GRDBChunkStore"],
    conformances: ["ChunkStore", "InfoSnippetStore"],
    isTypeDeclaration: true,
    signature: "public actor GRDBChunkStore: ChunkStore, InfoSnippetStore",
    docComment: "SQLite-based chunk storage..."
)
```

**Почему**:

- Declaration header — самая важная часть для "what is X" и "implements X" запросов
- Conformances уже извлекаются, но теряются в method chunks
- Minimal overhead (~1 chunk per type)

**Альтернативы**:

- Virtual chunks (не сохранять, генерировать при поиске) — сложнее, медленнее
- Include declaration in all method chunks — дублирование, раздутый индекс

### Decision 2: Exact Symbol Boost

**Что**: Для терминов с < 10 occurrences применять 2.0x boost при точном совпадении в `symbols`.

**Логика:**

```swift
func calculateBoost(term: String, chunk: CodeChunk) -> Double {
    let termFrequency = globalTermFrequency[term] ?? 0

    if termFrequency < 10 && chunk.symbols.contains(term) {
        return 2.0  // Exact match boost for rare terms
    }
    return 1.0
}
```

**Почему**:

- Редкие термины (`USearchError`, `RRFFusion`) должны находиться точно
- BM25 не различает substring matches
- Порог 10 предотвращает boost для common terms

### Decision 3: Conformance Index Table

**Что**: Отдельная таблица для быстрого поиска conformances.

**Schema:**

```sql
CREATE TABLE conformances (
    chunk_id TEXT NOT NULL,
    protocol_name TEXT NOT NULL,
    PRIMARY KEY (chunk_id, protocol_name),
    FOREIGN KEY (chunk_id) REFERENCES chunks(id)
);

CREATE INDEX idx_conformances_protocol ON conformances(protocol_name);
```

**Запрос "implements ChunkStore":**

```sql
SELECT c.* FROM chunks c
JOIN conformances cf ON c.id = cf.chunk_id
WHERE cf.protocol_name = 'ChunkStore'
  AND c.is_type_declaration = 1
ORDER BY c.id;
```

**Почему**:

- O(1) lookup для conformances vs O(n) scan
- Позволяет boosting с 3.0x для conforming types
- Normalized form предотвращает дубликаты

## Risks / Trade-offs

| Risk                           | Mitigation                                 |
| ------------------------------ | ------------------------------------------ |
| Увеличение размера индекса     | ~1% overhead (1 chunk per type)            |
| Schema migration v8            | Backwards-compatible, re-index при upgrade |
| False positives для rare terms | Порог 10 occurrences предотвращает         |

## Migration Plan

1. Add `is_type_declaration` column (nullable, default NULL)
2. Add `conformances` table
3. Re-index при первом запуске (автоматически при schema change)
4. Rollback: drop new columns, conformances table

## Open Questions

1. Нужен ли специальный синтаксис `conforms:ChunkStore` или достаточно natural language detection?
   - **Recommendation**: Начать с NL detection, добавить синтаксис если NL недостаточно

2. Включать ли extension conformances в type declaration chunk?
   - **Recommendation**: Да, `extension User: Sendable` создаёт chunk с conformance
