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

#### Scenario: Boost protocol definition

- **WHEN** query asks "ChunkStore protocol"
- **THEN** chunks with `kind == .protocol` are boosted by 1.3x

#### Scenario: Boost implementations

- **WHEN** query asks "what implements ChunkStore"
- **AND** chunk has "ChunkStore" in `conformances` list
- **THEN** chunk is boosted by 1.5x
