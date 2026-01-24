# Change: Stable file hash tracking for incremental indexing

## Why

Incremental indexing currently fails to skip unchanged files because the file hash uses a per-process random seed. This causes every run to treat files as changed, leading to unnecessary parsing and reindex work. The current file-hash table also keys on the hash alone, which can collide across different paths with identical content.

## What Changes

- Use a stable full SHA-256 file hash (64 hex chars) for change detection.
- Track file hashes keyed by file path (path primary key) to avoid cross-path collisions.
- Update incremental indexing checks to compare the stored hash for a path with the current hash.
- Update v1 schema directly (no migration needed — project is pre-production).

## Impact

- Affected specs: `storage`
- Affected code: `Sources/SwiftIndexCore/Storage/GRDBChunkStore.swift`, `Sources/SwiftIndexCore/Protocols/ChunkStore.swift`, `Sources/SwiftIndexCore/Storage/IndexManager.swift`
