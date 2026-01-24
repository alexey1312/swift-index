## ADDED Requirements

### Requirement: Batch Vector Retrieval

The system SHALL support batch retrieval of vectors by ID for efficient reindexing.

API:

```swift
func getBatch(ids: [String]) async throws -> [String: [Float]]
```

Returns dictionary mapping chunk ID to vector. Missing IDs are omitted from result.

#### Scenario: Retrieve multiple vectors in single call

- **WHEN** calling `getBatch(ids: ["a", "b", "c"])`
- **AND** vectors exist for "a" and "c"
- **THEN** returns `["a": [0.1, ...], "c": [0.3, ...]]`
- **AND** "b" is omitted (not found)

#### Scenario: Empty input returns empty result

- **WHEN** calling `getBatch(ids: [])`
- **THEN** returns empty dictionary
- **AND** no database operations performed

#### Scenario: Large batch retrieval

- **WHEN** calling `getBatch` with 500 IDs
- **THEN** all existing vectors returned in single operation
- **AND** performance is O(n) not O(n²)

#### Scenario: Batch retrieval during reindex

- **WHEN** reindexing file with 100 existing chunks
- **THEN** `IndexManager` uses `getBatch` instead of sequential `get` calls
- **AND** retrieval completes in single database round-trip

---

### Requirement: Reindex Change Detection Optimization

The system SHALL use batch operations for efficient change detection during reindexing.

Optimization flow:

1. Collect all existing chunk IDs for file
2. Single `getBatch` call to retrieve all existing vectors
3. Build content hash lookup from batch result
4. Categorize chunks as reusable or needing embedding
5. Generate embeddings only for changed content

#### Scenario: Batch vector lookup in reindex

- **WHEN** file has 50 existing chunks
- **AND** 5 chunks have changed content
- **THEN** single `getBatch(ids: [50 ids])` is called
- **AND** 45 vectors are reused without re-embedding
- **AND** only 5 new embeddings generated

#### Scenario: Performance improvement measurement

- **WHEN** reindexing file with 100 chunks
- **THEN** vector retrieval uses 1 batch call (not 100 sequential)
- **AND** retrieval time reduced by 5-10x compared to sequential
