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
- `chunks_fts` virtual table — FTS5 full-text search (includes `doc_comment`)
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

---

### Requirement: FTS5 Full-Text Search

The system SHALL use SQLite FTS5 for BM25 keyword search.

FTS5 configuration:

- Tokenizer: `unicode61`
- Indexed columns: `content`, `symbols`, `doc_comment`
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

---

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

- File hash (SHA256 of content)
- Modification timestamp
- File existence

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

- **WHEN** file hash matches stored hash
- **THEN** file is skipped
- **AND** no parsing or embedding performed

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
