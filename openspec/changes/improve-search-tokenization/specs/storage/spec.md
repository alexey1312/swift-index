## ADDED Requirements

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

## MODIFIED Requirements

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
