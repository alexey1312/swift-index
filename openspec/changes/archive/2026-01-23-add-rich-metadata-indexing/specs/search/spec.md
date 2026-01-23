# search Spec Delta

## MODIFIED Requirements

### Requirement: Search Result Structure

The system SHALL return structured search results with rich metadata.

Result fields:

- `chunk` — matched CodeChunk with all metadata fields
- `score` — relevance score (0-1)
- `relevancePercent` — human-readable percentage (0-100)
- `matchType` — how matched (bm25, semantic, multi-hop)
- `highlights` — matching text spans
- `bm25Score` — BM25 component score (optional)
- `semanticScore` — semantic similarity score (optional)
- `bm25Rank` — rank in BM25 results (optional)
- `semanticRank` — rank in semantic results (optional)

CodeChunk includes:

- `docComment` — documentation comment
- `signature` — declaration signature
- `breadcrumb` — hierarchy path
- `tokenCount` — approximate token count
- `language` — programming language

#### Scenario: Result includes highlights

- **WHEN** searching "authenticate"
- **THEN** results include highlight spans
- **AND** can be used for UI display

#### Scenario: Result includes rich metadata

- **WHEN** searching "login"
- **AND** matching function has doc comment and signature
- **THEN** result.chunk.docComment contains the doc comment
- **AND** result.chunk.signature contains the signature
- **AND** result.chunk.breadcrumb contains hierarchy path

---

### Requirement: BM25 Keyword Search

The system SHALL support BM25 keyword search via FTS5 including doc comments.

BM25 parameters:

- k1: 1.2 (term frequency saturation)
- b: 0.75 (length normalization)

Searchable fields:

- `content` — code content
- `symbols` — declared symbols
- `doc_comment` — documentation comments

#### Scenario: Keyword search returns ranked results

- **WHEN** searching "login authentication"
- **THEN** returns chunks containing keywords
- **AND** results ranked by BM25 score

#### Scenario: Search finds doc comment match

- **WHEN** searching "validates user credentials"
- **AND** function has doc comment "/// Validates user credentials"
- **THEN** function chunk is returned in results
- **AND** ranked based on doc comment relevance

#### Scenario: Search combines code and doc relevance

- **WHEN** searching "authentication flow"
- **THEN** BM25 searches both `content` and `doc_comment`
- **AND** results reflect combined relevance

#### Scenario: Empty query returns empty

- **WHEN** searching with empty string
- **THEN** returns empty result list
- **AND** no error raised

---

## ADDED Requirements

### Requirement: Search Output Formats with Rich Metadata

The system SHALL support multiple output formats with rich metadata.

Supported formats:

- `human` — human-readable with docComment/signature display
- `json` — complete JSON with all metadata fields
- `toon` — token-optimized format with meta/docs sections

#### Scenario: Human format shows doc comment

- **WHEN** searching with `--format human`
- **AND** result has doc comment
- **THEN** output includes "Doc: [truncated doc comment]" line

#### Scenario: Human format shows signature

- **WHEN** searching with `--format human`
- **AND** result has signature
- **THEN** output includes "Signature: [declaration]" line

#### Scenario: JSON format includes all metadata

- **WHEN** searching with `--format json`
- **THEN** each result includes `docComment`, `signature`, `breadcrumb`, `tokenCount`, `language` fields

#### Scenario: TOON format includes meta section

- **WHEN** searching with `--format toon`
- **AND** results have signatures or breadcrumbs
- **THEN** output includes `meta[n]{sig,bc}:` section with compact metadata

#### Scenario: TOON format includes docs section

- **WHEN** searching with `--format toon`
- **AND** results have doc comments
- **THEN** output includes `docs[n]:` section with truncated doc comments
