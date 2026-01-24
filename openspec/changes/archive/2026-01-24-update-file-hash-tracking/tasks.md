## 1. Implementation

- [x] 1.1 Replace file hash computation with stable full SHA-256 (64 hex chars)
- [x] 1.2 Update v1 schema: file_hashes table keyed by path (path PK, hash column)
- [x] 1.3 Update ChunkStore protocol: `getFileHash(forPath:)` / `setFileHash(_:forPath:)`
- [x] 1.4 Update incremental indexing logic to use path + hash comparison
- [x] 1.5 Add/adjust tests for unchanged-file skip and same-content different-paths
