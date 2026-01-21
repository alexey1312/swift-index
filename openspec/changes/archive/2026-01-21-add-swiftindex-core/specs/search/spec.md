## ADDED Requirements

### Requirement: BM25 Keyword Search

The system SHALL support BM25 keyword search via FTS5.

BM25 parameters:

- k1: 1.2 (term frequency saturation)
- b: 0.75 (length normalization)

#### Scenario: Keyword search returns ranked results

- **WHEN** searching "login authentication"
- **THEN** returns chunks containing keywords
- **AND** results ranked by BM25 score

#### Scenario: Empty query returns empty

- **WHEN** searching with empty string
- **THEN** returns empty result list
- **AND** no error raised

#### Scenario: Special characters handled

- **WHEN** searching "func login()"
- **THEN** parentheses are handled correctly
- **AND** returns matching functions

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

#### Scenario: Hybrid search combines results

- **WHEN** searching "authentication flow"
- **THEN** BM25 and semantic results are combined
- **AND** final ranking uses RRF

#### Scenario: Hybrid handles disjoint sets

- **WHEN** BM25 returns {A, B, C}
- **AND** semantic returns {C, D, E}
- **THEN** combined results include all
- **AND** C is ranked higher (in both)

#### Scenario: Configurable weights

- **WHEN** `search.semantic_weight = 0.9`
- **THEN** semantic results dominate ranking

---

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

The system SHALL return structured search results.

Result fields:

- `chunk` — matched CodeChunk
- `score` — relevance score (0-1)
- `matchType` — how matched (bm25, semantic, multi-hop)
- `highlights` — matching text spans

#### Scenario: Result includes highlights

- **WHEN** searching "authenticate"
- **THEN** results include highlight spans
- **AND** can be used for UI display

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

#### Scenario: Large index search

- **WHEN** index has 10,000+ chunks
- **THEN** search completes within targets
- **AND** results are relevant

---

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
