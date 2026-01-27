# storage Specification

## Purpose

TBD - created by archiving change add-swiftindex-core. Update Purpose after archive.

## Requirements

### Requirement: SQLite Metadata Storage

The system SHALL store chunk metadata in SQLite database using GRDB.swift.

Database location: `~/.swiftindex/indexes/<project-hash>/metadata.sqlite`

Schema:

- `chunks` table — chunk content and metadata
  - `doc_comment TEXT` — extracted documentation comment
  - `signature TEXT` — declaration signature
  - `breadcrumb TEXT` — hierarchy path (e.g., "Module > Class > Method")
  - `token_count INTEGER NOT NULL DEFAULT 0` — approximate token count
  - `language TEXT NOT NULL DEFAULT 'unknown'` — programming language
  - `generated_description TEXT` — LLM-generated summary of the code
  - `conformances TEXT` — JSON array of protocol/class conformances
- `chunks_fts` virtual table — FTS5 full-text search (includes rich metadata)
- `files` table — indexed file tracking
- `config` table — index configuration snapshot

#### Scenario: Store chunk metadata

- **WHEN** indexing creates new chunk
- **THEN** chunk is inserted into `chunks` table
- **AND** FTS5 index is updated

#### Scenario: Store chunk with rich metadata

- **WHEN** indexing Swift function with doc comment `/// Authenticates user`
- **THEN** chunk is inserted with `doc_comment = "Authenticates user"`
- **AND** `signature` contains function declaration
- **AND** `breadcrumb` contains type hierarchy path
- **AND** `token_count` is calculated as content.count / 4
- **AND** `language` is set to "swift"

#### Scenario: Retrieve chunk by ID

- **WHEN** querying chunk by ID
- **THEN** returns chunk with all metadata including rich fields
- **AND** query completes in < 1ms

#### Scenario: Database persistence

- **WHEN** application restarts
- **THEN** all indexed data is preserved
- **AND** no re-indexing required

#### Scenario: Store chunk with conformances

- **WHEN** indexing `class User: Codable, Identifiable`
- **THEN** `conformances` column contains `["Codable", "Identifiable"]`
- **AND** conformances are searchable via FTS

### Requirement: FTS5 Full-Text Search

The system SHALL use SQLite FTS5 for BM25 keyword search.

FTS5 configuration:

- Tokenizer: `unicode61` **(MODIFIED)**
- Indexed columns: `content`, `symbols`, `doc_comment`, `generated_description`, `conformances`
- BM25 ranking function

#### Scenario: FTS5 search

- **WHEN** searching "authentication"
- **THEN** FTS5 returns chunks containing "authentication"
- **AND** results ranked by BM25 score

#### Scenario: FTS5 search in doc comments

- **WHEN** searching "validates credentials"
- **AND** function has doc comment "/// Validates user credentials"
- **THEN** function chunk is returned in results
- **AND** ranked by combined content + doc_comment relevance

#### Scenario: FTS5 phrase search

- **WHEN** searching `"user login"`
- **THEN** returns chunks with exact phrase
- **AND** ranked higher than partial matches

#### Scenario: FTS5 prefix search

- **WHEN** searching `auth*`
- **THEN** returns "authentication", "authorize", "auth"

#### Scenario: FTS5 search in descriptions

- **WHEN** searching "calculates total"
- **AND** chunk has generated description "Calculates the total sum"
- **THEN** chunk is returned in results

### Requirement: Vector Index Storage

The system SHALL store embedding vectors using USearch HNSW index.

Index location: `~/.swiftindex/indexes/<project-hash>/vectors.usearch`

USearch configuration:

- Metric: Cosine similarity
- Connectivity: 16 (default)
- Expansion: 128 (construction), 64 (search)

#### Scenario: Add vector to index

- **WHEN** chunk is indexed with embedding
- **THEN** vector is added to USearch index
- **AND** associated with chunk ID

#### Scenario: Vector similarity search

- **WHEN** searching with query embedding
- **THEN** returns k-nearest neighbors
- **AND** results include similarity scores

#### Scenario: Vector index persistence

- **WHEN** application restarts
- **THEN** vector index is loaded from disk
- **AND** search works without re-indexing

---

### Requirement: Incremental Indexing

The system SHALL support incremental indexing based on file changes.

Change detection:

- File hash (stable SHA-256 of content)
- Modification timestamp
- File existence
- File path for hash lookup (per-path tracking)

#### Scenario: New file detection

- **WHEN** new Swift file added to project
- **THEN** only new file is indexed
- **AND** existing chunks unchanged

#### Scenario: Modified file detection

- **WHEN** existing file content changes
- **THEN** old chunks for file are removed
- **AND** new chunks are created

#### Scenario: Deleted file detection

- **WHEN** indexed file is deleted
- **THEN** chunks for file are removed
- **AND** vectors are removed from index

#### Scenario: Unchanged file skipped

- **WHEN** file hash for a path matches stored hash for that same path
- **THEN** file is skipped
- **AND** no parsing or embedding performed

#### Scenario: Identical content across different paths

- **WHEN** two different paths contain identical content
- **THEN** each path is tracked independently
- **AND** skipping applies per path without collisions

---

### Requirement: Index Project Isolation

The system SHALL maintain separate indexes per project.

Project identification:

- Hash of absolute project path
- Stored in `~/.swiftindex/indexes/<hash>/`

#### Scenario: Multiple projects

- **WHEN** indexing ProjectA and ProjectB
- **THEN** separate index directories created
- **AND** searches are project-scoped

#### Scenario: Project moved

- **WHEN** project directory moved to new location
- **THEN** new index created (different hash)
- **AND** old index can be garbage collected

---

### Requirement: Indexer Orchestration

The system SHALL coordinate parsing, embedding, and storage.

Indexing pipeline:

1. Scan project for matching files
2. Filter by include/exclude patterns
3. Detect changed files (incremental)
4. Parse files into chunks
5. Generate embeddings (batched)
6. Store metadata and vectors
7. Update file tracking

#### Scenario: Full project index

- **WHEN** running `swiftindex index`
- **THEN** all matching files are indexed
- **AND** progress is displayed

#### Scenario: Index with include pattern

- **WHEN** config has `include = ["Sources/**/*.swift"]`
- **THEN** only matching files are indexed

#### Scenario: Index with exclude pattern

- **WHEN** config has `exclude = ["**/Tests/**"]`
- **THEN** test files are skipped

---

### Requirement: Index Statistics

The system SHALL track and report index statistics.

Statistics:

- Total files indexed
- Total chunks created
- Total vectors stored
- Index size on disk
- Last index timestamp
- Indexing duration

#### Scenario: Show index stats

- **WHEN** running `swiftindex stats`
- **THEN** displays all statistics
- **AND** shows breakdown by file type

---

### Requirement: Index Cleanup

The system SHALL support index cleanup and rebuild.

#### Scenario: Clear index

- **WHEN** running `swiftindex clear`
- **THEN** all indexed data is removed
- **AND** index directory is deleted

#### Scenario: Rebuild index

- **WHEN** running `swiftindex index --rebuild`
- **THEN** existing index is cleared
- **AND** full re-index is performed

### Requirement: Database Schema Migration

The system SHALL support incremental schema migrations for index evolution.

#### Scenario: v2 migration adds rich metadata columns

- **WHEN** opening index created with v1 schema
- **THEN** v2 migration runs automatically
- **AND** new columns are added with default values
- **AND** FTS5 index is recreated with doc_comment column
- **AND** existing data is preserved

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

### Requirement: Optimized FTS5 Tokenizer

The system SHALL use the `unicode61` tokenizer for FTS5 full-text search. This tokenizer splits text on whitespace and punctuation, preserving CamelCase terms as single tokens (e.g., `USearchError` remains `usearcherror`). This improves exact term matching accuracy for code identifiers, as opposed to `porter` stemmer which can mangle such terms.

#### Scenario: Exact identifier search

- **WHEN** searching for `USearchError`
- **AND** FTS5 index contains `usearcherror` token from `USearchError`
- **THEN** `USearchError` is found as an exact match
- **AND** scores higher than partial matches like `Search`

#### Scenario: CamelCase splitting

- **WHEN** indexing `MyAwesomeClass`
- **AND** FTS5 tokenizer is `unicode61`
- **THEN** `myawesomeclass` is indexed as a single token
- **AND** searching `myawesomeclass` matches it directly

#### Scenario: Standard code terms

- **WHEN** indexing `func processRequest()`
- **AND** FTS5 tokenizer is `unicode61`
- **THEN** `func`, `process`, `request` are indexed as separate tokens
- **AND** search for `process` finds it
