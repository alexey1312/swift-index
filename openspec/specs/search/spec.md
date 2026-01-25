# search Specification

## Purpose

TBD - created by archiving change add-swiftindex-core. Update Purpose after archive.

## Requirements

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

### Requirement: Semantic Vector Search

The system SHALL support semantic search via vector similarity.

Similarity metric: Cosine similarity

#### Scenario: Semantic search returns similar chunks

- **WHEN** searching "how to authenticate users"
- **THEN** returns chunks semantically related to authentication
- **AND** results ordered by similarity score

#### Scenario: Semantic search respects limit

- **WHEN** searching with `limit: 5`
- **THEN** returns at most 5 results

#### Scenario: Semantic search with threshold

- **WHEN** searching with `min_similarity: 0.7`
- **THEN** only returns chunks with score >= 0.7

---

### Requirement: Hybrid Search with RRF Fusion

The system SHALL combine BM25 and semantic search using Reciprocal Rank Fusion.

RRF formula: `score = Σ 1/(k + rank)`

Default parameters:

- k: 60
- semantic_weight: 0.7
- bm25_weight: 0.3
- alpha: 0.7 (controls balance between RRF rank and normalized original score)

Scoring Logic:

- The final contribution of each method (BM25 or Semantic) is a weighted sum of its RRF rank score and its normalized original score.
- `contribution = weight * (alpha * rrfScore + (1 - alpha) * normalizedOriginalScore)`

#### Scenario: Hybrid search combines results

- **WHEN** searching "authentication flow"
- **THEN** BM25 and semantic results are combined
- **AND** final ranking uses hybrid scoring (rank + score)

#### Scenario: Hybrid handles disjoint sets

- **WHEN** BM25 returns {A, B, C}
- **AND** semantic returns {C, D, E}
- **THEN** combined results include all
- **AND** C is ranked higher (in both)

#### Scenario: Configurable weights

- **WHEN** `search.semantic_weight = 0.9`
- **THEN** semantic results dominate ranking

#### Scenario: Score-aware fusion

- **WHEN** BM25 returns result A with 0.99 score (exact match)
- **AND** Semantic returns result B with 0.6 score
- **THEN** A ranks significantly higher than B due to score component
- **AND** `alpha` parameter balances rank vs score influence

### Requirement: Multi-hop Search

The system SHALL support multi-hop search for deep code exploration.

Multi-hop algorithm:

1. Initial search returns seed results
2. Extract references from seed results
3. Search for referenced symbols
4. Merge and re-rank all results
5. Repeat for configured depth

#### Scenario: Multi-hop follows references

- **WHEN** searching "login" with depth 2
- **AND** login function calls "validateCredentials"
- **THEN** results include validateCredentials
- **AND** includes its dependencies

#### Scenario: Multi-hop respects depth limit

- **WHEN** searching with `depth: 1`
- **THEN** only direct references followed
- **AND** transitive references excluded

#### Scenario: Multi-hop deduplication

- **WHEN** same chunk reachable via multiple paths
- **THEN** chunk appears once in results
- **AND** score reflects multiple relevance signals

---

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

### Requirement: Path Filtering

The system SHALL support filtering results by file path.

#### Scenario: Filter by glob pattern

- **WHEN** searching with `file_filter: "Sources/Auth/**"`
- **THEN** only returns chunks from matching paths

#### Scenario: Filter by extension

- **WHEN** searching with `file_filter: "*.swift"`
- **THEN** only returns Swift file chunks

#### Scenario: Exclude pattern

- **WHEN** searching with `exclude_filter: "**/Tests/**"`
- **THEN** test file chunks are excluded

---

### Requirement: Symbol Search

The system SHALL support searching by symbol name.

#### Scenario: Search for function name

- **WHEN** searching symbol "authenticateUser"
- **THEN** returns chunk containing that function
- **AND** ranks exact symbol match highest

#### Scenario: Search for class name

- **WHEN** searching symbol "AuthenticationManager"
- **THEN** returns class declaration chunk
- **AND** includes methods of that class

---

### Requirement: Search Performance

The system SHALL complete searches within acceptable latency.

Performance targets:

- Simple search: < 100ms
- Hybrid search: < 200ms
- Multi-hop (depth 2): < 500ms
- **Path filtering (100 results): < 10ms** (with glob caching)

#### Scenario: Large index search

- **WHEN** index has 10,000+ chunks
- **THEN** search completes within targets
- **AND** results are relevant

#### Scenario: Glob filtering performance

- **WHEN** filtering 1,000 results by path pattern
- **THEN** filtering completes in < 50ms
- **AND** glob regex is compiled only once per unique pattern

### Requirement: Code Research Tool

The system SHALL provide deep architectural analysis via `code_research`.

Research capabilities:

- Find all implementations of protocol
- Trace call graph from entry point
- Identify related components
- Map dependencies between modules

#### Scenario: Protocol implementation search

- **WHEN** researching "implementations of AuthProtocol"
- **THEN** returns all conforming types
- **AND** includes extension conformances

#### Scenario: Call graph tracing

- **WHEN** researching "what calls login()"
- **THEN** returns callers of login function
- **AND** traces through call chain

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

### Requirement: Glob Pattern Caching

The system SHALL cache compiled glob patterns to avoid repeated regex compilation.

Cache parameters:

- Cache size: 100 patterns (hard-coded)
- Eviction policy: LRU (Least Recently Used)
- Scope: per `HybridSearchEngine` instance

#### Scenario: Pattern reused across results

- **WHEN** filtering 100 results with pattern `Sources/**/*.swift`
- **THEN** regex is compiled once
- **AND** cached compilation is reused for all 100 matches

#### Scenario: Cache eviction on overflow

- **WHEN** cache contains 100 patterns
- **AND** new pattern is added
- **THEN** least recently used pattern is evicted
- **AND** new pattern is cached

---

### Requirement: LRU Cache for Follow-Up Suggestions

The system SHALL use LRU (Least Recently Used) eviction policy for follow-up suggestion cache.

Cache parameters:

- Cache size: 50 entries (existing)
- Eviction policy: LRU (replaces FIFO)
- Key: normalized query + result summary prefix

#### Scenario: Frequently used queries retained

- **WHEN** cache contains 50 entries
- **AND** query "authentication" was accessed recently
- **AND** new query is added
- **THEN** least recently used entry is evicted
- **AND** "authentication" remains in cache

#### Scenario: Cache hit updates access order

- **WHEN** cached query is accessed
- **THEN** entry is moved to most recently used position
- **AND** entry is protected from immediate eviction

#### Scenario: Cold queries evicted first

- **WHEN** cache is full
- **AND** queries A, B, C were added in order
- **AND** query A was accessed again after C
- **AND** new query D is added
- **THEN** query B is evicted (oldest access)
- **AND** queries A, C, D remain

---

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
