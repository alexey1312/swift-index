## ADDED Requirements

### Requirement: Term Frequency Lookup

The system SHALL provide efficient term frequency lookup for search ranking optimization.

Term frequency API:

- `getTermFrequency(term: String) -> Int` — count of chunks containing term
- Cache: LRU with 100 entries per search session
- Query: FTS5 term frequency or symbols column count

#### Scenario: Lookup term frequency

- **WHEN** querying term frequency for "USearchError"
- **THEN** returns count of chunks containing "USearchError"
- **AND** result is cached for subsequent lookups

#### Scenario: Cache hit performance

- **WHEN** same term queried twice
- **THEN** second query uses cached value
- **AND** no database query executed

---

### Requirement: Standard Protocol Extension Demotion

The system SHALL demote extension chunks for standard protocols in conceptual queries.

Standard protocols list:

- Comparable
- Equatable
- Hashable
- Codable
- Sendable
- CustomStringConvertible
- CustomDebugStringConvertible

Conceptual query patterns:

- Contains "how" (e.g., "how does X work")
- Contains "what" (e.g., "what implements X")
- Contains "where" (e.g., "where is X used")

Demotion parameters:

- `standard_protocol_demotion` — 0.5x for matching extension chunks

#### Scenario: Demote Comparable extension

- **WHEN** searching "nearest neighbor search"
- **AND** result includes `extension SearchResult: Comparable`
- **THEN** extension chunk receives 0.5x demotion
- **AND** ranks lower than implementation chunks

#### Scenario: No demotion for non-standard protocols

- **WHEN** searching "what implements ChunkStore"
- **AND** result includes `extension User: ChunkStore`
- **THEN** no demotion applied
- **AND** ranks normally with conformance boost

#### Scenario: No demotion for non-conceptual queries

- **WHEN** searching "Comparable implementation"
- **THEN** no demotion applied
- **AND** Comparable extensions rank normally

---

### Requirement: Source Path Ranking Boost

The system SHALL boost results from source directories over test directories.

Boost parameters:

- `source_boost` — 1.1x for paths containing `/Sources/`
- Configurable via `search.source_boost` (default: 1.1)

#### Scenario: Source file ranked higher

- **WHEN** searching "GRDBChunkStore"
- **AND** results include both `Sources/SwiftIndexCore/Storage/GRDBChunkStore.swift` and `Tests/SwiftIndexCoreTests/StorageTests.swift`
- **THEN** source file receives 1.1x boost
- **AND** ranks higher than test file

#### Scenario: Boost disabled when configured

- **WHEN** `search.source_boost = 1.0`
- **THEN** no path-based boost applied
- **AND** source and test files ranked equally

---

### Requirement: Public Modifier Boost

The system SHALL boost public declarations over internal/private declarations.

Boost parameters:

- `public_boost` — 1.1x for signatures starting with "public"

#### Scenario: Public type ranked higher

- **WHEN** searching "ChunkStore implementations"
- **AND** results include `public actor GRDBChunkStore` and `actor MockChunkStore`
- **THEN** public declaration receives 1.1x boost
- **AND** GRDBChunkStore ranks higher than MockChunkStore

#### Scenario: Boost stacks with other boosts

- **WHEN** searching "what implements ChunkStore"
- **AND** GRDBChunkStore is public type declaration with ChunkStore conformance
- **THEN** receives: conformance_boost (1.5x) × public_boost (1.1x) × source_boost (1.1x)
- **AND** total boost is ~1.8x

## MODIFIED Requirements

### Requirement: Exact Symbol Matching

The system SHALL boost results with exact symbol matches for rare terms.

Boost parameters:

- `rare_term_threshold` — 10 occurrences (terms appearing < 10 times in index)
- `exact_symbol_boost` — 2.5x multiplier for exact symbol match (increased from 2.0x)

Detection:

- Query term frequency via ChunkStore
- If frequency < threshold, term is rare
- Check if symbols field contains exact term (case-sensitive)

#### Scenario: Boost rare term exact match

- **WHEN** searching "USearchError"
- **AND** term appears < 10 times in index
- **AND** chunk has "USearchError" in symbols list
- **THEN** chunk receives 2.5x boost
- **AND** ranks higher than substring matches

#### Scenario: No boost for common terms

- **WHEN** searching "search"
- **AND** term appears > 10 times in index
- **THEN** no exact symbol boost applied
- **AND** standard BM25 ranking used

#### Scenario: Boost stacks with conformance boost

- **WHEN** searching "ChunkStore"
- **AND** term is rare (< 10 occurrences)
- **AND** chunk is type declaration with "ChunkStore" in conformances
- **THEN** chunk receives both exact_symbol_boost (2.5x) and conformance_boost (1.5x)
- **AND** total boost is 3.75x

#### Scenario: BM25 prioritizes symbols field for rare terms

- **WHEN** searching rare term "USearchError"
- **THEN** BM25 search prioritizes matches in `symbols` field
- **AND** content-only matches ranked lower
