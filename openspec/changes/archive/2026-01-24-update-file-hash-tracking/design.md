## Context

Incremental indexing relies on stored file hashes to decide whether to skip parsing and embedding. The current hash implementation is non-deterministic across process runs, and the file hash table uses the hash as a primary key, which cannot distinguish identical content in different paths.

## Goals / Non-Goals

- Goals:
  - Deterministic, stable file hashing across runs.
  - File-hash tracking keyed by path to avoid collisions.
- Non-Goals:
  - Changes to chunk-level content hash or embedding reuse logic.
  - Changes to project hashing or index directory layout.
  - Backward-compatible migration (project is pre-production).

## Decisions

- Decision: Use SHA-256 of full file content for file-level change detection.
  - Rationale: Stable across runs and aligns with storage spec requirement.
- Decision: Full 64 hex character SHA-256 hash (no truncation).
  - Rationale: Unifies hash format across codebase (`computeContentHash` already uses full SHA-256, parsers use truncated). Standard format, negligible storage overhead.
- Decision: Store file hashes keyed by path (path primary key; hash as a column).
  - Rationale: Prevents collisions when multiple paths have identical content.
- Decision: No migration — replace schema directly in v1.
  - Rationale: Project is pre-production; no existing indexes to preserve.

## Risks / Trade-offs

- Existing indexes will be invalidated and require full reindex.
  - Mitigation: Acceptable for pre-production phase.

## Open Questions

- None.
