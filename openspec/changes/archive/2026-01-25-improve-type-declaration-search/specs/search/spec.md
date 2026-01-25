## ADDED Requirements

### Requirement: Exact Symbol Matching

The system SHALL boost results with exact symbol matches for rare terms.

Boost parameters:

- `rare_term_threshold` — 10 occurrences (terms appearing < 10 times in index)
- `exact_symbol_boost` — 2.0x multiplier for exact symbol match

#### Scenario: Boost rare term exact match

- **WHEN** searching "USearchError"
- **AND** term appears < 10 times in index
- **AND** chunk has "USearchError" in symbols list
- **THEN** chunk receives 2.0x boost
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
- **THEN** chunk receives both exact_symbol_boost (2.0x) and conformance_boost (1.5x)
- **AND** total boost is 3.0x

---

### Requirement: Conformance Index Lookup

The system SHALL maintain a dedicated conformance index for fast protocol implementation search.

Index structure:

- Table: `conformances(chunk_id, protocol_name)`
- Index: `idx_conformances_protocol` on `protocol_name`

#### Scenario: Find all implementations of protocol

- **WHEN** querying "what implements ChunkStore"
- **THEN** system queries conformance index
- **AND** returns all chunks with "ChunkStore" in conformances
- **AND** type declaration chunks ranked first

#### Scenario: Conformance lookup performance

- **WHEN** index has 5000+ chunks
- **AND** querying conformances for "Sendable"
- **THEN** lookup completes in < 10ms
- **AND** uses index scan, not table scan

#### Scenario: Extension conformances included

- **WHEN** `extension User: Codable` exists
- **AND** searching "implements Codable"
- **THEN** extension chunk is returned
- **AND** ranked with conformance boost

---

### Requirement: Type Declaration Priority

The system SHALL prioritize type declaration chunks for "what is X" and "implements X" queries.

Boost parameters:

- `type_declaration_boost` — 1.5x for type declaration chunks
- `conformance_implementation_boost` — 3.0x for type declarations matching conformance query

#### Scenario: Type declaration ranked first

- **WHEN** searching "GRDBChunkStore"
- **AND** index contains type declaration chunk and method chunks
- **THEN** type declaration chunk is ranked #1
- **AND** method chunks follow

#### Scenario: Implementation query returns type declarations

- **WHEN** searching "what implements ChunkStore protocol"
- **THEN** type declaration chunks with ChunkStore conformance are top results
- **AND** usage sites (let store: ChunkStore) ranked lower

#### Scenario: Protocol definition also returned

- **WHEN** searching "what implements ChunkStore"
- **THEN** ChunkStore protocol definition is in top-3
- **AND** implementing types are in top-5
- **AND** usage sites are ranked lower

## MODIFIED Requirements

### Requirement: Metadata-Aware Semantic Re-ranking

The system SHALL re-rank semantic search results based on query intent and metadata matches.

Boost factors:

- `protocol_kind_boost` (1.3x) - when query targets a protocol definition
- `conformance_match_boost` (1.5x) - when query asks for implementations of a type
- `type_declaration_boost` (1.5x) - when chunk is a type declaration
- `conformance_implementation_boost` (3.0x) - when type declaration matches conformance query
- `exact_symbol_boost` (2.0x) - when rare term exactly matches symbol name

#### Scenario: Boost protocol definition

- **WHEN** query asks "ChunkStore protocol"
- **THEN** chunks with `kind == .protocol` are boosted by 1.3x

#### Scenario: Boost implementations

- **WHEN** query asks "what implements ChunkStore"
- **AND** chunk has "ChunkStore" in `conformances` list
- **THEN** chunk is boosted by 1.5x

#### Scenario: Boost type declarations for conformance query

- **WHEN** query asks "what implements ChunkStore"
- **AND** chunk is type declaration with "ChunkStore" in conformances
- **THEN** chunk receives 3.0x boost (conformance_implementation_boost)
- **AND** ranks above method chunks and usage sites

#### Scenario: Boost exact symbol match

- **WHEN** searching rare term "USearchError"
- **AND** chunk has "USearchError" in symbols
- **THEN** chunk receives 2.0x boost
