## MODIFIED Requirements

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

## ADDED Requirements

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
