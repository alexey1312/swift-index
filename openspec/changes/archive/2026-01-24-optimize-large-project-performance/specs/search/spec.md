## ADDED Requirements

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

## MODIFIED Requirements

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
