## MODIFIED Requirements

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

- Tokenizer: `unicode61`
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
